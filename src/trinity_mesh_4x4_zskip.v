// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// trinity_mesh_4x4_zskip.v — Wave-16a zero-skip v2 mesh fabric (NorthPole-style).
// Apache-2.0
//
// NEW MODULE — shadow-mode only. Does NOT modify trinity_mesh_4x4.v (freeze rule).
// Branch: feat/wave-16a-zero-skip-experimental
// Author: Vasilev Dmitrii <admin@t27.ai> ORCID 0009-0008-4294-6159
//
// DESCRIPTION
// -----------
// Derives from trinity_mesh_4x4 — wraps each trinity_gf16_tile instance with a
// tri_zero_skip_gate that monitors LOAD_B packet payloads and generates per-tile
// pe_clk_en signals for synthesis clock-enable gating.
//
// ZERO-SKIP V2 vs V1
// ------------------
// v1 (W8, gf16_dot4_sparse): operand-level mux — zero operand presented to mul,
//   but the mul still toggles. Saves ~60% of operand switching.
// v2 (this module, Wave-16a): CLOCK-ENABLE gating — pe_clk_en=0 when last loaded
//   b-weight was zero. Synthesis tool instantiates ICG cell (latch+AND) on the
//   accumulator registers, eliminating adder dynamic power for zero-weight cycles.
//   Estimated +30–50% TOPS/W at 33–50% weight sparsity (GF16 ternary typical).
//
// FUNCTIONAL EQUIVALENCE
// ----------------------
// ALL packets pass through to the tile unchanged — no packet suppression.
// Functional behavior is bit-identical to trinity_mesh_4x4 (required for testbench).
// pe_clk_en is a SYNTHESIS ANNOTATION signal: a registered per-tile enable that
// synthesis uses to insert ICG cells. In behavioural simulation it does not gate
// any logic; the ICG effect is physical-only.
//
// REGISTERED pe_clk_en
// ---------------------
// When a LOAD_B packet arrives for tile i and payload[14:0]==0 (GF16 zero),
// pe_clk_en[i] is cleared. When a non-zero LOAD_B arrives, pe_clk_en[i] is set.
// This register is the ICG enable for the tile's accumulator registers in synthesis.
// COMPUTE packets do not change pe_clk_en.
//
// SG13G2 mapping: synthesis synthesises:
//   sg13g2_icg u_icg(.CLK(clk), .EN(pe_clk_en_i), .ENCLK(pe_gated_clk));
//   always_ff @(posedge pe_gated_clk) begin acc_reg <= acc_in; end
//
// R-SI-1: NO `*` operator in this file.
// ANCHOR: φ²+φ⁻²=3 · Wave-16a · DOI 10.5281/zenodo.19227877 · R5

`include "trinity_packet.vh"

// ---------------------------------------------------------------------------
// trinity_mesh_4x4_zskip_fabric — 16-tile mesh with zero-skip v2 clock-enable
// ---------------------------------------------------------------------------
module trinity_mesh_4x4_zskip_fabric (
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
    output wire [15:0]                dbg_tile0_result,

    // Zero-skip v2 clock-enable outputs (16 tiles) — synthesis ICG annotation
    // pe_clk_en[i]=1: tile i accumulator may clock (weight non-zero)
    // pe_clk_en[i]=0: tile i accumulator holds (weight is zero — ICG gated)
    output wire [15:0]                pe_clk_en_out
);

    // ---- Internal router buses ----
    wire [16*`TRN_PKT_W-1:0] t_pkt_flat;
    wire [15:0]               t_valid;
    wire [15:0]               t_ready;

    wire [16*`TRN_PKT_W-1:0] t_ret_pkt_flat;
    wire [15:0]               t_ret_valid;
    wire [15:0]               t_ret_ready;

    // ---- Router ----
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
    wire [`TRN_PKT_W-1:0] t_in_pkt_raw [0:15];
    wire [`TRN_PKT_W-1:0] t_in_pkt     [0:15];
    wire [`TRN_PKT_W-1:0] t_out_pkt    [0:15];
    wire [15:0]            tile_dbg     [0:15];

    // ---- Zero-skip v2: registered pe_clk_en per tile ----
    // Updated whenever a LOAD_B packet is accepted by that tile.
    // pe_clk_en[i] = last LOAD_B payload was non-zero.
    reg  [15:0] pe_clk_en_r;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_tile

            // Slice raw packet from flat bus
            assign t_in_pkt_raw[i] = t_pkt_flat[(i+1)*`TRN_PKT_W-1 -: `TRN_PKT_W];

            // ICA-M-002 fix: rewrite packet fields to tile's 2x2 ABI
            assign t_in_pkt[i] = {
                t_in_pkt_raw[i][31:28],  // op[3:0]
                i[1:0],                   // dst[1:0] — forced to tile_id
                t_in_pkt_raw[i][21:20],  // src4[1:0]
                t_in_pkt_raw[i][19:16],  // lane4[3:0]
                4'h0,                     // reserved
                t_in_pkt_raw[i][15:0]    // payload[15:0]
            };

            // Return packet packing — ALL packets pass through (no suppression)
            assign t_ret_pkt_flat[(i+1)*`TRN_PKT_W-1 -: `TRN_PKT_W] = t_out_pkt[i];

            // Tile instantiation — UNMODIFIED (freeze rule)
            // All valid signals pass through unchanged → bit-identical to baseline
            trinity_gf16_tile #(
                .TILE_ID  (i[1:0]),
                .DOT_WIDTH(4)
            ) u_tile (
                .clk        (clk),
                .rst_n      (rst_n),
                .in_pkt     (t_in_pkt[i]),
                .in_valid   (t_valid[i]),   // ← unmodified, bit-identical path
                .in_ready   (t_ready[i]),
                .out_pkt    (t_out_pkt[i]),
                .out_valid  (t_ret_valid[i]),
                .out_ready  (t_ret_ready[i]),
                .dbg_result (tile_dbg[i])
            );

            // ---- tri_zero_skip_gate: detect zero weight in LOAD_B payload ----
            // Monitors the 4-bit weight nibble from incoming LOAD_B packets.
            // pe_clk_en is a COMBINATIONAL indicator for the current packet.
            // Registered below as pe_clk_en_r[i] (synthesis ICG annotation).
            wire [15:0] raw_payload = t_in_pkt_raw[i][15:0];
            wire [3:0]  weight_nibble = {
                |raw_payload[14:12],
                |raw_payload[11:8],
                |raw_payload[7:4],
                |raw_payload[3:0]
            };
            wire pe_clk_en_comb_i;

            tri_zero_skip_gate u_zsg (
                .weight   (weight_nibble),
                .clk      (clk),
                .pe_clk_en(pe_clk_en_comb_i)
            );

            // Detect incoming LOAD_B for this tile
            wire is_load_b_i = (t_in_pkt_raw[i][31:28] == `TRN_OP_LOAD_B);
            wire pkt_accepted_i = t_valid[i] && t_ready[i];

            // Registered pe_clk_en: update on LOAD_B acceptance
            // ICG semantic: pe_clk_en_r[i]=0 means last weight was 0 → hold accumulator
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    pe_clk_en_r[i] <= 1'b1;  // default: enabled (non-zero weight assumed)
                else if (pkt_accepted_i && is_load_b_i)
                    pe_clk_en_r[i] <= pe_clk_en_comb_i;
                // else: hold pe_clk_en_r[i]
            end
        end
    endgenerate

    assign dbg_tile0_result = tile_dbg[0];
    assign pe_clk_en_out    = pe_clk_en_r;

endmodule
// phi^2 + phi^-2 = 3 · Wave-16a · NorthPole zero-skip v2 · DOI 10.5281/zenodo.19227877
`default_nettype wire
