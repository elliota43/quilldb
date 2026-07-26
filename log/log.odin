package log

import "core:fmt"
import "core:os"

Log :: struct {
	file: ^os.File,
}

log_open :: proc(pathname: string) -> (^Log, os.Error) {
	f, err := os.open(pathname, {.Read, .Write, .Append})
	if err != nil {
		return nil, err
	}

	log := new(Log)
	log.file = f
	return log, nil
}

log_close :: proc(log: ^Log) {
	err := os.close(log.file)

	if err != nil {
		fmt.eprintfln("error closing log file: %v", err)
	}

	log.file = nil
	free(log)
}
