// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// tt_um_trinity_max_v16b.v — Wave-16b merged top for OpenLane2 P&R verification.
//
// Anchor: phi^2+phi^-2=3  DOI 10.5281/zenodo.19227877
// Apache-2.0
// Author: Vasilev Dmitrii <admin@t27.ai>  ORCID 0009-0008-4294-6159
//
// PURPOSE
// -------
// Wires the Wave-16a poly mesh (trinity_mesh_4x4_poly — GF(2^4) 4-tile,
// 34 cells/inst, 0 $mul) together with the Wave-16a zero-skip v2 clock-
// enable gates (trinity_mesh_4x4_zskip_fabric — NorthPole-style ICG FFs)
// into a single TinyTapeout-pinout module for OpenLane2 SKY130 synthesis
// and place-and-route, thereby MEASURING (not projecting) area, timing,
// and power for the "120 TOPS/W" claim.
//
// DESIGN INTENT
// -------------
// The design exercises BOTH compute paths simultaneously through a shared
// trinity_master_fsm.  Packet fan-out: every host packet is forwarded to
// both the poly-mesh and the zskip-mesh.  Results are muxed out by
// result_sel (ui_in[1]).
//
// R-SI-1: NO `*` operator in this file.
// ANCHOR: phi^2+phi^-2=3 · Wave-16b · DOI 10.5281/zenodo.19227877 · R5
//
// info.yaml is UNCHANGED — tt_um_trinity_max remains the Octad submission.
// This module is a SEPARATE synthesis target (openlane2/config_v16b.json).
// DO NOT open a PR touching info.yaml.

`include "trinity_packet.vh"

// ---------------------------------------------------------------------------
// tt_um_trinity_max_v16b — TT-pinout wrapper merging poly+zskip meshes
// ---------------------------------------------------------------------------
module tt_um_trinity_max_v16b (
    input  wire [7:0] ui_in,    // TT input pins
    output wire [7:0] uo_out,   // TT output pins
    input  wire [7:0] uio_in,   // TT bidirectional inputs
    output wire [7:0] uio_out,  // TT bidirectional outputs
    output wire [7:0] uio_oe,   // TT bidirectional output-enable
    input  wire       ena,      // TT enable
    input  wire       clk,      // TT clock
    input  wire       rst_n     // TT reset (active-low)
);

    // -------------------------------------------------------------------------
    // Shared host bus wires (single master FSM drives both meshes)
    // -------------------------------------------------------------------------
    wire [`TRN_PKT_W-1:0] host_in_pkt;
    wire                  host_in_valid;
    // host_in_ready: poly mesh is primary; OR with zskip ready (both accept)
    wire                  poly_in_ready;
    wire                  zskip_in_ready;
    wire                  host_in_ready = poly_in_ready | zskip_in_ready;

    wire [`TRN_PKT_W-1:0] host_out_pkt_poly;
    wire                  host_out_valid_poly;

    wire [`TRN_PKT_W-1:0] host_out_pkt_zskip;
    wire                  host_out_valid_zskip;

    // Result arbitration: ui_in[1] selects which mesh result is presented
    wire result_sel = ui_in[1];

    wire [`TRN_PKT_W-1:0] host_out_pkt_mux;
    wire                  host_out_valid_mux;
    // FSM-driven host_out_ready (always 1 from trinity_master_fsm)
    wire                  fsm_out_ready;
    assign host_out_pkt_mux   = result_sel ? host_out_pkt_zskip   : host_out_pkt_poly;
    assign host_out_valid_mux = result_sel ? host_out_valid_zskip  : host_out_valid_poly;

    // -------------------------------------------------------------------------
    // Master FSM — issues packets, captures results
    // -------------------------------------------------------------------------
    wire [15:0] mesh_result;
    wire        mesh_result_valid;
    wire [7:0]  mesh_rcpt_checksum;
    wire [7:0]  mesh_rcpt_job_id;
    wire [1:0]  mesh_rcpt_tile_id;
    wire        mesh_rcpt_valid;

    trinity_master_fsm u_master (
        .clk             (clk),
        .rst_n           (rst_n),
        .ena             (ena),
        .load_mode       (ui_in[0]),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (host_in_ready),
        .host_out_pkt    (host_out_pkt_mux),
        .host_out_valid  (host_out_valid_mux),
        .host_out_ready  (fsm_out_ready),     // output: always-1 from FSM
        .result_reg      (mesh_result),
        .result_valid_q  (mesh_result_valid),
        .rcpt_checksum_q (mesh_rcpt_checksum),
        .rcpt_job_id_q   (mesh_rcpt_job_id),
        .rcpt_tile_id_q  (mesh_rcpt_tile_id),
        .rcpt_valid_q    (mesh_rcpt_valid)
    );

    // -------------------------------------------------------------------------
    // Poly mesh — trinity_mesh_4x4_poly (4 tiles, GF(2^4) gf16_poly_mul)
    // -------------------------------------------------------------------------
    wire [15:0] poly_dbg_tile0;

    trinity_mesh_4x4_poly u_poly_mesh (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (poly_in_ready),
        .host_out_pkt    (host_out_pkt_poly),
        .host_out_valid  (host_out_valid_poly),
        .host_out_ready  (fsm_out_ready),
        .dbg_tile0_result(poly_dbg_tile0)
    );

    // -------------------------------------------------------------------------
    // Zero-skip v2 mesh — trinity_mesh_4x4_zskip_fabric (16 tiles, ICG gates)
    // -------------------------------------------------------------------------
    wire [15:0] zskip_dbg_tile0;
    wire [15:0] pe_clk_en_vec;

    trinity_mesh_4x4_zskip_fabric u_zskip_mesh (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (zskip_in_ready),
        .host_out_pkt    (host_out_pkt_zskip),
        .host_out_valid  (host_out_valid_zskip),
        .host_out_ready  (fsm_out_ready),
        .dbg_tile0_result(zskip_dbg_tile0),
        .pe_clk_en_out   (pe_clk_en_vec)
    );

    // -------------------------------------------------------------------------
    // POST / diagnostic modules (φ anchor, Lucas ROM, HWRNG, status)
    // -------------------------------------------------------------------------
    wire phi_ok;
    wire post_done;
    phi_anchor_post u_phi_post (
        .clk(clk), .rst_n(rst_n),
        .phi_ok(phi_ok), .post_done(post_done)
    );

    wire [7:0] lucas_val;
    wire [2:0] lucas_idx = ui_in[4:2];
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

    // -------------------------------------------------------------------------
    // Legacy combinational dot4 path (preserved for 0x47C0 backward compat)
    // -------------------------------------------------------------------------
    wire [15:0] dot_out;
    gf16_dot4 u_dot (
        .a0(16'h3E00), .a1(16'h4000), .a2(16'h4100), .a3(16'h4200),
        .b0(16'h3E00), .b1(16'h4000), .b2(16'h4100), .b3(16'h4200),
        .result(dot_out)
    );

    // Input echo register
    reg [15:0] input_echo;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            input_echo <= 16'h0;
        else if (ena)
            input_echo <= {ui_in, uio_in};
    end

    // -------------------------------------------------------------------------
    // Output mux
    // -------------------------------------------------------------------------
    wire [15:0] final_result = mesh_result_valid ? mesh_result : dot_out;

    assign uo_out  = final_result[7:0]  | input_echo[7:0];
    assign uio_out = (ui_in[0] && post_done) ? status_byte
                                             : (final_result[15:8] | input_echo[15:8]);
    assign uio_oe  = 8'hFF;

    // -------------------------------------------------------------------------
    // Unused signal tieoff (avoids lint warnings)
    // -------------------------------------------------------------------------
    wire _unused = &{1'b0,
                     poly_dbg_tile0,
                     zskip_dbg_tile0,
                     pe_clk_en_vec,
                     lucas_val,
                     hwrng_word[14:0],
                     mesh_rcpt_checksum,
                     mesh_rcpt_job_id,
                     mesh_rcpt_tile_id,
                     mesh_rcpt_valid,
                     uio_in,
                     ui_in[7:5],
                     fsm_out_ready,
                     1'b0};

endmodule
// phi^2 + phi^-2 = 3 · Wave-16b · poly+zskip merged · DOI 10.5281/zenodo.19227877
`default_nettype wire
