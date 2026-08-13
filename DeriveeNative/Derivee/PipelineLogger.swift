import Foundation
import os

public final class PipelineLogger: @unchecked Sendable {
    public static let shared = PipelineLogger()
    
    private let osLogger = Logger(subsystem: "com.derivee", category: "Pipeline")
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.derivee.pipelinelogger", qos: .utility)
    private var fileHandle: FileHandle?
    private let dateFormatter: ISO8601DateFormatter
    
    private init() {
        let fileManager = FileManager.default
        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.logFileURL = docsURL.appendingPathComponent("pipeline_debug.log")
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter = formatter
        
        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: nil)
        }
        self.fileHandle = try? FileHandle(forWritingTo: logFileURL)
        self.fileHandle?.seekToEndOfFile()
        
        let header = "\n=== Dérivée Pipeline Log Started at \(Date()) ===\n"
        if let data = header.data(using: .utf8) {
            self.fileHandle?.write(data)
        }
    }
    
    public func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        
        // 1. Stdout print for active Xcode console
        print(message)
        
        // 2. Apple Unified Logging for Console.app / sysdiagnose
        osLogger.info("\(message, privacy: .public)")
        
        // 3. Persistent Documents/pipeline_debug.log file for untethered field testing
        queue.async { [weak self] in
            guard let self = self, let handle = self.fileHandle, let data = line.data(using: .utf8) else { return }
            handle.write(data)
        }
    }
}

public func logPipeline(_ message: String) {
    PipelineLogger.shared.log(message)
}
