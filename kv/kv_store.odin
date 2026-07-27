package kv

import "../wal"
import "core:bytes"
import "core:strings"

KVStore :: struct {
	data: map[string][]u8,
	wal:  ^wal.Log,
}

KV_Error :: enum {
	None,
	Not_Found,
	Invalid_Format,
	IO_Error,
	Incomplete_Record,
}

// make_kv_store is for in-memory storage only.  It just returns an empty
// KVStore object.
// @deprecate
make_kv_store :: proc() -> KVStore {
	return KVStore{data = make(map[string][]u8)}
}

open_kv_store :: proc(pathname: string) -> (kv: ^KVStore, err: KV_Error) {
	w, werr := wal.open(pathname)
	if werr != nil {
		return nil, .IO_Error
	}

	kv = new(KVStore)
	kv.wal = w
	kv.data = make(map[string][]u8)

	mapped, merr := wal.map_readonly(w)
	if merr != nil {
		destroy_kv_store(kv)
		free(kv)
		return nil, .IO_Error
	}

	offset := 0
	truncate_to := -1 // -1 = no truncate
	data := mapped.data

	for offset < len(data) {
		entry, size, derr := try_decode_entry(data[offset:])
		if derr != .None {
			truncate_to = offset
			break
		}

		apply_replay(kv, &entry) // in-memory put/del only
		destroy_kv_entry(&entry)
		offset += size
	}

	wal.unmap(&mapped)

	if truncate_to >= 0 {
		if terr := wal.truncate(w, i64(truncate_to)); terr != nil {
			destroy_kv_store(kv)
			free(kv)
			return nil, .IO_Error
		}
	}

	if serr := wal.seek_end(w); serr != nil {
		destroy_kv_store(kv)
		free(kv)
		return nil, .IO_Error
	}

	return kv, .None
}


destroy_kv_store :: proc(this: ^KVStore) {
	for k, v in this.data {
		delete(k)
		delete(v)
	}

	if this.wal != nil {
		wal.close(this.wal)
		this.wal = nil
	}

	delete(this.data)
	this.data = nil
}

apply_replay :: proc(this: ^KVStore, entry: ^KV_Entry) {
	switch entry.type {
	case .Edit:
		key_view := string(entry.key)
		if prev, ok := this.data[key_view]; ok {
			delete(prev)
			this.data[key_view] = bytes.clone(entry.value)
		} else {
			this.data[strings.clone_from_bytes(entry.key)] = bytes.clone(entry.value)
		}

	case .Delete:
		key_view := string(entry.key)
		if key_view in this.data {
			old_key, old_val := delete_key(&this.data, key_view)
			delete(old_key)
			delete(old_val)
		}
	}
}

// get returns a borrowed slice into the store.
// valid until the key is overwritten, deleted, or the store is destroyed.
// do not delete/mutate the returned slice
get :: proc(this: ^KVStore, key: []u8) -> ([]u8, KV_Error) {
	val, ok := this.data[string(key)]
	if !ok {
		return nil, .Not_Found
	}

	return val, .None
}

// get_clone is the safe version of get if you need to own the data
get_clone :: proc(this: ^KVStore, key: []u8) -> (value: []u8, error: KV_Error) {
	val, err := get(this, key)
	if err != .None {
		return nil, err
	}

	return bytes.clone(val), .None
}

put :: proc(this: ^KVStore, key: []u8, value: []u8) -> (updated: bool, error: KV_Error) {
	key_view := string(key)
	prev, exists := this.data[key_view]

	if exists && bytes.equal(prev, value) {
		return false, .None
	}

	if this.wal != nil {
		entry := make_kv_entry(.Edit, key, value)
		payload, serialize_err := serialize(&entry)
		if serialize_err != .None {
			return false, serialize_err
		}

		defer delete(payload)

		if werr := wal.write(this.wal, payload); werr != nil {
			return false, .IO_Error
		}
	}

	if exists {
		delete(prev)
		this.data[key_view] = bytes.clone(value)
		return true, .None
	}

	owned_key := strings.clone_from_bytes(key)
	owned_val := bytes.clone(value)
	this.data[owned_key] = owned_val
	return true, .None
}

del :: proc(this: ^KVStore, key: []u8) -> (updated: bool, error: KV_Error) {
	key_view := string(key)
	if key_view not_in this.data {
		return false, .Not_Found
	}

	if this.wal != nil {
		entry := make_kv_entry(.Delete, key)
		payload, serialize_err := serialize(&entry)
		if serialize_err != .None {
			return false, serialize_err
		}

		defer delete(payload)

		if werr := wal.write(this.wal, payload); werr != nil {
			return false, .IO_Error
		}
	}

	old_key, old_val := delete_key(&this.data, key_view)
	delete(old_key)
	delete(old_val)
	return true, .None
}
