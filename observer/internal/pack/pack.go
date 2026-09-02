package pack

import (
	"archive/tar"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/klauspost/compress/zstd"
)

// CreateCityPack packages city_config.json, transit.sqlite, and transit-lines.geojson into a .pack.zst archive
func CreateCityPack(configPath, transitDBPath, geojsonPath, outputPath string) (*CityManifestEntry, error) {
	return CreateCityPackWithAssets(configPath, transitDBPath, geojsonPath, nil, outputPath)
}

// CreateCityPackV2 packages all standard version 2 assets into a .pack.zst archive
func CreateCityPackV2(configPath, transitDBPath, geojsonPath, timetablePath, ultraPath, walkGraphPath, outputPath string) (*CityManifestEntry, error) {
	extraAssets := make(map[string]string)
	if timetablePath != "" {
		extraAssets["timetable.bin"] = timetablePath
	}
	if ultraPath != "" {
		extraAssets["ultra_transfers.csr"] = ultraPath
	}
	if walkGraphPath != "" {
		extraAssets["walk_graph.bin"] = walkGraphPath
	}
	return CreateCityPackWithAssets(configPath, transitDBPath, geojsonPath, extraAssets, outputPath)
}

// CreateCityPackWithAssets packages base assets plus optional extra binary assets (e.g. timetable.bin) into .pack.zst
func CreateCityPackWithAssets(configPath, transitDBPath, geojsonPath string, extraAssets map[string]string, outputPath string) (*CityManifestEntry, error) {
	cfg, err := LoadCityConfig(configPath)
	if err != nil {
		return nil, fmt.Errorf("invalid config: %w", err)
	}

	outFile, err := os.Create(outputPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create output file %s: %w", outputPath, err)
	}
	defer outFile.Close()

	// Wrap output with SHA-256 hasher
	hasher := sha256.New()
	multiOut := io.MultiWriter(outFile, hasher)

	// Wrap with Zstandard encoder (maximum compression level for static distributions)
	zstdWriter, err := zstd.NewWriter(multiOut, zstd.WithEncoderLevel(zstd.SpeedBestCompression))
	if err != nil {
		return nil, fmt.Errorf("failed to create zstd writer: %w", err)
	}
	defer zstdWriter.Close()

	tarWriter := tar.NewWriter(zstdWriter)
	defer tarWriter.Close()

	filesToPack := []struct {
		ArchiveName string
		SourcePath  string
	}{
		{"city_config.json", configPath},
		{"transit.sqlite", transitDBPath},
		{"transit-lines.geojson", geojsonPath},
	}

	for archiveName, srcPath := range extraAssets {
		if srcPath != "" {
			filesToPack = append(filesToPack, struct {
				ArchiveName string
				SourcePath  string
			}{archiveName, srcPath})
		}
	}

	var totalUncompressedSize int64

	for _, fileEntry := range filesToPack {
		info, err := os.Stat(fileEntry.SourcePath)
		if err != nil {
			return nil, fmt.Errorf("failed to stat file %s: %w", fileEntry.SourcePath, err)
		}

		header := &tar.Header{
			Name:    fileEntry.ArchiveName,
			Size:    info.Size(),
			Mode:    0644,
			ModTime: info.ModTime(),
		}

		if err := tarWriter.WriteHeader(header); err != nil {
			return nil, fmt.Errorf("failed to write tar header for %s: %w", fileEntry.ArchiveName, err)
		}

		srcFile, err := os.Open(fileEntry.SourcePath)
		if err != nil {
			return nil, fmt.Errorf("failed to open file %s: %w", fileEntry.SourcePath, err)
		}

		written, err := io.Copy(tarWriter, srcFile)
		srcFile.Close()
		if err != nil {
			return nil, fmt.Errorf("failed to copy file %s to archive: %w", fileEntry.SourcePath, err)
		}

		totalUncompressedSize += written
	}

	// Close tar and zstd writers to flush all data
	if err := tarWriter.Close(); err != nil {
		return nil, fmt.Errorf("failed to flush tar writer: %w", err)
	}
	if err := zstdWriter.Close(); err != nil {
		return nil, fmt.Errorf("failed to flush zstd writer: %w", err)
	}

	// Get final compressed file size
	outInfo, err := outFile.Stat()
	if err != nil {
		return nil, fmt.Errorf("failed to stat output file: %w", err)
	}

	hashStr := hex.EncodeToString(hasher.Sum(nil))

	versionStr := fmt.Sprintf("%d.0.0", cfg.Version)
	if cfg.Version == 1 {
		versionStr = "1.1.0"
	}

	return &CityManifestEntry{
		Slug:                  cfg.Slug,
		DisplayName:           cfg.DisplayName,
		Region:                cfg.Region,
		CompressedSizeBytes:   outInfo.Size(),
		UncompressedSizeBytes: totalUncompressedSize,
		IsBundled:             cfg.Slug == "nyc",
		Version:               versionStr,
		SHA256:                hashStr,
	}, nil
}

// ExtractCityPack extracts a .pack.zst archive into the target directory
func ExtractCityPack(packPath, targetDir string) error {
	packFile, err := os.Open(packPath)
	if err != nil {
		return fmt.Errorf("failed to open pack file %s: %w", packPath, err)
	}
	defer packFile.Close()

	zstdReader, err := zstd.NewReader(packFile)
	if err != nil {
		return fmt.Errorf("failed to create zstd reader: %w", err)
	}
	defer zstdReader.Close()

	tarReader := tar.NewReader(zstdReader)

	if err := os.MkdirAll(targetDir, 0755); err != nil {
		return fmt.Errorf("failed to create target directory %s: %w", targetDir, err)
	}

	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("error reading tar entry: %w", err)
		}

		cleanName := filepath.Clean(header.Name)
		if filepath.IsAbs(cleanName) || cleanName == ".." {
			continue // Prevent zip-slip
		}

		targetPath := filepath.Join(targetDir, cleanName)

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(targetPath, 0755); err != nil {
				return err
			}
		case tar.TypeReg:
			outF, err := os.OpenFile(targetPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, header.FileInfo().Mode())
			if err != nil {
				return fmt.Errorf("failed to create extracted file %s: %w", targetPath, err)
			}
			if _, err := io.Copy(outF, tarReader); err != nil {
				outF.Close()
				return fmt.Errorf("failed to write extracted file %s: %w", targetPath, err)
			}
			outF.Close()
		}
	}

	return nil
}

// VerifyCityPack checks that a .pack.zst archive can be decompressed and contains all required files
func VerifyCityPack(packPath string) error {
	packFile, err := os.Open(packPath)
	if err != nil {
		return fmt.Errorf("failed to open pack file: %w", err)
	}
	defer packFile.Close()

	zstdReader, err := zstd.NewReader(packFile)
	if err != nil {
		return fmt.Errorf("failed to create zstd reader: %w", err)
	}
	defer zstdReader.Close()

	tarReader := tar.NewReader(zstdReader)
	foundFiles := make(map[string]bool)
	var configBytes []byte

	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("tar reading error: %w", err)
		}
		foundFiles[header.Name] = true

		if header.Name == "city_config.json" {
			var buf bytes.Buffer
			if _, err := io.Copy(&buf, tarReader); err != nil {
				return fmt.Errorf("failed to read city_config.json: %w", err)
			}
			configBytes = buf.Bytes()
		}
	}

	requiredFiles := []string{"city_config.json", "transit.sqlite", "transit-lines.geojson"}
	for _, rf := range requiredFiles {
		if !foundFiles[rf] {
			return fmt.Errorf("missing required file in pack: %s", rf)
		}
	}

	if len(configBytes) > 0 {
		var cfg CityConfig
		if err := json.Unmarshal(configBytes, &cfg); err == nil {
			if cfg.Version >= 2 || cfg.Routing != nil {
				routingFiles := []string{"timetable.bin", "ultra_transfers.csr", "walk_graph.bin"}
				if cfg.Routing != nil {
					if cfg.Routing.TimetableBinFile != "" {
						routingFiles[0] = cfg.Routing.TimetableBinFile
					}
					if cfg.Routing.UltraCsrFile != "" {
						routingFiles[1] = cfg.Routing.UltraCsrFile
					}
					if cfg.Routing.WalkGraphFile != "" {
						routingFiles[2] = cfg.Routing.WalkGraphFile
					}
				}
				for _, rf := range routingFiles {
					if !foundFiles[rf] {
						return fmt.Errorf("missing required routing file in v2 pack: %s", rf)
					}
				}
			}
		}
	}

	return nil
}
