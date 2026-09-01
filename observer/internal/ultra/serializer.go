package ultra

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
)

// ReadUltraCSR deserializes a binary ULTRA CSR file into an in-memory UltraCSR struct
func ReadUltraCSR(r io.ReaderAt, fileSize int64) (*UltraCSR, error) {
	if err := ValidateUltraCSR(r, fileSize); err != nil {
		return nil, fmt.Errorf("invalid binary format: %w", err)
	}

	headerBytes := make([]byte, HeaderSize)
	if _, err := r.ReadAt(headerBytes, 0); err != nil {
		return nil, fmt.Errorf("failed to read header: %w", err)
	}

	var header BinaryHeader
	if err := binary.Read(bytes.NewReader(headerBytes), binary.LittleEndian, &header); err != nil {
		return nil, fmt.Errorf("failed to parse header: %w", err)
	}

	s := uint64(header.NumStops)
	n := header.NumShortcuts

	// 1. Read indptr array
	indptr := make([]uint64, s+1)
	offsetIndptr := int64(HeaderSize)
	indptrBytes := make([]byte, (s+1)*8)
	if _, err := r.ReadAt(indptrBytes, offsetIndptr); err != nil {
		return nil, fmt.Errorf("failed to read indptr: %w", err)
	}
	if err := binary.Read(bytes.NewReader(indptrBytes), binary.LittleEndian, &indptr); err != nil {
		return nil, fmt.Errorf("failed to parse indptr: %w", err)
	}

	// 2. Read target_stops array
	targetStops := make([]uint32, n)
	offsetTargets := offsetIndptr + int64((s+1)*8)
	if n > 0 {
		targetsBytes := make([]byte, n*4)
		if _, err := r.ReadAt(targetsBytes, offsetTargets); err != nil {
			return nil, fmt.Errorf("failed to read target_stops: %w", err)
		}
		if err := binary.Read(bytes.NewReader(targetsBytes), binary.LittleEndian, &targetStops); err != nil {
			return nil, fmt.Errorf("failed to parse target_stops: %w", err)
		}
	}

	// 3. Read durations_sec array
	durationsSec := make([]uint16, n)
	offsetDurations := offsetTargets + int64(n*4)
	if n > 0 {
		durationsBytes := make([]byte, n*2)
		if _, err := r.ReadAt(durationsBytes, offsetDurations); err != nil {
			return nil, fmt.Errorf("failed to read durations_sec: %w", err)
		}
		if err := binary.Read(bytes.NewReader(durationsBytes), binary.LittleEndian, &durationsSec); err != nil {
			return nil, fmt.Errorf("failed to parse durations_sec: %w", err)
		}
	}

	// 4. Read flags array
	flags := make([]uint8, n)
	offsetFlags := offsetDurations + int64(n*2)
	if n > 0 {
		flagsBytes := make([]byte, n*1)
		if _, err := r.ReadAt(flagsBytes, offsetFlags); err != nil {
			return nil, fmt.Errorf("failed to read flags: %w", err)
		}
		copy(flags, flagsBytes)
	}

	return &UltraCSR{
		Header:       header,
		Indptr:       indptr,
		TargetStops:  targetStops,
		DurationsSec: durationsSec,
		Flags:        flags,
	}, nil
}
