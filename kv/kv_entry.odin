package kv

import "core:bytes"
import "core:encoding/endian"

KV_Entry_Type :: enum (u8) {
	Edit,
	Delete,
}

KV_Entry :: struct {
	type:  KV_Entry_Type,
	key:   []u8,
	value: []u8,
}

// make_kv_entry returns a KV_Entry populated with the appropriate type.  Key and value are optional.
make_kv_entry :: proc(type: KV_Entry_Type, key: []u8 = nil, value: []u8 = nil) -> KV_Entry {
	return KV_Entry{type = type, key = key, value = value}
}

// destroy_kv_entry borrows key/value pairs **unless** produced by deserialized.
// Only call this for deserialized entries.
destroy_kv_entry :: proc(kv: ^KV_Entry) {
	delete(kv.key)
	delete(kv.value)
	kv^ = {}
}

// serialize returns a serialized []u8 buffer in the following format:
// [Type (1 byte) | Key Len (4 bytes) | Value Len (4 bytes) | Key (variable)... | Value (variable)... ]
// The buffer is a dynamically allocated array that must be freed by the caller when done.
serialize :: proc(kv: ^KV_Entry, allocator := context.allocator) -> (data: []u8, err: KV_Error) {
	key_len := len(kv.key)
	value_len := 0 if kv.type == .Delete else len(kv.value)
	total := 1 + 4 + 4 + key_len + value_len

	buf := make([]u8, total, allocator)

	buf[0] = u8(kv.type)
	endian.put_u32(buf[1:5], .Little, u32(key_len))
	endian.put_u32(buf[5:9], .Little, u32(value_len))
	copy(buf[9:], kv.key)

	if value_len > 0 {
		copy(buf[9 + key_len:], kv.value)
	}

	return buf, .None
}

deserialize :: proc(data: []u8, allocator := context.allocator) -> (KV_Entry, KV_Error) {
	entry, size, err := try_decode_entry(data, allocator)
	if err != .None {
		return {}, err
	}

	if size != len(data) {
		destroy_kv_entry(&entry)
		return {}, .Invalid_Format
	}

	return entry, .None
}

// try_decode_entry tries to decode the next KV_Entry from the raw byte data.
try_decode_entry :: proc(
	data: []u8,
	allocator := context.allocator,
) -> (
	entry: KV_Entry,
	size: int,
	err: KV_Error,
) {
	if len(data) < 9 {
		return {}, 0, .Incomplete_Record
	}

	type := KV_Entry_Type(data[0])
	if type != .Edit && type != .Delete {
		return {}, 0, .Invalid_Format
	}

	key_len, ok_k := endian.get_u32(data[1:5], .Little)
	value_len, ok_v := endian.get_u32(data[5:9], .Little)
	if !ok_k || !ok_v {
		return {}, 0, .Invalid_Format
	}

	need := 9 + int(key_len) + int(value_len)
	if len(data) < need {
		return {}, 0, .Incomplete_Record
	}

	if type == .Delete && value_len != 0 {
		return {}, 0, .Invalid_Format
	}

	entry.type = type
	entry.key = bytes.clone(data[9:][:key_len], allocator)
	entry.value = bytes.clone(data[9 + key_len:][:value_len], allocator)
	return entry, need, .None
}
