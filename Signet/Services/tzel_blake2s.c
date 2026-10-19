#include "tzel_blake2s.h"
#include <string.h>

// ---- BLAKE2s (RFC 7693) --------------------------------------------------------------------------

static const uint32_t IV[8] = {
    0x6A09E667u, 0xBB67AE85u, 0x3C6EF372u, 0xA54FF53Au, 0x510E527Fu, 0x9B05688Cu, 0x1F83D9ABu, 0x5BE0CD19u,
};

static const uint8_t SIGMA[10][16] = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
    {11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4},
    {7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8},
    {9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13},
    {2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9},
    {12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11},
    {13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10},
    {6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5},
    {10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0},
};

static inline uint32_t rotr32(uint32_t x, unsigned n) { return (x >> n) | (x << (32 - n)); }

static inline uint32_t load32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline void store32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
}

#define G(r, i, a, b, c, d)                                   \
    do {                                                      \
        a = a + b + m[SIGMA[r][2 * i]];                       \
        d = rotr32(d ^ a, 16);                                \
        c = c + d;                                            \
        b = rotr32(b ^ c, 12);                                \
        a = a + b + m[SIGMA[r][2 * i + 1]];                   \
        d = rotr32(d ^ a, 8);                                 \
        c = c + d;                                            \
        b = rotr32(b ^ c, 7);                                 \
    } while (0)

static void compress(uint32_t h[8], const uint8_t block[64], uint64_t counter, int last) {
    uint32_t m[16], v[16];
    for (int i = 0; i < 16; i++) m[i] = load32(block + 4 * i);
    for (int i = 0; i < 8; i++) { v[i] = h[i]; v[i + 8] = IV[i]; }
    v[12] ^= (uint32_t)counter;
    v[13] ^= (uint32_t)(counter >> 32);
    if (last) v[14] = ~v[14];
    for (int r = 0; r < 10; r++) {
        G(r, 0, v[0], v[4], v[8], v[12]);
        G(r, 1, v[1], v[5], v[9], v[13]);
        G(r, 2, v[2], v[6], v[10], v[14]);
        G(r, 3, v[3], v[7], v[11], v[15]);
        G(r, 4, v[0], v[5], v[10], v[15]);
        G(r, 5, v[1], v[6], v[11], v[12]);
        G(r, 6, v[2], v[7], v[8], v[13]);
        G(r, 7, v[3], v[4], v[9], v[14]);
    }
    for (int i = 0; i < 8; i++) h[i] ^= v[i] ^ v[i + 8];
}

void tzel_blake2s(const uint8_t *in, size_t len, const uint8_t *personal, uint8_t out[32]) {
    uint32_t h[8];
    // Parameter block: digest length 32, no key, fanout 1, depth 1; the personalization is the last two words.
    for (int i = 0; i < 8; i++) h[i] = IV[i];
    h[0] ^= 0x01010020u;
    if (personal) { h[6] ^= load32(personal); h[7] ^= load32(personal + 4); }
    uint8_t block[64];
    uint64_t counter = 0;
    size_t offset = 0;
    for (;;) {
        size_t take = len - offset < 64 ? len - offset : 64;
        memset(block, 0, 64);
        if (take) memcpy(block, in + offset, take);
        counter += take;
        offset += take;
        int last = offset >= len;
        compress(h, block, counter, last);
        if (last) break;
    }
    for (int i = 0; i < 8; i++) store32(out + 4 * i, h[i]);
}

// ---- Auth tree ------------------------------------------------------------------------------------
//
// A port of `authLeaf` in TaquitoBridge/src/tzel.js: WOTS+ with w = 4 and 133 chains, the chain
// endpoints compressed by an L-tree. Every hash is unpersonalized BLAKE2s truncated to 251 bits
// over `pub_seed ‖ ADRS ‖ inputs`, where ADRS packs an 8-byte tag and four little-endian u32s.

#define CHAINS 133
#define WOTS_STEPS 3
static const uint8_t TAG_CHAIN[8] = {'x', 'm', 's', 's', '-', 'c', 'h', 0};
static const uint8_t TAG_LTREE[8] = {'x', 'm', 's', 's', '-', 'l', 't', 0};
static const uint8_t TAG_TREE[8] = {'x', 'm', 's', 's', '-', 't', 'r', 0};

static inline void hash_truncated(const uint8_t *in, size_t len, uint8_t out[32]) {
    tzel_blake2s(in, len, NULL, out);
    out[31] &= 0x07;
}

static inline void write_adrs(uint8_t *at, const uint8_t tag[8], uint32_t key_idx, uint32_t a, uint32_t b, uint32_t c) {
    memcpy(at, tag, 8);
    store32(at + 8, key_idx);
    store32(at + 12, a);
    store32(at + 16, b);
    store32(at + 20, c);
    memset(at + 24, 0, 8);
}

/// A domain tag felt: the label's bytes reversed into the low positions.
static void felt_tag(const char *label, uint8_t out[32]) {
    size_t n = strlen(label);
    memset(out, 0, 32);
    for (size_t i = 0; i < n; i++) out[i] = (uint8_t)label[n - 1 - i];
}

void tzel_auth_leaf(const uint8_t ask_j[32], const uint8_t pub_seed[32], uint32_t key_idx, uint8_t out[32]) {
    // key_seed = H(tag("xmss-sk") ‖ ask_j ‖ felt(key_idx))
    uint8_t buf[128];
    felt_tag("xmss-sk", buf);
    memcpy(buf + 32, ask_j, 32);
    memset(buf + 64, 0, 32);
    store32(buf + 64, key_idx);
    uint8_t key_seed[32];
    hash_truncated(buf, 96, key_seed);

    // Chain endpoints: sk_c = H(key_seed ‖ u32(c) ‖ 0…) then three chain steps.
    uint8_t pk[CHAINS][32];
    uint8_t chain_in[64];
    memcpy(chain_in, key_seed, 32);
    memset(chain_in + 32, 0, 32);
    uint8_t scratch[128];
    memcpy(scratch, pub_seed, 32);
    for (uint32_t c = 0; c < CHAINS; c++) {
        store32(chain_in + 32, c);
        uint8_t x[32];
        hash_truncated(chain_in, 64, x);
        for (uint32_t step = 0; step < WOTS_STEPS; step++) {
            write_adrs(scratch + 32, TAG_CHAIN, key_idx, c, step, 0);
            memcpy(scratch + 64, x, 32);
            hash_truncated(scratch, 96, x);
        }
        memcpy(pk[c], x, 32);
    }

    // L-tree: pairs are hashed, an odd one out is carried up unchanged.
    uint8_t next[CHAINS][32];
    uint8_t (*current)[32] = pk, (*other)[32] = next;
    uint32_t count = CHAINS, level = 0;
    while (count > 1) {
        uint32_t node_idx = 0, written = 0;
        for (uint32_t i = 0; i < count; i += 2) {
            if (i + 1 == count) {
                memcpy(other[written], current[i], 32);
            } else {
                write_adrs(scratch + 32, TAG_LTREE, key_idx, level, node_idx, 0);
                memcpy(scratch + 64, current[i], 32);
                memcpy(scratch + 96, current[i + 1], 32);
                hash_truncated(scratch, 128, other[written]);
                node_idx++;
            }
            written++;
        }
        count = written;
        level++;
        uint8_t (*swap)[32] = current; current = other; other = swap;
    }
    memcpy(out, current[0], 32);
}

void tzel_auth_node(const uint8_t pub_seed[32], uint32_t level, uint32_t node_idx, const uint8_t left[32], const uint8_t right[32], uint8_t out[32]) {
    uint8_t scratch[128];
    memcpy(scratch, pub_seed, 32);
    write_adrs(scratch + 32, TAG_TREE, 0, level, node_idx, 0);
    memcpy(scratch + 64, left, 32);
    memcpy(scratch + 96, right, 32);
    hash_truncated(scratch, 128, out);
}
