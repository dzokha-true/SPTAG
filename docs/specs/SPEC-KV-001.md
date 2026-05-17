# SPEC-KV-001: Aerospike KeyValueIO smoke behavior

## Statement

When built with `-DAEROSPIKE=ON` and run with `SPTAG_RUN_AEROSPIKE_TEST=1` against a reachable cluster, `AerospikeKeyValueIO` shall:

1. Connect (`Available() == true`).
2. Complete preflight Put → Get → Delete on an isolated key.
3. Put `totalNum` keys, Merge append on each key, Get key `0` with non-empty value.
4. Complete `MultiGet` over batched head IDs with `ErrorCode::Success`.
5. Delete key `0`; subsequent Get shall not succeed.

Configuration uses `SPTAG_AEROSPIKE_*` environment variables when set; otherwise compile-time defaults from CMake.

## Verified by

`Test/src/KVTest.cpp` — `BOOST_AUTO_TEST_CASE(AerospikeTest)` in suite `KVTest`.

## Contract

[../contracts/aerospike-kv-backend.md](../contracts/aerospike-kv-backend.md)
