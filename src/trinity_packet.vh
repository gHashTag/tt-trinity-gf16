// Trinity packet format constants (v0, 2x2 mesh fabric)
// Apache-2.0
//
// 32-bit packet layout:
//   [31:28] op     - 4'h0 NOP, 4'h1 LOAD_A, 4'h2 LOAD_B, 4'h3 COMPUTE, 4'h4 RESULT, 4'h5 READ_RES
//   [27:26] dst_x  - 2 bits (column 0..1)
//   [27]    dst_y  - 1 bit  (row    0..1)  (we treat [27:26] as flat tile id 0..3)
//   [25:24] src_x  - 2 bits (column)
//   [23:20] lane   - which lane (0..3 for a/b operands; 0 for compute/result)
//   [19:16] reserved
//   [15:0]  payload (GF16 word or result)
//
// Tile id (flat) lives in [27:26] (dst) and [25:24] (src).
// This is a single-hop fabric; "x/y" naming kept for forward-compat with full 2x2 XY routing.

`define TRN_PKT_W            32
`define TRN_NUM_TILES        4
`define TRN_TILE_ID_W        2

`define TRN_OP_NOP           4'h0
`define TRN_OP_LOAD_A        4'h1
`define TRN_OP_LOAD_B        4'h2
`define TRN_OP_COMPUTE       4'h3
`define TRN_OP_RESULT        4'h4
`define TRN_OP_READ_RES      4'h5

// Field accessors
`define TRN_PKT_OP(p)        (p[31:28])
`define TRN_PKT_DST(p)       (p[27:26])
`define TRN_PKT_SRC(p)       (p[25:24])
`define TRN_PKT_LANE(p)      (p[23:20])
`define TRN_PKT_PAYLOAD(p)   (p[15:0])

`define TRN_MK_PKT(op,dst,src,lane,pl) {op, dst, src, lane, 4'h0, pl}
