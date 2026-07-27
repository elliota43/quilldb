package kv

import "core:bytes"
import "core:os"
import "core:testing"

@(test)
test_serialize_edit_layout :: proc(t: ^testing.T) {
	key := transmute([]u8)string("hi")
	val := transmute([]u8)string("yo")
	entry := make_kv_entry(.Edit, key, val)

	data, err := serialize(&entry)
	defer delete(data)

	testing.expect_value(t, err, KV_Error.None)
	testing.expect_value(t, len(data), 13)
	testing.expect_value(t, data[0], u8(KV_Entry_Type.Edit))
	testing.expect(t, bytes.equal(data[1:5], []u8{2, 0, 0, 0}))
	testing.expect(t, bytes.equal(data[5:9], []u8{2, 0, 0, 0}))
	testing.expect(t, bytes.equal(data[9:11], key))
	testing.expect(t, bytes.equal(data[11:13], val))
}

@(test)
test_serialize_delete_layout :: proc(t: ^testing.T) {
	key := transmute([]u8)string("k")
	entry := make_kv_entry(.Delete, key, transmute([]u8)string("ignored"))

	data, err := serialize(&entry)
	defer delete(data)
	testing.expect_value(t, err, KV_Error.None)
	testing.expect_value(t, len(data), 10)
	testing.expect_value(t, data[0], u8(KV_Entry_Type.Delete))
	testing.expect(t, bytes.equal(data[1:5], []u8{1, 0, 0, 0}))
	testing.expect(t, bytes.equal(data[5:9], []u8{0, 0, 0, 0}))
	testing.expect(t, bytes.equal(data[9:10], key))
}


@(test)
test_serialize_empty_value :: proc(t: ^testing.T) {
	entry := make_kv_entry(.Edit, transmute([]u8)string("k"), []u8{})
	data, err := serialize(&entry)
	defer delete(data)
	testing.expect_value(t, err, KV_Error.None)
	testing.expect_value(t, len(data), 10)
	testing.expect(t, bytes.equal(data[5:9], []u8{0, 0, 0, 0}))
}
@(test)
test_serialize_binary_payload :: proc(t: ^testing.T) {
	key := []u8{0x00, 0xff, 0x01}
	val := []u8{0xde, 0xad}
	entry := make_kv_entry(.Edit, key, val)
	data, err := serialize(&entry)
	defer delete(data)
	testing.expect_value(t, err, KV_Error.None)
	testing.expect(t, bytes.equal(data[9:12], key))
	testing.expect(t, bytes.equal(data[12:14], val))
}

@(test)
test_serialize_borrows_input :: proc(t: ^testing.T) {
	key := []u8{'k'}
	val := []u8{'v', '1'}
	entry := make_kv_entry(.Edit, key, val)

	data, err := serialize(&entry)
	defer delete(data)
	testing.expect_value(t, err, KV_Error.None)

	key[0] = 'x'
	val[1] = '2'


	// Mutating calling buffer must not change already-serialized output
	testing.expect(t, bytes.equal(data[9:10], []u8{'k'}))
	testing.expect(t, bytes.equal(data[10:12], []u8{'v', '1'}))
}

@(test)
test_roundtrip_edit :: proc(t: ^testing.T) {
	key := transmute([]u8)string("alpha")
	val := transmute([]u8)string("one")
	entry := make_kv_entry(.Edit, key, val)

	data, err := serialize(&entry)
	defer delete(data)
	testing.expect_value(t, err, KV_Error.None)

	got, derr := deserialize(data)
	defer destroy_kv_entry(&got)
	testing.expect_value(t, derr, KV_Error.None)
	testing.expect_value(t, got.type, KV_Entry_Type.Edit)
	testing.expect(t, bytes.equal(got.key, key))
	testing.expect(t, bytes.equal(got.value, val))
}

@(test)
test_roundtrip_delete :: proc(t: ^testing.T) {
	key := transmute([]u8)string("gone")
	entry := make_kv_entry(.Delete, key)
	data, err := serialize(&entry)
	defer delete(data)
	testing.expect_value(t, err, KV_Error.None)
	got, derr := deserialize(data)
	defer destroy_kv_entry(&got)
	testing.expect_value(t, derr, KV_Error.None)
	testing.expect_value(t, got.type, KV_Entry_Type.Delete)
	testing.expect(t, bytes.equal(got.key, key))
	testing.expect_value(t, len(got.value), 0)
}

@(test)
test_deserialize_owns_memory :: proc(t: ^testing.T) {
	entry := make_kv_entry(.Edit, transmute([]u8)string("k"), transmute([]u8)string("v1"))
	data, err := serialize(&entry)
	testing.expect_value(t, err, KV_Error.None)
	got, derr := deserialize(data)
	defer destroy_kv_entry(&got)
	testing.expect_value(t, derr, KV_Error.None)
	delete(data) // wire buffer gone; got must still be valid
	testing.expect(t, bytes.equal(got.key, transmute([]u8)string("k")))
	testing.expect(t, bytes.equal(got.value, transmute([]u8)string("v1")))
}

@(test)
test_deserialize_too_short :: proc(t: ^testing.T) {
	_, err := deserialize([]u8{1, 2, 3})
	testing.expect_value(t, err, KV_Error.Incomplete_Record)
}

@(test)
test_deserialize_truncated_payload :: proc(t: ^testing.T) {
	data := []u8{u8(KV_Entry_Type.Edit), 5, 0, 0, 0, 0, 0, 0, 0, 'a', 'b'}
	_, err := deserialize(data)
	testing.expect_value(t, err, KV_Error.Incomplete_Record)
}

@(test)
test_deserialize_bad_type :: proc(t: ^testing.T) {
	data := []u8{0xff, 0, 0, 0, 0, 0, 0, 0, 0}
	_, err := deserialize(data)
	testing.expect_value(t, err, KV_Error.Invalid_Format)
}

@(test)
test_deserialize_delete_with_value_rejected :: proc(t: ^testing.T) {
	data := []u8{u8(KV_Entry_Type.Delete), 1, 0, 0, 0, 1, 0, 0, 0, 'k', 'v'}
	_, err := deserialize(data)
	testing.expect_value(t, err, KV_Error.Invalid_Format)
}

// =====================================================
//              INTEGRATION TESTS
// =====================================================

@(test)
test_wal_reboot_roundtrip :: proc(t: ^testing.T) {
	path := "test_kv_reboot.wal"
	os.remove(path)
	defer os.remove(path)

	store, err := open_kv_store(path)
	testing.expect_value(t, err, KV_Error.None)
	testing.expect(t, store != nil)


	_, perr := put(store, transmute([]u8)string("a"), transmute([]u8)string("1"))
	testing.expect_value(t, perr, KV_Error.None)
	_, perr = put(store, transmute([]u8)string("b"), transmute([]u8)string("2"))
	testing.expect_value(t, perr, KV_Error.None)
	_, derr := del(store, transmute([]u8)string("a"))
	testing.expect_value(t, derr, KV_Error.None)

	destroy_kv_store(store)
	free(store)

	store2, err2 := open_kv_store(path)
	testing.expect_value(t, err2, KV_Error.None)
	defer {
		destroy_kv_store(store2)
		free(store2)
	}

	_, gerr := get(store2, transmute([]u8)string("a"))
	testing.expect_value(t, gerr, KV_Error.Not_Found)
	got, gerr2 := get(store2, transmute([]u8)string("b"))
	testing.expect_value(t, gerr2, KV_Error.None)
	testing.expect(t, bytes.equal(got, transmute([]u8)string("2")))
}

@(test)
test_wal_empty_open :: proc(t: ^testing.T) {
	path := "test_kv_empty.wal"
	os.remove(path)
	defer os.remove(path)

	store, err := open_kv_store(path)
	testing.expect_value(t, err, KV_Error.None)
	testing.expect(t, store != nil)
	defer {
		destroy_kv_store(store)
		free(store)
	}

	_, gerr := get(store, transmute([]u8)string("missing"))
	testing.expect_value(t, gerr, KV_Error.Not_Found)

	_, perr := put(store, transmute([]u8)string("k"), transmute([]u8)string("v"))
	testing.expect_value(t, perr, KV_Error.None)

	got, gerr2 := get(store, transmute([]u8)string("k"))
	testing.expect_value(t, gerr2, KV_Error.None)
	testing.expect(t, bytes.equal(got, transmute([]u8)string("v")))
}

@(test)
test_wal_overwrite_survives_reboot :: proc(t: ^testing.T) {
	path := "test_kv_overwrite.wal"
	os.remove(path)
	defer os.remove(path)

	store, err := open_kv_store(path)
	testing.expect_value(t, err, KV_Error.None)

	_, _ = put(store, transmute([]u8)string("k"), transmute([]u8)string("v1"))
	_, perr := put(store, transmute([]u8)string("k"), transmute([]u8)string("v2"))
	testing.expect_value(t, perr, KV_Error.None)

	destroy_kv_store(store)
	free(store)

	store2, err2 := open_kv_store(path)
	testing.expect_value(t, err2, KV_Error.None)
	defer {
		destroy_kv_store(store2)
		free(store2)
	}

	got, gerr := get(store2, transmute([]u8)string("k"))
	testing.expect_value(t, gerr, KV_Error.None)
	testing.expect(t, bytes.equal(got, transmute([]u8)string("v2")))
}

@(test)
test_wal_torn_tail_truncated_on_open :: proc(t: ^testing.T) {
	path := "test_kv_torn.wal"
	os.remove(path)
	defer os.remove(path)

	store, err := open_kv_store(path)
	testing.expect_value(t, err, KV_Error.None)

	_, perr := put(store, transmute([]u8)string("k"), transmute([]u8)string("ok"))
	testing.expect_value(t, perr, KV_Error.None)

	destroy_kv_store(store)
	free(store)

	before, rok := os.read_entire_file(path, context.allocator)
	testing.expect(t, rok == nil)
	defer delete(before)
	good_len := len(before)

	f, oerr := os.open(path, {.Write, .Append})
	testing.expect(t, oerr == nil)
	_, werr := os.write(f, []u8{u8(KV_Entry_Type.Edit), 5, 0, 0, 0}) // header claims key_len=5, no payload
	testing.expect(t, werr == nil)
	os.close(f)

	store2, err2 := open_kv_store(path)
	testing.expect_value(t, err2, KV_Error.None)
	defer {
		destroy_kv_store(store2)
		free(store2)
	}

	got, gerr := get(store2, transmute([]u8)string("k"))
	testing.expect_value(t, gerr, KV_Error.None)
	testing.expect(t, bytes.equal(got, transmute([]u8)string("ok")))

	after, rok2 := os.read_entire_file(path, context.allocator)
	testing.expect(t, rok2 == nil)
	defer delete(after)
	testing.expect_value(t, len(after), good_len)
	testing.expect(t, bytes.equal(after, before))
}
