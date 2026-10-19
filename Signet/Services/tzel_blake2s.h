// BLAKE2s-256 (RFC 7693) and the TzEL auth-tree leaf, in C so the 44 million hashes of an
// address's signing tree take seconds in every build configuration (the file is compiled with
// -O3; see project.yml). Swift's `Blake2s` and `XMSSAuthTree` wrap these; the protocol stays
// in TaquitoBridge/src/tzel.js and the tests check the two agree.
#ifndef TZEL_BLAKE2S_H
#define TZEL_BLAKE2S_H

#include <stddef.h>
#include <stdint.h>

/// BLAKE2s-256 of `in`, unkeyed; `personal` is 8 bytes or NULL. `out` is 32 bytes.
void tzel_blake2s(const uint8_t *in, size_t len, const uint8_t *personal, uint8_t out[32]);

/// The WOTS+ leaf of key `key_idx` of the auth tree with signing seed `ask_j` and public seed
/// `pub_seed` (32 bytes each; felts, little-endian). `out` is the 32-byte leaf.
void tzel_auth_leaf(const uint8_t ask_j[32], const uint8_t pub_seed[32], uint32_t key_idx, uint8_t out[32]);

/// An inner auth-tree node: `H(pub_seed ‖ ADRS(xmss-tr, 0, level, node_idx, 0) ‖ left ‖ right)`, truncated.
void tzel_auth_node(const uint8_t pub_seed[32], uint32_t level, uint32_t node_idx, const uint8_t left[32], const uint8_t right[32], uint8_t out[32]);

#endif
