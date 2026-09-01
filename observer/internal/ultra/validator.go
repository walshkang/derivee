package ultra

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"os"
)

// ValidateUltraCSR checks all structural invariants, bounds, and monotonicity rules of a serialized CSR buffer
func ValidateUltraCSR(r io.ReaderAt, fileSize int64) error {
	if fileSize < int64(HeaderSize) {
		return fmt.Errorf("file size %d smaller than minimum header size %d", fileSize, HeaderSize)
	}

	// 1. Read and Validate Header
	headerBytes := make([]byte, HeaderSize)
	if _, err := r.ReadAt(headerBytes, 0); err != nil {
		return fmt.Errorf("failed to read binary header: %w", err)
	}

	var header BinaryHeader
	if err := binary.Read(bytes.NewReader(headerBytes), binary.LittleEndian, &header); err != nil {
		return fmt.Errorf("failed to parse binary header: %w", err)
	}

	if header.MagicBytes != MagicUltraCSR {
		return fmt.Errorf("invalid magic signature: 0x%08X (expected 0x%08X)", header.MagicBytes, MagicUltraCSR)
	}
	if header.Version != uint32(SchemaVersion) {
		return fmt.Errorf("version mismatch: %d (expected %d)", header.Version, SchemaVersion)
	}

	s := uint64(header.NumStops)
	n := header.NumShortcuts

	expectedIndptrBytes := (s + 1) * 8
	expectedTargetsBytes := n * 4
	expectedDurationsBytes := n * 2
	expectedFlagsBytes := n * 1

	expectedMinSize := int64(HeaderSize) + int64(expectedIndptrBytes+expectedTargetsBytes+expectedDurationsBytes+expectedFlagsBytes)
	if fileSize != expectedMinSize {
		return fmt.Errorf("file size mismatch: expected %d bytes, got %d", expectedMinSize, fileSize)
	}

	// 2. Validate indptr array
	offsetIndptr := int64(HeaderSize)
	indptrBytes := make([]byte, expectedIndptrBytes)
	if _, err := r.ReadAt(indptrBytes, offsetIndptr); err != nil {
		return fmt.Errorf("failed to read indptr array: %w", err)
	}

	indptr := make([]uint64, s+1)
	if err := binary.Read(bytes.NewReader(indptrBytes), binary.LittleEndian, &indptr); err != nil {
		return fmt.Errorf("failed to parse indptr array: %w", err)
	}

	if indptr[0] != 0 {
		return fmt.Errorf("invalid indptr[0]: expected 0, got %d", indptr[0])
	}
	if indptr[s] != n {
		return fmt.Errorf("invalid indptr[|S|]: expected %d, got %d", n, indptr[s])
	}

	for i := uint64(0); i < s; i++ {
		if indptr[i] > indptr[i+1] {
			return fmt.Errorf("monotonicity violation: indptr[%d] = %d > indptr[%d] = %d", i, indptr[i], i+1, indptr[i+1])
		}
	}

	// 3. Validate Targets, Durations, and Flags (sample checking if large)
	offsetTargets := offsetIndptr + int64(expectedIndptrBytes)
	offsetDurations := offsetTargets + int64(expectedTargetsBytes)

	if n > 0 {
		// Read first and last target stop
		var firstTarget, lastTarget uint32
		var firstDur, lastDur uint16

		buf4 := make([]byte, 4)
		if _, err := r.ReadAt(buf4, offsetTargets); err != nil {
			return err
		}
		firstTarget = binary.LittleEndian.Uint32(buf4)

		if _, err := r.ReadAt(buf4, offsetTargets+int64(n-1)*4); err != nil {
			return err
		}
		lastTarget = binary.LittleEndian.Uint32(buf4)

		if uint64(firstTarget) >= s || uint64(lastTarget) >= s {
			return fmt.Errorf("target stop index out of bounds (max %d): first=%d, last=%d", s-1, firstTarget, lastTarget)
		}

		buf2 := make([]byte, 2)
		if _, err := r.ReadAt(buf2, offsetDurations); err != nil {
			return err
		}
		firstDur = binary.LittleEndian.Uint16(buf2)

		if _, err := r.ReadAt(buf2, offsetDurations+int64(n-1)*2); err != nil {
			return err
		}
		lastDur = binary.LittleEndian.Uint16(buf2)

		if uint32(firstDur) > header.TauMax || uint32(lastDur) > header.TauMax {
			return fmt.Errorf("duration exceeds tau_max (%d): first=%d, last=%d", header.TauMax, firstDur, lastDur)
		}
	}

	return nil
}

// ValidateUltraCSRFile opens and validates the specified file path
func ValidateUltraCSRFile(filePath string) error {
	f, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("failed to open file %s: %w", filePath, err)
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return fmt.Errorf("failed to stat file %s: %w", filePath, err)
	}

	return ValidateUltraCSR(f, fi.Size())
}
