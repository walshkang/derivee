import Foundation

/// Pure-Swift POSIX ustar / GNU Tar archive extractor and builder.
public struct TarExtractor: Sendable {
    public static let blockSize = 512
    
    public struct TarEntry: Sendable {
        public let name: String
        public let size: Int
        public let isDirectory: Bool
        public let data: Data
        
        public init(name: String, size: Int, isDirectory: Bool, data: Data) {
            self.name = name
            self.size = size
            self.isDirectory = isDirectory
            self.data = data
        }
    }
    
    /// Parses tar archive data into in-memory entries.
    public static func parse(tarData: Data) throws -> [TarEntry] {
        var entries: [TarEntry] = []
        var offset = 0
        let totalBytes = tarData.count
        
        while offset + blockSize <= totalBytes {
            let headerBlock = tarData.subdata(in: offset..<(offset + blockSize))
            
            // Check for end of archive (all zeroes in block)
            if headerBlock.allSatisfy({ $0 == 0 }) {
                // If the next block is also all zeros, or we're at EOF, stop
                break
            }
            
            // 1. Parse File Name (0..<100) & Prefix (345..<500)
            let nameData = headerBlock.subdata(in: 0..<100)
            let rawName = extractString(from: nameData)
            
            let prefixData = headerBlock.subdata(in: 345..<500)
            let rawPrefix = extractString(from: prefixData)
            
            var fullName = rawName
            if !rawPrefix.isEmpty {
                fullName = "\(rawPrefix)/\(rawName)"
            }
            
            fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if fullName.isEmpty || fullName.hasPrefix("._") || fullName.contains("/._") || fullName.hasPrefix("PaxHeader/") || fullName.contains("/PaxHeader/") {
                offset += blockSize
                continue
            }
            
            // 2. Parse Size (124..<136) in octal
            let sizeData = headerBlock.subdata(in: 124..<136)
            guard let size = parseOctal(from: sizeData) else {
                throw CityPackError.invalidArchive(reason: "Malformed octal file size in tar header at offset \(offset)")
            }
            
            // 3. Parse Type Flag (156)
            let typeFlag = headerBlock[156]
            let isDirectory = (typeFlag == 0x35) || fullName.hasSuffix("/") // '5' is directory
            
            offset += blockSize
            
            // 4. Extract Payload
            if isDirectory || size == 0 {
                entries.append(TarEntry(name: fullName, size: 0, isDirectory: true, data: Data()))
            } else {
                guard offset + size <= totalBytes else {
                    throw CityPackError.invalidArchive(reason: "Tar entry '\(fullName)' size \(size) exceeds archive bounds")
                }
                
                let fileData = tarData.subdata(in: offset..<(offset + size))
                entries.append(TarEntry(name: fullName, size: size, isDirectory: false, data: fileData))
                
                // Advance by padded 512-byte blocks
                let paddedBlocks = (size + blockSize - 1) / blockSize
                offset += paddedBlocks * blockSize
            }
        }
        
        return entries
    }
    
    /// Extracts tar archive data to a target directory with path traversal protection.
    public static func extract(tarData: Data, to destinationURL: URL, fileManager: FileManager = .default) throws {
        let entries = try parse(tarData: tarData)
        let destinationCanonicalPath = destinationURL.standardizedFileURL.path
        
        for entry in entries {
            let cleanName = sanitizePath(entry.name)
            guard !cleanName.isEmpty else { continue }
            
            let fileURL = destinationURL.appendingPathComponent(cleanName).standardizedFileURL
            let filePath = fileURL.path
            
            // Security: Prevent path traversal (e.g. ../../)
            guard filePath.hasPrefix(destinationCanonicalPath) else {
                throw CityPackError.invalidArchive(reason: "Path traversal detected in archive entry: '\(entry.name)'")
            }
            
            if entry.isDirectory {
                try fileManager.createDirectory(at: fileURL, withIntermediateDirectories: true, attributes: nil)
            } else {
                let parentDirectory = fileURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)
                try entry.data.write(to: fileURL, options: .atomic)
            }
        }
    }
    
    /// Helper to create a POSIX ustar Tar archive from in-memory file data (used for testing and pack generation).
    public static func createTarArchive(files: [(name: String, data: Data)]) -> Data {
        var archive = Data()
        
        for file in files {
            var header = Data(count: blockSize)
            
            // 1. File name (0..<100)
            let nameData = file.name.data(using: .utf8) ?? Data()
            header.replaceSubrange(0..<min(nameData.count, 100), with: nameData.prefix(100))
            
            // 2. Mode (100..<108) -> 0000644\0
            let mode = "0000644\0".data(using: .ascii)!
            header.replaceSubrange(100..<108, with: mode)
            
            // 3. UID / GID (108..<124)
            let uidGid = "0000000\00000000\0".data(using: .ascii)!
            header.replaceSubrange(108..<124, with: uidGid)
            
            // 4. File size (124..<136) -> 11 octal digits + space/null
            let sizeOctal = String(format: "%011o ", file.data.count)
            if let sizeData = sizeOctal.data(using: .ascii) {
                header.replaceSubrange(124..<136, with: sizeData.prefix(12))
            }
            
            // 5. Modification time (136..<148)
            let mtime = String(format: "%011o ", Int(Date().timeIntervalSince1970))
            if let mtimeData = mtime.data(using: .ascii) {
                header.replaceSubrange(136..<148, with: mtimeData.prefix(12))
            }
            
            // 6. Type flag (156) -> '0' normal file
            header[156] = 0x30
            
            // 7. Magic "ustar\0" (257..<263) & version "00" (263..<265)
            let magic = "ustar\000".data(using: .ascii)!
            header.replaceSubrange(257..<265, with: magic)
            
            // 8. Checksum (148..<156) -> sum of all bytes in header with checksum field treated as ASCII spaces (0x20)
            for i in 148..<156 {
                header[i] = 0x20
            }
            let sum = header.reduce(0) { $0 + Int($1) }
            let checksumOctal = String(format: "%06o\0 ", sum)
            if let checksumData = checksumOctal.data(using: .ascii) {
                header.replaceSubrange(148..<156, with: checksumData.prefix(8))
            }
            
            // Append header
            archive.append(header)
            
            // Append file data
            archive.append(file.data)
            
            // Pad to 512-byte block boundary
            let remainder = file.data.count % blockSize
            if remainder > 0 {
                let paddingSize = blockSize - remainder
                archive.append(Data(count: paddingSize))
            }
        }
        
        // Two 512-byte zero blocks mark EOF
        archive.append(Data(count: blockSize * 2))
        return archive
    }
    
    // MARK: - Private Helpers
    
    private static func extractString(from data: Data) -> String {
        guard let nullIndex = data.firstIndex(of: 0) else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return String(data: data.subdata(in: 0..<nullIndex), encoding: .utf8) ?? ""
    }
    
    private static func parseOctal(from data: Data) -> Int? {
        let string = extractString(from: data).trimmingCharacters(in: .whitespacesAndNewlines)
        if string.isEmpty { return 0 }
        return Int(string, radix: 8)
    }
    
    private static func sanitizePath(_ path: String) -> String {
        var clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasPrefix("/") {
            clean.removeFirst()
        }
        return clean
    }
}
