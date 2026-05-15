// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// trinity_mesh_4x4.v — 16-tile GF16 mesh fabric (4×4, 16 trinity_gf16_tile instances).
// Apache-2.0
//
// Extends trinity_mesh_2x2 pattern to 16 tiles via generate-for (i=0..15).
// Uses trinity_router_4x4 for host injection/ejection.
//
// ICA-002 (tile-id width): trinity_gf16_tile uses a 2-bit TILE_ID parameter and checks
//   `TRN_PKT_DST(in_pkt) == TILE_ID` (2-bit comparison) for `pkt_for_me`.
//   In a 4×4 mesh, tiles 0..15 need 4-bit IDs in the packet header.
//   Resolution: the trinity_router_4x4 decodes the full 4-bit DST and only asserts
//   `t_valid[i]` for the correct tile. Each tile's `in_pkt` is rewritten here to
//   set DST bits [27:26] = tile_id[1:0] so the tile's `pkt_for_me` check passes.
//   TILE_ID parameter carries the full 4-bit address (upper 2 bits conveyed via
//   the rewritten packet, lower 2 bits match the 2-bit parameter).
//   This is a deliberate ICA; no functional change to trinity_gf16_tile.v (freeze rule).
//
// Interface vectors (match trinity_mesh_2x2 naming, scaled to 16):
//   tile_data_in[i], tile_data_out[i], tile_valid[i]
//
// R-SI-1: NO `*` operator in this file.
// phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E · DOI 10.5281/zenodo.19227877

`include "trinity_packet.vh"

module trinity_mesh_4x4 (
    input  wire                       clk,
    input  wire                       rst_n,

    // Host injection (issue packets to tiles)
    input  wire [`TRN_PKT_W-1:0]      host_in_pkt,
    input  wire                       host_in_valid,
    output wire                       host_in_ready,

    // Host ejection (RESULT / RECEIPT packets from tiles)
    output wire [`TRN_PKT_W-1:0]      host_out_pkt,
    output wire                       host_out_valid,
    input  wire                       host_out_ready,

    // Debug: tile 0 result visibility
    output wire [15:0]                dbg_tile0_result
);

    // ---- Internal router buses ----
    wire [16*`TRN_PKT_W-1:0] t_pkt_flat;      // router -> tiles (forward)
    wire [15:0]               t_valid;
    wire [15:0]               t_ready;

    wire [16*`TRN_PKT_W-1:0] t_ret_pkt_flat;  // tiles -> router (return)
    wire [15:0]               t_ret_valid;
    wire [15:0]               t_ret_ready;

    // ---- Router instantiation ----
    trinity_router_4x4 u_router (
        .clk            (clk),
        .rst_n          (rst_n),
        .host_in_pkt    (host_in_pkt),
        .host_in_valid  (host_in_valid),
        .host_in_ready  (host_in_ready),
        .host_out_pkt   (host_out_pkt),
        .host_out_valid (host_out_valid),
        .host_out_ready (host_out_ready),
        .t_pkt_flat     (t_pkt_flat),
        .t_valid        (t_valid),
        .t_ready        (t_ready),
        .t_ret_pkt_flat (t_ret_pkt_flat),
        .t_ret_valid    (t_ret_valid),
        .t_ret_ready    (t_ret_ready)
    );

    // ---- Per-tile wires ----
    wire [`TRN_PKT_W-1:0] t_in_pkt_raw [0:15];   // sliced from flat bus (4-bit DST)
    wire [`TRN_PKT_W-1:0] t_in_pkt     [0:15];   // rewritten: DST[27:26] = tile_id[1:0]
    wire [`TRN_PKT_W-1:0] t_out_pkt    [0:15];
    wire [15:0]            tile_dbg     [0:15];

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_tile
            // Slice raw packet from flat bus
            assign t_in_pkt_raw[i] = t_pkt_flat[(i+1)*`TRN_PKT_W-1 -: `TRN_PKT_W];

            // ICA-M-002 FIX (W15-TT-E, 2026-05-15):
            // The 4x4 extended packet format from the testbench / host is:
            //   [31:28]=op, [27:24]=dst4, [23:20]=src4, [19:16]=lane4, [15:0]=pl
            // but trinity_gf16_tile reads via trinity_packet.vh macros:
            //   TRN_PKT_DST  = p[27:26]  (2-bit)
            //   TRN_PKT_SRC  = p[25:24]  (2-bit)
            //   TRN_PKT_LANE = p[23:20]  (4-bit)
            //   TRN_PKT_PAYLOAD = p[15:0]
            // Previous rewrite only patched DST but left src4 at [23:20] where
            // TRN_PKT_LANE looks — causing ALL LOAD_A/B packets to hit lane 0
            // regardless of the intended lane (ICA-M-002 root cause).
            //
            // Correct rewrite maps the 4x4 extended fields to the 2x2 macro layout:
            //   [31:28] = op            (unchanged)
            //   [27:26] = i[1:0]        (tile_id — for pkt_for_me)
            //   [25:24] = raw[21:20]    (src4[1:0] — where TRN_PKT_SRC reads)
            //   [23:20] = raw[19:16]    (lane4[3:0] — where TRN_PKT_LANE reads)
            //   [19:16] = 4'h0          (reserved field in TRN_MK_PKT layout)
            //   [15:0]  = raw[15:0]     (payload — unchanged)
            // No trinity_packet.vh ABI change; only the mesh adaptor is updated.
            assign t_in_pkt[i] = {
                t_in_pkt_raw[i][31:28],  // op[3:0]         — unchanged
                i[1:0],                   // dst[1:0]        — forced to tile_id[1:0]
                t_in_pkt_raw[i][21:20],  // src4[1:0]       — TRN_PKT_SRC = p[25:24]
                t_in_pkt_raw[i][19:16],  // lane4[3:0]      — TRN_PKT_LANE = p[23:20]
                4'h0,                     // reserved        — TRN_MK_PKT [19:16]
                t_in_pkt_raw[i][15:0]    // payload[15:0]   — unchanged
            };

            // Return: pack tile output into flat bus
            assign t_ret_pkt_flat[(i+1)*`TRN_PKT_W-1 -: `TRN_PKT_W] = t_out_pkt[i];

            // Tile instantiation — TILE_ID is 2-bit (lower 2 bits of 4-bit id)
            // R-SI-1: DOT_WIDTH=4 (baseline dot4, no gf16_dot4_wallace) per freeze rule.
            trinity_gf16_tile #(
                .TILE_ID  (i[1:0]),
                .DOT_WIDTH(4)
            ) u_tile (
                .clk        (clk),
                .rst_n      (rst_n),
                .in_pkt     (t_in_pkt[i]),
                .in_valid   (t_valid[i]),
                .in_ready   (t_ready[i]),
                .out_pkt    (t_out_pkt[i]),
                .out_valid  (t_ret_valid[i]),
                .out_ready  (t_ret_ready[i]),
                .dbg_result (tile_dbg[i])
            );
        end
    endgenerate

    assign dbg_tile0_result = tile_dbg[0];

endmodule
// phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E · DOI 10.5281/zenodo.19227877
