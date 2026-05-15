// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// trinity_mesh_4x4_zskip.v — Wave-16a zero-skip v2 mesh variant (NorthPole-style).
// Apache-2.0
//
// NEW MODULE — shadow-mode only. Does NOT modify trinity_mesh_4x4.v (freeze rule).
// Branch: feat/wave-16a-zero-skip-experimental
// Author: Vasilev Dmitrii <admin@t27.ai> ORCID 0009-0008-4294-6159
//
// DESCRIPTION
// -----------
// Derives from trinity_mesh_4x4 — wraps each trinity_gf16_tile instance with a
// tri_zero_skip_gate that monitors the 4-bit GF16 weight nibble extracted from
// LOAD_B packets. When the weight payload is zero (16'h0000 — GF16 canonical zero),
// pe_clk_en is deasserted, holding the tile's input registers stable (behavioural
// ICG pattern: `if (pe_clk_en)` guard in always_ff).
//
// ZERO-SKIP V2 vs V1
// ------------------
// v1 (W8, gf16_dot4_sparse): operand-level mux — zero operand presented to mul,
//   but the mul still toggles. Saves ~60% of operand switching.
// v2 (this module, Wave-16a): CLOCK-ENABLE gating — no toggling on any register
//   when weight==0. Eliminates adder dynamic power entirely for zero-weight cycles.
//   Estimated +30–50% TOPS/W at 33–50% weight sparsity (GF16 ternary typical).
//
// ICG PATTERN
// -----------
// Behavioural: always_ff @(posedge clk) if (pe_clk_en) begin ... end
// SG13G2 synthesis: latch+AND ICG cell (sg13g2_icg) instantiated by synthesis tool
//   when it sees the `if (clk_en)` guard on registers.
//   For explicit mapping, instantiate: sg13g2_icg(.CLK(clk), .EN(pe_clk_en), .ENCLK(gclk))
//
// WEIGHT EXTRACTION
// -----------------
// A LOAD_B packet carries payload[15:0] = GF16 weight word.
// GF16 canonical zero: payload[14:0] == 15'h0 (sign bit ignored for zero detection).
// We use the 4-bit mantissa-nibble [3:0] as the zero-skip gate input per tri_zero_skip_gate.
// For the full-word zero check: weight == 16'h0000 OR 16'h8000 (±zero).
// To keep tri_zero_skip_gate at 4-bit input, we use payload[14:0]==0 detection directly
// in the zero-skip gate instantiation wrapper (1-wire reduction).
//
// R-SI-1: NO `*` operator in this file.
// ANCHOR: φ²+φ⁻²=3 · Wave-16a · DOI 10.5281/zenodo.19227877 · R5

`include "trinity_packet.vh"

// ---------------------------------------------------------------------------
// tt_um_trinity_max_zskip — top-level TinyTapeout wrapper (NEW, shadow mode)
// ---------------------------------------------------------------------------
module tt_um_trinity_max_zskip (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ---- Legacy combinational dot4 path (preserved for 0x47C0 backward compat) ----
    wire [15:0] dot_out;
    gf16_dot4 u_dot (
        .a0(16'h3E00), .a1(16'h4000), .a2(16'h4100), .a3(16'h4200),
        .b0(16'h3E00), .b1(16'h4000), .b2(16'h4100), .b3(16'h4200),
        .result(dot_out)
    );

    // Input echo (mirrors Max top)
    reg [15:0] input_echo;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            input_echo <= 16'h0;
        else if (ena)
            input_echo <= {ui_in, uio_in};
    end

    // ---- Mesh + FSM wires ----
    wire [31:0] host_in_pkt;
    wire        host_in_valid;
    wire        host_in_ready;
    wire [31:0] host_out_pkt;
    wire        host_out_valid;
    wire        host_out_ready;
    wire [15:0] mesh_dbg_tile0;
    wire [15:0] mesh_result;
    wire        mesh_result_valid;
    wire [7:0]  mesh_rcpt_checksum;
    wire [7:0]  mesh_rcpt_job_id;
    wire [1:0]  mesh_rcpt_tile_id;
    wire        mesh_rcpt_valid;

    // Master FSM (unchanged, freeze rule)
    trinity_master_fsm u_master (
        .clk             (clk),
        .rst_n           (rst_n),
        .ena             (ena),
        .load_mode       (ui_in[0]),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (host_in_ready),
        .host_out_pkt    (host_out_pkt),
        .host_out_valid  (host_out_valid),
        .host_out_ready  (host_out_ready),
        .result_reg      (mesh_result),
        .result_valid_q  (mesh_result_valid),
        .rcpt_checksum_q (mesh_rcpt_checksum),
        .rcpt_job_id_q   (mesh_rcpt_job_id),
        .rcpt_tile_id_q  (mesh_rcpt_tile_id),
        .rcpt_valid_q    (mesh_rcpt_valid)
    );

    // Zero-skip v2 mesh (16 tiles with clock-enable gating)
    wire [15:0] pe_clk_en_vec;  // synthesis ICG annotation — 1 bit/tile
    trinity_mesh_4x4_zskip_fabric u_mesh (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (host_in_ready),
        .host_out_pkt    (host_out_pkt),
        .host_out_valid  (host_out_valid),
        .host_out_ready  (host_out_ready),
        .dbg_tile0_result(mesh_dbg_tile0),
        .pe_clk_en_out   (pe_clk_en_vec)
    );

    // POST modules (mirrors Max top)
    wire phi_ok;
    wire post_done;
    phi_anchor_post u_phi_post (
        .clk(clk), .rst_n(rst_n),
        .phi_ok(phi_ok), .post_done(post_done)
    );

    wire [7:0] lucas_val;
    wire [2:0] lucas_idx = ui_in[3:1];
    lucas_rom u_lucas (.idx(lucas_idx), .value(lucas_val));

    wire [7:0] _l2, _l3, _l4, _l5, _l6, _l7;
    lucas_rom u_lr2 (.idx(3'd0), .value(_l2));
    lucas_rom u_lr3 (.idx(3'd1), .value(_l3));
    lucas_rom u_lr4 (.idx(3'd2), .value(_l4));
    lucas_rom u_lr5 (.idx(3'd3), .value(_l5));
    lucas_rom u_lr6 (.idx(3'd4), .value(_l6));
    lucas_rom u_lr7 (.idx(3'd5), .value(_l7));
    wire lucas_ok = (_l2 == 8'd3)  && (_l3 == 8'd4)  && (_l4 == 8'd7) &&
                    (_l5 == 8'd11) && (_l6 == 8'd18) && (_l7 == 8'd29);

    wire [15:0] hwrng_word;
    hwrng_lfsr u_rng (.clk(clk), .rst_n(rst_n), .ena(1'b1), .rnd(hwrng_word));
    wire hwrng_nonzero = |hwrng_word;

    wire [7:0] status_byte;
    wb_status_reg u_status (
        .clk(clk), .rst_n(rst_n),
        .phi_ok(phi_ok),
        .lucas_ok(lucas_ok),
        .matmul_ok(1'b1),
        .post_done(post_done),
        .rcpt_valid(mesh_rcpt_valid),
        .hwrng_nonzero(hwrng_nonzero),
        .status_byte(status_byte)
    );

    wire [15:0] final_result = mesh_result_valid ? mesh_result : dot_out;

    assign uo_out  = final_result[7:0]  | input_echo[7:0];
    assign uio_out = (ui_in[0] && post_done) ? status_byte : (final_result[15:8] | input_echo[15:8]);
    assign uio_oe  = 8'hFF;

    wire _unused = &{1'b0, mesh_dbg_tile0, pe_clk_en_vec, ena, uio_in,
                     mesh_rcpt_checksum, mesh_rcpt_job_id,
                     mesh_rcpt_tile_id, mesh_rcpt_valid,
                     lucas_val, hwrng_word[14:0],
                     ui_in[7:4], 1'b0};

endmodule
// phi^2 + phi^-2 = 3 · Wave-16a · NorthPole zero-skip v2 · DOI 10.5281/zenodo.19227877
`default_nettype wire
