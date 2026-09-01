package ultra

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// SpoolWriter streams columnar CSR arrays directly to disk spools, maintaining only indptr in RAM (< 1 MB)
type SpoolWriter struct {
	tempDir          string
	targetsFile      *os.File
	durationsFile    *os.File
	flagsFile        *os.File
	targetsBuf       *bufio.Writer
	durationsBuf     *bufio.Writer
	flagsBuf         *bufio.Writer
	indptr           []uint64
	numStops         uint32
	tauMax           uint32
	currentStop      uint32
	totalShortcuts   uint64
	isFinalized      bool
	tempFilesClosed  bool
}

// NewSpoolWriter creates temporary spool files and initializes the streaming writer
func NewSpoolWriter(tempDir string, numStops uint32, tauMax uint32) (*SpoolWriter, error) {
	if tempDir == "" {
		tempDir = os.TempDir()
	}

	targetsPath := filepath.Join(tempDir, "ultra_targets.tmp")
	durationsPath := filepath.Join(tempDir, "ultra_durations.tmp")
	flagsPath := filepath.Join(tempDir, "ultra_flags.tmp")

	fTargets, err := os.Create(targetsPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create targets spool: %w", err)
	}

	fDurations, err := os.Create(durationsPath)
	if err != nil {
		fTargets.Close()
		return nil, fmt.Errorf("failed to create durations spool: %w", err)
	}

	fFlags, err := os.Create(flagsPath)
	if err != nil {
		fTargets.Close()
		fDurations.Close()
		return nil, fmt.Errorf("failed to create flags spool: %w", err)
	}

	return &SpoolWriter{
		tempDir:         tempDir,
		targetsFile:     fTargets,
		durationsFile:   fDurations,
		flagsFile:       fFlags,
		targetsBuf:      bufio.NewWriterSize(fTargets, 64*1024),
		durationsBuf:    bufio.NewWriterSize(fDurations, 64*1024),
		flagsBuf:        bufio.NewWriterSize(fFlags, 64*1024),
		indptr:          make([]uint64, numStops+1),
		numStops:        numStops,
		tauMax:          tauMax,
		currentStop:     0,
		totalShortcuts:  0,
		isFinalized:     false,
		tempFilesClosed: false,
	}, nil
}

// AppendStopShortcuts writes all shortcuts for the specified origin stop and updates indptr
func (sw *SpoolWriter) AppendStopShortcuts(originStop uint32, shortcuts []TransferCandidate) error {
	// Pad any skipped stops with current totalShortcuts offset
	for sw.currentStop < originStop {
		sw.indptr[sw.currentStop+1] = sw.totalShortcuts
		sw.currentStop++
	}

	for _, sc := range shortcuts {
		if err := binary.Write(sw.targetsBuf, binary.LittleEndian, sc.TargetStop); err != nil {
			return fmt.Errorf("failed to spool target stop: %w", err)
		}
		if err := binary.Write(sw.durationsBuf, binary.LittleEndian, sc.Duration); err != nil {
			return fmt.Errorf("failed to spool duration: %w", err)
		}
		if err := binary.Write(sw.flagsBuf, binary.LittleEndian, sc.Flags); err != nil {
			return fmt.Errorf("failed to spool flags: %w", err)
		}
		sw.totalShortcuts++
	}

	sw.indptr[originStop+1] = sw.totalShortcuts
	sw.currentStop = originStop + 1
	return nil
}

// FinalizeStopOffsets completes the indptr array up to numStops
func (sw *SpoolWriter) FinalizeStopOffsets() error {
	for sw.currentStop < sw.numStops {
		sw.indptr[sw.currentStop+1] = sw.totalShortcuts
		sw.currentStop++
	}

	if err := sw.targetsBuf.Flush(); err != nil {
		return err
	}
	if err := sw.durationsBuf.Flush(); err != nil {
		return err
	}
	if err := sw.flagsBuf.Flush(); err != nil {
		return err
	}

	sw.isFinalized = true
	return nil
}

// StitchToFile performs the final pass: writing the 32B header, indptr array, and appending spools
func (sw *SpoolWriter) StitchToFile(outputPath string) (*BinaryHeader, error) {
	if !sw.isFinalized {
		if err := sw.FinalizeStopOffsets(); err != nil {
			return nil, err
		}
	}

	// Close open spool handles prior to streaming read
	if !sw.tempFilesClosed {
		sw.targetsFile.Close()
		sw.durationsFile.Close()
		sw.flagsFile.Close()
		sw.tempFilesClosed = true
	}

	targetsPath := filepath.Join(sw.tempDir, "ultra_targets.tmp")
	durationsPath := filepath.Join(sw.tempDir, "ultra_durations.tmp")
	flagsPath := filepath.Join(sw.tempDir, "ultra_flags.tmp")
	defer os.Remove(targetsPath)
	defer os.Remove(durationsPath)
	defer os.Remove(flagsPath)

	outF, err := os.Create(outputPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create output file %s: %w", outputPath, err)
	}
	defer outF.Close()

	outBuf := bufio.NewWriterSize(outF, 128*1024)

	// 1. Construct and write 32-byte BinaryHeader
	header := BinaryHeader{
		MagicBytes:   MagicUltraCSR,
		Version:      uint32(SchemaVersion),
		NumStops:     sw.numStops,
		NumShortcuts: sw.totalShortcuts,
		TauMax:       sw.tauMax,
		Reserved:     [2]uint32{0, 0},
	}

	if err := binary.Write(outBuf, binary.LittleEndian, header); err != nil {
		return nil, fmt.Errorf("failed to write header: %w", err)
	}

	// 2. Write indptr array (|S| + 1 entries)
	for _, off := range sw.indptr {
		if err := binary.Write(outBuf, binary.LittleEndian, off); err != nil {
			return nil, fmt.Errorf("failed to write indptr offset: %w", err)
		}
	}

	if err := outBuf.Flush(); err != nil {
		return nil, fmt.Errorf("failed to flush indptr: %w", err)
	}

	// 3. Append Targets Spool
	if err := appendFileToWriter(targetsPath, outF); err != nil {
		return nil, fmt.Errorf("failed to append targets: %w", err)
	}

	// 4. Append Durations Spool
	if err := appendFileToWriter(durationsPath, outF); err != nil {
		return nil, fmt.Errorf("failed to append durations: %w", err)
	}

	// 5. Append Flags Spool
	if err := appendFileToWriter(flagsPath, outF); err != nil {
		return nil, fmt.Errorf("failed to append flags: %w", err)
	}

	if err := outF.Sync(); err != nil {
		return nil, fmt.Errorf("failed to sync output file: %w", err)
	}

	return &header, nil
}

// Close ensures temporary files are closed and deleted if not stitched
func (sw *SpoolWriter) Close() {
	if !sw.tempFilesClosed {
		sw.targetsFile.Close()
		sw.durationsFile.Close()
		sw.flagsFile.Close()
		sw.tempFilesClosed = true
	}
	os.Remove(filepath.Join(sw.tempDir, "ultra_targets.tmp"))
	os.Remove(filepath.Join(sw.tempDir, "ultra_durations.tmp"))
	os.Remove(filepath.Join(sw.tempDir, "ultra_flags.tmp"))
}

func appendFileToWriter(srcPath string, dst io.Writer) error {
	f, err := os.Open(srcPath)
	if err != nil {
		return err
	}
	defer f.Close()

	buf := make([]byte, 64*1024)
	_, err = io.CopyBuffer(dst, f, buf)
	return err
}
