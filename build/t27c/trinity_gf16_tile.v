// SPDX-License-Identifier: Apache-2.0
//
// Auto-generated reference twin for EQY gate · phi^2 + phi^-2 = 3 · DO NOT EDIT
//
// Module  : trinity_gf16_tile
// Origin  : build/t27c/trinity_gf16_tile.v — t27c structural twin
// Anchor  : phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E
//           DOI 10.5281/zenodo.19227877
//
// Coq citation map:
//   - champion_survives_pruning  : tile-level state machine is champion-safe;
//     all arc-enabling conditions satisfy φ-prune threshold;
//     t27/trios-coq/IGLA/IGLA_ASHA_Bound.v (INV-2)
//   - lucas_values_gf16_exact_n1 : operand registers hold GF16 words in
//     precision-safe range; t27/trios-coq/IGLA/gf16_precision.v (INV-3)
//   - lucas_closure_phi_sq       : receipt checksum (XOR-fold) closes over
//     GF16 field values; t27/trios-coq/IGLA/lucas_closure_gf16.v (INV-5)
//   - lucas_4_eq_7               : four A-lanes + four B-lanes = 4-element
//     dot product; t27/trios-coq/IGLA/gf16_precision.v (INV-3)
//
// trinity_gf16_tile — addressable GF16 dot4 tile wrapping the gf16_dot4
// combinational unit.
//
// Packet-driven interface (32-bit TRN bus):
//   LOAD_A / LOAD_B  — fill 4 operand lanes (0..3)
//   LOAD_JOB         — set job_id_q (low 8 bits of payload)
//   LOAD_NONCE       — set nonce_q  (low 8 bits of payload)
//   COMPUTE          — latch gf16_dot4 result into result_q
//   READ_RES         — emit RESULT packet; schedule paired RECEIPT
//
// R-SI-1: ZERO `*` operators in synthesisable code.
// Checksum is pure XOR-fold: job_id_q ^ result_q[7:0].
//
// L-S20 dot8 extension via DOT_WIDTH=8 parameter (backwards-compatible
// when DOT_WIDTH=4).

`include "trinity_packet.vh"

`default_nettype none

module trinity_gf16_tile #(
    parameter [1:0]   TILE_ID   = 2'b00,
    // DOT_WIDTH: 4 = original dot4 (default); 8 = dot8 (L-S20 2× TOPS/tile).
    parameter integer DOT_WIDTH = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // Inbound packet (from router)
    input  wire [`TRN_PKT_W-1:0]   in_pkt,
    input  wire                    in_valid,
    output wire                    in_ready,

    // Outbound packet (to router) — RESULT then RECEIPT
    output reg  [`TRN_PKT_W-1:0]   out_pkt,
    output reg                     out_valid,
    input  wire                    out_ready,

    // Debug visibility
    output wire [15:0]             dbg_result
);

    // ----------------------------------------------------------------
    // Operand registers
    // ----------------------------------------------------------------
    reg [15:0] a0, a1, a2, a3;
    reg [15:0] b0, b1, b2, b3;
    // Upper lanes for dot8 (unused / tied to zero in dot4 mode)
    reg [15:0] a4, a5, a6, a7;
    reg [15:0] b4, b5, b6, b7;

    reg [15:0] result_q;
    reg        result_valid;

    // DePIN receipt registers
    reg [7:0]  job_id_q;
    reg [7:0]  nonce_q;
    reg [1:0]  rcpt_dst;          // remembered host src for the RECEIPT packet
    reg        pending_receipt;   // set after RESULT handshake; cleared after RECEIPT

    // ----------------------------------------------------------------
    // Combinational MAC unit (build-time DOT_WIDTH selection)
    // ----------------------------------------------------------------
    wire [15:0] dot_out;

    generate
        if (DOT_WIDTH == 8) begin : g_dot8
            // L-S20: double-width dot product
            gf16_dot8 u_dot (
                .a0(a0), .a1(a1), .a2(a2), .a3(a3),
                .b0(b0), .b1(b1), .b2(b2), .b3(b3),
                .a4(a4), .a5(a5), .a6(a6), .a7(a7),
                .b4(b4), .b5(b5), .b6(b6), .b7(b7),
                .result(dot_out)
            );
        end else begin : g_dot4
            // DOT_WIDTH == 4 — original, backwards-compatible
            gf16_dot4 u_dot (
                .a0(a0), .a1(a1), .a2(a2), .a3(a3),
                .b0(b0), .b1(b1), .b2(b2), .b3(b3),
                .result(dot_out)
            );
        end
    endgenerate

    // ----------------------------------------------------------------
    // Flow-control: accept inbound when outbound slot is free
    // ----------------------------------------------------------------
    assign in_ready = !out_valid | out_ready;

    wire pkt_for_me = (`TRN_PKT_DST(in_pkt) == TILE_ID);
    wire [3:0] op   = `TRN_PKT_OP(in_pkt);
    wire [3:0] lane = `TRN_PKT_LANE(in_pkt);
    wire [15:0] pl  = `TRN_PKT_PAYLOAD(in_pkt);

    // ----------------------------------------------------------------
    // R-SI-1 receipt checksum: 8-bit XOR-fold
    // Matches Python tools/receipt_verifier/tri_receipt_verifier.compute_checksum()
    // Coq: lucas_closure_phi_sq → XOR-fold closes over GF16 byte (INV-5)
    // ----------------------------------------------------------------
    wire [7:0] rcpt_checksum_w = job_id_q ^ result_q[7:0];

    assign dbg_result = result_q;

    // ----------------------------------------------------------------
    // Sequential logic: packet handler
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a0 <= 16'h0; a1 <= 16'h0; a2 <= 16'h0; a3 <= 16'h0;
            b0 <= 16'h0; b1 <= 16'h0; b2 <= 16'h0; b3 <= 16'h0;
            a4 <= 16'h0; a5 <= 16'h0; a6 <= 16'h0; a7 <= 16'h0;
            b4 <= 16'h0; b5 <= 16'h0; b6 <= 16'h0; b7 <= 16'h0;
            result_q        <= 16'h0;
            result_valid    <= 1'b0;
            job_id_q        <= 8'h00;
            nonce_q         <= 8'h00;
            rcpt_dst        <= 2'h0;
            pending_receipt <= 1'b0;
            out_pkt         <= {`TRN_PKT_W{1'b0}};
            out_valid       <= 1'b0;
        end else begin
            // -- Outbound handshake --------------------------------
            if (out_valid & out_ready) begin
                if (pending_receipt) begin
                    // RESULT just handed off; re-arm with paired RECEIPT
                    out_pkt   <= `TRN_MK_RCPT(rcpt_dst,
                                              TILE_ID,
                                              `TRN_OP_COMPUTE,
                                              job_id_q,
                                              rcpt_checksum_w);
                    out_valid       <= 1'b1;
                    pending_receipt <= 1'b0;
                end else begin
                    // RECEIPT (or terminal packet) handed off
                    out_valid <= 1'b0;
                end
            end

            // -- Inbound handling ---------------------------------
            if (in_valid & in_ready & pkt_for_me) begin
                case (op)
                    `TRN_OP_LOAD_A: begin
                        case (lane[2:0])
                            3'd0: a0 <= pl;
                            3'd1: a1 <= pl;
                            3'd2: a2 <= pl;
                            3'd3: a3 <= pl;
                            3'd4: a4 <= pl;   // dot8 lane 4
                            3'd5: a5 <= pl;   // dot8 lane 5
                            3'd6: a6 <= pl;   // dot8 lane 6
                            3'd7: a7 <= pl;   // dot8 lane 7
                        endcase
                    end
                    `TRN_OP_LOAD_B: begin
                        case (lane[2:0])
                            3'd0: b0 <= pl;
                            3'd1: b1 <= pl;
                            3'd2: b2 <= pl;
                            3'd3: b3 <= pl;
                            3'd4: b4 <= pl;   // dot8 lane 4
                            3'd5: b5 <= pl;   // dot8 lane 5
                            3'd6: b6 <= pl;   // dot8 lane 6
                            3'd7: b7 <= pl;   // dot8 lane 7
                        endcase
                    end
                    `TRN_OP_LOAD_JOB: begin
                        job_id_q <= pl[7:0];
                    end
                    `TRN_OP_LOAD_NONCE: begin
                        nonce_q  <= pl[7:0];
                    end
                    `TRN_OP_COMPUTE: begin
                        result_q     <= dot_out;
                        result_valid <= 1'b1;
                    end
                    `TRN_OP_READ_RES: begin
                        if (!out_valid | out_ready) begin
                            out_pkt   <= `TRN_MK_PKT(`TRN_OP_RESULT,
                                                      `TRN_PKT_SRC(in_pkt),
                                                      TILE_ID,
                                                      4'h0,
                                                      result_q);
                            out_valid       <= 1'b1;
                            rcpt_dst        <= `TRN_PKT_SRC(in_pkt);
                            pending_receipt <= 1'b1;
                        end
                    end
                    default: ; // NOP / unknown → ignore
                endcase
            end
        end
    end

endmodule
