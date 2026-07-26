package wal

import "core:bytes"
import "core:os"
import "core:testing"

@(test)
test_write_roundtrip :: proc(t: ^testing.T) {
	path := "test_log_roundtrip.log"
	os.remove(path)
	defer os.remove(path)

	l, err := open(path)
	testing.expect(t, err == nil)
	defer close(l)

	payload := []u8{1, 2, 3, 4}
	testing.expect(t, write(l, payload) == nil)

	data, rerr := os.read_entire_file(path, context.allocator)

	defer delete(data)
	testing.expect(t, rerr == nil)
	testing.expect(t, bytes.equal(data, payload))
}
