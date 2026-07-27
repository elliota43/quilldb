package wal

import "core:fmt"
import "core:mem"
import "core:os"
import "core:sys/posix"

Log :: struct {
	file: ^os.File,
}

// Mapped gives a []u8 slice view into the mmap'ed file contents
Mapped :: struct {
	data: []u8,
}

open :: proc(pathname: string) -> (^Log, os.Error) {
	f, err := os.open(pathname, {.Read, .Write, .Append, .Create})
	if err != nil {
		return nil, err
	}

	log := new(Log)
	log.file = f
	return log, nil
}

close :: proc(log: ^Log) {
	err := os.close(log.file)

	if err != nil {
		fmt.eprintfln("error closing log file: %v", err)
	}

	log.file = nil
	free(log)
}

// write writes the log entry to disk and sync's the file for durability.
// os.write() returns a non-nil error if the number of bytes written is less than the
//
write :: proc(log: ^Log, data: []u8) -> os.Error {
	_, err := os.write(log.file, data)
	if err != nil {
		return err
	}

	return os.sync(log.file)
}

// map_readonly maps the current file contents for scanning.
// NOTE: contents are read-only.  DO NOT FREE / DELETE the memory
map_readonly :: proc(log: ^Log) -> (m: Mapped, err: os.Error) {
	size, serr := os.file_size(log.file)
	if serr != nil {
		return {}, serr
	}

	if size == 0 {
		return {}, nil
	}

	fd := posix.FD(os.fd(log.file))
	ptr := posix.mmap(nil, uint(size), {.READ}, {.PRIVATE}, fd, 0)

	if ptr == posix.MAP_FAILED {
		return {}, posix.errno()
	}

	m.data = mem.slice_ptr(cast([^]u8)ptr, int(size))
	return m, nil
}

unmap :: proc(m: ^Mapped) {
	if m.data == nil do return

	posix.munmap(raw_data(m.data), uint(len(m.data)))
	m.data = nil
}

truncate :: proc(log: ^Log, size: i64) -> os.Error {
	return os.truncate(log.file, size)
}

seek_end :: proc(log: ^Log) -> os.Error {
	_, err := os.seek(log.file, 0, .End)
	return err
}
