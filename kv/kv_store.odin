package kv

import "core:bytes"
import "core:strings"

KVStore :: struct {
	data: map[string][]u8,
}

KV_Error :: enum {
	None,
	Not_Found,
}

make_kv_store :: proc() -> KVStore {
	return KVStore{data = make(map[string][]u8)}
}

destroy_kv_store :: proc(this: ^KVStore) {
	for k, v in this.data {
		delete(k)
		delete(v)
	}

	delete(this.data)
	this.data = nil
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

	if exists {
		if bytes.equal(prev, value) {
			return false, .None
		}

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

	old_key, old_val := delete_key(&this.data, key_view)
	delete(old_key)
	delete(old_val)
	return true, .None
}
