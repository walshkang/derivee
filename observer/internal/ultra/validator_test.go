package ultra

import (
	"bytes"
	"encoding/binary"
	"testing"
)

func TestValidatorNegativeCorruptions(t *testing.T) {
	// 1. Corrupt Magic
	buf := new(bytes.Buffer)
	header := BinaryHeader{
		MagicBytes:   0xDEADBEEF, // Bad magic
		Version:      1,
		NumStops:     2,
		NumShortcuts: 1,
		TauMax:       900,
	}
	binary.Write(buf, binary.LittleEndian, header)
	// Write dummy payload matching expected size: indptr (3*8=24B) + target (4B) + dur (2B) + flags (1B) = 31B
	buf.Write(make([]byte, 31))

	r := bytes.NewReader(buf.Bytes())
	if err := ValidateUltraCSR(r, int64(buf.Len())); err == nil {
		t.Errorf("expected error for invalid magic, got nil")
	}

	// 2. Corrupt File Size Truncation
	buf2 := new(bytes.Buffer)
	header.MagicBytes = MagicUltraCSR
	binary.Write(buf2, binary.LittleEndian, header)
	buf2.Write(make([]byte, 10)) // truncated payload

	r2 := bytes.NewReader(buf2.Bytes())
	if err := ValidateUltraCSR(r2, int64(buf2.Len())); err == nil {
		t.Errorf("expected error for truncated file size, got nil")
	}

	// 3. Monotonicity violation in indptr
	buf3 := new(bytes.Buffer)
	binary.Write(buf3, binary.LittleEndian, header)
	// indptr: [0, 2, 1] (non-monotonic)
	binary.Write(buf3, binary.LittleEndian, uint64(0))
	binary.Write(buf3, binary.LittleEndian, uint64(2))
	binary.Write(buf3, binary.LittleEndian, uint64(1))
	buf3.Write(make([]byte, 7)) // targets (4B) + dur (2B) + flags (1B)

	r3 := bytes.NewReader(buf3.Bytes())
	if err := ValidateUltraCSR(r3, int64(buf3.Len())); err == nil {
		t.Errorf("expected error for non-monotonic indptr, got nil")
	}
}
