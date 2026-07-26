package kv

import "core:bytes"
import "core:testing"

@(test)
test_put_get_roundtrip :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)

	key := transmute([]u8)string("alpha")
	val := transmute([]u8)string("one")

	updated, err := put(&store, key, val)
	testing.expect_value(t, err, KV_Error.None)
	testing.expect(t, updated)

	got, gerr := get(&store, key)
	testing.expect_value(t, gerr, KV_Error.None)
	testing.expect(t, bytes.equal(got, val))
}

@(test)
test_get_missing :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)

	_, err := get(&store, transmute([]u8)string("nope"))
	testing.expect_value(t, err, KV_Error.Not_Found)
}

@(test)
test_put_overwrite :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)

	key := transmute([]u8)string("k")
	_, _ = put(&store, key, transmute([]u8)string("v1"))

	updated, err := put(&store, key, transmute([]u8)string("v2"))
	testing.expect_value(t, err, KV_Error.None)
	testing.expect(t, updated)

	got, gerr := get(&store, key)
	testing.expect_value(t, gerr, KV_Error.None)
	testing.expect(t, bytes.equal(got, transmute([]u8)string("v2")))
}


@(test)
test_put_same_value_no_update :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)
	key := transmute([]u8)string("k")
	val := transmute([]u8)string("same")
	_, _ = put(&store, key, val)
	updated, err := put(&store, key, val)
	testing.expect_value(t, err, KV_Error.None)
	testing.expect(t, !updated)
}
@(test)
test_delete_existing :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)
	key := transmute([]u8)string("k")
	_, _ = put(&store, key, transmute([]u8)string("v"))
	updated, err := del(&store, key)
	testing.expect_value(t, err, KV_Error.None)
	testing.expect(t, updated)
	_, gerr := get(&store, key)
	testing.expect_value(t, gerr, KV_Error.Not_Found)
}
@(test)
test_delete_missing :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)
	updated, err := del(&store, transmute([]u8)string("missing"))
	testing.expect_value(t, err, KV_Error.Not_Found)
	testing.expect(t, !updated)
}
@(test)
test_binary_keys :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)
	key := []u8{0x00, 0xff, 0x01}
	val := []u8{1, 2, 3}
	_, err := put(&store, key, val)
	testing.expect_value(t, err, KV_Error.None)
	got, gerr := get(&store, key)
	testing.expect_value(t, gerr, KV_Error.None)
	testing.expect(t, bytes.equal(got, val))
}
@(test)
test_keys_are_distinct :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)
	_, _ = put(&store, transmute([]u8)string("a"), transmute([]u8)string("1"))
	_, _ = put(&store, transmute([]u8)string("ab"), transmute([]u8)string("2"))
	a, _ := get(&store, transmute([]u8)string("a"))
	ab, _ := get(&store, transmute([]u8)string("ab"))
	testing.expect(t, bytes.equal(a, transmute([]u8)string("1")))
	testing.expect(t, bytes.equal(ab, transmute([]u8)string("2")))
}
@(test)
test_put_owns_value_memory :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)
	key_buf := []u8{'k'}
	val_buf := []u8{'v', '1'}
	_, err := put(&store, key_buf, val_buf)
	testing.expect_value(t, err, KV_Error.None)
	// Mutate caller's buffers after put — store must be unaffected.
	val_buf[1] = '2'
	key_buf[0] = 'x'
	got, gerr := get(&store, transmute([]u8)string("k"))
	testing.expect_value(t, gerr, KV_Error.None)
	testing.expect(
		t,
		bytes.equal(got, transmute([]u8)string("v1")),
		"store must own its own copy of the value",
	)
}
@(test)
test_overwrite_then_get :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)
	key := transmute([]u8)string("k")
	_, _ = put(&store, key, transmute([]u8)string("first"))
	_, _ = put(&store, key, transmute([]u8)string("second"))
	_, _ = put(&store, key, transmute([]u8)string("third"))
	got, err := get(&store, key)
	testing.expect_value(t, err, KV_Error.None)
	testing.expect(t, bytes.equal(got, transmute([]u8)string("third")))
}
@(test)
test_delete_then_reinsert :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)
	key := transmute([]u8)string("k")
	_, _ = put(&store, key, transmute([]u8)string("v1"))
	_, _ = del(&store, key)
	updated, err := put(&store, key, transmute([]u8)string("v2"))
	testing.expect_value(t, err, KV_Error.None)
	testing.expect(t, updated)
	got, gerr := get(&store, key)
	testing.expect_value(t, gerr, KV_Error.None)
	testing.expect(t, bytes.equal(got, transmute([]u8)string("v2")))
}
@(test)
test_empty_value_allowed :: proc(t: ^testing.T) {
	store := make_kv_store()
	defer destroy_kv_store(&store)
	key := transmute([]u8)string("k")
	empty := []u8{}
	_, err := put(&store, key, empty)
	testing.expect_value(t, err, KV_Error.None)
	got, gerr := get(&store, key)
	testing.expect_value(t, gerr, KV_Error.None)
	testing.expect(t, len(got) == 0)
}
