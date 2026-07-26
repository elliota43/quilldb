package wal

import "core:fmt"
import "core:os"

Log :: struct {
	file: ^os.File,
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
