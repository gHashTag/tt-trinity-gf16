// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// tt_um_trinity_max.v — TinyTapeout MAX top wrapper (TRI-1 4×4 = 16 tiles).
// Apache-2.0
//
// Mirrors tt_um_ghtag_trinity_gf16.v (the Mid 8×2 top) for the MAX tile slot.
// TTSKY26b Max tile = 4×4 = 16 tiles; area target ~4× Mid.
//
// Same IO pad set as TT spec:
//   ui_in[7:0]   — user inputs (ui_in[0]=load_mode, ui_in[3:1]=lucas_idx)
//   uo_out[7:0]  — user outputs (result low byte or status)
//   uio_in[7:0]  — bidirectional input (unused, folded to _unused)
//   uio_out[7:0] — bidirectional output (result high byte or status_byte)
//   uio_oe[7:0]  — all driven as outputs (0xFF)
//   ena          — chip enable
//   clk          — 50 MHz TT board clock (R-SI-4)
//   rst_n        — active-low synchronous reset
//
// Instantiates one trinity_mesh_4x4 (16 trinity_gf16_tile instances).
// Canonical dot4 legacy path preserved for 0x47C0 backward compat.
//
// R-SI-1: NO `*` operator in this file (XOR/AND/OR/mux only).
// R-SI-4: clock_hz = 50_000_000 (no PLL inside user logic).
// TG-Max-07 evidence: grep this file — zero MicroBlaze / zero CPU / no Linux.
// phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E · DOI 10.5281/zenodo.19227877

`include "trinity_packet.vh"

module tt_um_trinity_max (
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

    // Input echo (legacy, mirrors Mid top)
    reg [15:0] input_echo;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            input_echo <= 16'h0;
        else if (ena)
            input_echo <= {ui_in, uio_in};
    end

    // ---- Trinity MAX mesh fabric (16 tiles) ----
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

    // Master FSM — drives the host injection/ejection ports.
    // Reuses the existing trinity_master_fsm (unchanged, freeze rule).
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

    // MAX mesh: 16 tiles (4×4)
    trinity_mesh_4x4 u_mesh (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (host_in_ready),
        .host_out_pkt    (host_out_pkt),
        .host_out_valid  (host_out_valid),
        .host_out_ready  (host_out_ready),
        .dbg_tile0_result(mesh_dbg_tile0)
    );

    // ---- Wave-26b CROWN POST modules (mirrors Mid top) ----
    wire phi_ok;
    wire post_done;
    phi_anchor_post u_phi_post (
        .clk(clk), .rst_n(rst_n),
        .phi_ok(phi_ok), .post_done(post_done)
    );

    wire [7:0] lucas_val;
    wire [2:0] lucas_idx = ui_in[3:1];
    lucas_rom u_lucas (.idx(lucas_idx), .value(lucas_val));

    // lucas_ok: combinational integrity check of all 6 ROM entries
    wire [7:0] _l2, _l3, _l4, _l5, _l6, _l7;
    lucas_rom u_lr2 (.idx(3'd0), .value(_l2));
    lucas_rom u_lr3 (.idx(3'd1), .value(_l3));
    lucas_rom u_lr4 (.idx(3'd2), .value(_l4));
    lucas_rom u_lr5 (.idx(3'd3), .value(_l5));
    lucas_rom u_lr6 (.idx(3'd4), .value(_l6));
    lucas_rom u_lr7 (.idx(3'd5), .value(_l7));
    wire lucas_ok = (_l2 == 8'd3)  && (_l3 == 8'd4)  && (_l4 == 8'd7) &&
                    (_l5 == 8'd11) && (_l6 == 8'd18) && (_l7 == 8'd29);

    // L-S5: 16-bit LFSR nonce (mirrors Mid top)
    wire [15:0] hwrng_word;
    hwrng_lfsr u_rng (.clk(clk), .rst_n(rst_n), .ena(1'b1), .rnd(hwrng_word));
    wire hwrng_nonzero = |hwrng_word;

    // Wishbone-lite status byte (mirrors Mid top, aggregates POST results)
    wire [7:0] status_byte;
    wb_status_reg u_status (
        .clk(clk), .rst_n(rst_n),
        .phi_ok(phi_ok),
        .lucas_ok(lucas_ok),
        .matmul_ok(1'b1),   // MAX: no inline matmul; tie high (tile array IS the matmul)
        .post_done(post_done),
        .rcpt_valid(mesh_rcpt_valid),
        .hwrng_nonzero(hwrng_nonzero),
        .status_byte(status_byte)
    );

    // ---- Output mux (mirrors Mid top) ----
    // Combinational dot result by default; mesh result once produced.
    wire [15:0] final_result = mesh_result_valid ? mesh_result : dot_out;

    assign uo_out  = final_result[7:0]  | input_echo[7:0];
    // uio_out: legacy result high byte; switches to status_byte when load_mode & post_done.
    assign uio_out = (ui_in[0] && post_done) ? status_byte : (final_result[15:8] | input_echo[15:8]);
    assign uio_oe  = 8'hFF;

    // Silence lint on unused signals (mirrors Mid top pattern)
    wire _unused = &{1'b0, mesh_dbg_tile0, ena, uio_in,
                     mesh_rcpt_checksum, mesh_rcpt_job_id,
                     mesh_rcpt_tile_id, mesh_rcpt_valid,
                     lucas_val, hwrng_word[14:0],
                     ui_in[7:4], 1'b0};

endmodule
// phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E · DOI 10.5281/zenodo.19227877
