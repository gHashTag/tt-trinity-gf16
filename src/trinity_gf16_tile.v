`default_nettype none
// trinity_gf16_tile.v - addressable GF16 dot4 tile wrapping the existing combinational gf16_dot4.
// Apache-2.0
//
// Packet-driven interface:
//   - Accepts LOAD_A / LOAD_B packets to fill 4 operand lanes (lane 0..3).
//   - Accepts LOAD_JOB / LOAD_NONCE packets to set persisted (job_id_q, nonce_q)
//     used for deterministic on-die receipt emission (G4 — DePIN).
//   - On COMPUTE packet, latches result of gf16_dot4 into result register.
//   - On READ_RES packet, drives one outgoing RESULT packet on out_valid; the
//     cycle the host hands the RESULT off (`out_valid && out_ready`) the tile
//     re-asserts out_valid with the paired RECEIPT packet carrying
//       (tile_id, op_code=COMPUTE, checksum=(job_id_q ^ result_q[7:0]) & 0xFF,
//        job_id_lo=job_id_q).
//
// The compute is combinational (existing dot4), but the tile latches inputs and result, so
// the tile behaves as a real synchronous packet-addressable compute element inside the mesh.
//
// R-SI-1 (silicon constraint): no `*` introduced. Checksum is pure XOR-fold.
//
// L-S20 dot8 expansion:
//   DOT_WIDTH=4 (default) → single gf16_dot4, original behaviour preserved.
//   DOT_WIDTH=8           → gf16_dot8 (2× dot4 + adder); 8 A/B lanes available;
//                           TOPS per tile doubles; canonical 0x47C0 vector unaffected.
//
// L-Z02 Operand Isolation:
//   operand_iso_en tracks whether this tile has been given a COMPUTE command.
//   When operand_iso_en=0 (idle), all operand buses are AND-gated to zero via
//   operand_iso_buf instances — preventing toggle propagation into gf16_mul/add.
//   operand_iso_en asserts on first LOAD_A packet (tile armed) and stays high
//   until reset. This means idle tiles (never loaded) propagate zero operands.
//   ~8 isolators × 16 bits/dot4 mode = 128 AND2 cells; dot8 adds 8 more = 256 total.
//   Projected saving: ~8% dynamic power per tile → +8 TOPS/W system-wide.

`include "trinity_packet.vh"

module trinity_gf16_tile #(
    parameter [1:0]   TILE_ID   = 2'b00,
    // DOT_WIDTH: build-time selector for MAC unit width.
    // 4 → dot4 (original, backwards-compatible).
    // 8 → dot8 (L-S20: 2× dot4 lanes, 2× TOPS/tile).
    parameter integer DOT_WIDTH = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // Inbound packet (from router)
    input  wire [`TRN_PKT_W-1:0]   in_pkt,
    input  wire                    in_valid,
    output wire                    in_ready,

    // Outbound packet (to router) - RESULT then RECEIPT
    output reg  [`TRN_PKT_W-1:0]   out_pkt,
    output reg                     out_valid,
    input  wire                    out_ready,

    // Debug visibility
    output wire [15:0]             dbg_result
);

    // Operand registers — dot4 lanes
    reg [15:0] a0, a1, a2, a3;
    reg [15:0] b0, b1, b2, b3;
    // Extra lanes for dot8 (unused / tied to zero in dot4 mode)
    reg [15:0] a4, a5, a6, a7;
    reg [15:0] b4, b5, b6, b7;
    reg [15:0] result_q;
    reg        result_valid;

    // DePIN receipt registers
    reg [7:0]  job_id_q;
    reg [7:0]  nonce_q;
    reg [1:0]  rcpt_dst;          // remembered host src so the RECEIPT goes back to the host
    reg        pending_receipt;   // set after RESULT handshake; cleared after RECEIPT handshake

    // -----------------------------------------------------------------------
    // L-Z02: Operand Isolation Enable
    // operand_iso_en is set when this tile receives its first LOAD_A packet.
    // When low (tile never loaded / idle), isolators clamp operand buses to zero
    // — preventing spurious toggle activity from reaching gf16_mul/add cells.
    // -----------------------------------------------------------------------
    reg operand_iso_en;

    // Isolated operand wires (output of operand_iso_buf instances)
    wire [15:0] a0_iso, a1_iso, a2_iso, a3_iso;
    wire [15:0] b0_iso, b1_iso, b2_iso, b3_iso;
    wire [15:0] a4_iso, a5_iso, a6_iso, a7_iso;
    wire [15:0] b4_iso, b5_iso, b6_iso, b7_iso;

    // dot4 A-bus isolators (16 AND2 cells each → 8×16 = 128 cells in dot4 mode)
    operand_iso_buf #(.N(16)) u_iso_a0 (.enable(operand_iso_en), .in(a0), .out(a0_iso));
    operand_iso_buf #(.N(16)) u_iso_a1 (.enable(operand_iso_en), .in(a1), .out(a1_iso));
    operand_iso_buf #(.N(16)) u_iso_a2 (.enable(operand_iso_en), .in(a2), .out(a2_iso));
    operand_iso_buf #(.N(16)) u_iso_a3 (.enable(operand_iso_en), .in(a3), .out(a3_iso));

    // dot4 B-bus isolators
    operand_iso_buf #(.N(16)) u_iso_b0 (.enable(operand_iso_en), .in(b0), .out(b0_iso));
    operand_iso_buf #(.N(16)) u_iso_b1 (.enable(operand_iso_en), .in(b1), .out(b1_iso));
    operand_iso_buf #(.N(16)) u_iso_b2 (.enable(operand_iso_en), .in(b2), .out(b2_iso));
    operand_iso_buf #(.N(16)) u_iso_b3 (.enable(operand_iso_en), .in(b3), .out(b3_iso));

    // dot8 upper lane A-bus isolators (only relevant when DOT_WIDTH==8)
    operand_iso_buf #(.N(16)) u_iso_a4 (.enable(operand_iso_en), .in(a4), .out(a4_iso));
    operand_iso_buf #(.N(16)) u_iso_a5 (.enable(operand_iso_en), .in(a5), .out(a5_iso));
    operand_iso_buf #(.N(16)) u_iso_a6 (.enable(operand_iso_en), .in(a6), .out(a6_iso));
    operand_iso_buf #(.N(16)) u_iso_a7 (.enable(operand_iso_en), .in(a7), .out(a7_iso));

    // dot8 upper lane B-bus isolators
    operand_iso_buf #(.N(16)) u_iso_b4 (.enable(operand_iso_en), .in(b4), .out(b4_iso));
    operand_iso_buf #(.N(16)) u_iso_b5 (.enable(operand_iso_en), .in(b5), .out(b5_iso));
    operand_iso_buf #(.N(16)) u_iso_b6 (.enable(operand_iso_en), .in(b6), .out(b6_iso));
    operand_iso_buf #(.N(16)) u_iso_b7 (.enable(operand_iso_en), .in(b7), .out(b7_iso));

    // Combinational MAC unit — selected at build time by DOT_WIDTH parameter
    // Receives isolated operands: all-zero when tile is idle → no toggle into mul/add.
    wire [15:0] dot_out;
    generate
        if (DOT_WIDTH == 8) begin : g_dot8
            gf16_dot8 u_dot (
                .a0(a0_iso), .a1(a1_iso), .a2(a2_iso), .a3(a3_iso),
                .b0(b0_iso), .b1(b1_iso), .b2(b2_iso), .b3(b3_iso),
                .a4(a4_iso), .a5(a5_iso), .a6(a6_iso), .a7(a7_iso),
                .b4(b4_iso), .b5(b5_iso), .b6(b6_iso), .b7(b7_iso),
                .result(dot_out)
            );
        end else begin : g_dot4
            // DOT_WIDTH == 4 — original behaviour, backwards-compatible
            gf16_dot4 u_dot (
                .a0(a0_iso), .a1(a1_iso), .a2(a2_iso), .a3(a3_iso),
                .b0(b0_iso), .b1(b1_iso), .b2(b2_iso), .b3(b3_iso),
                .result(dot_out)
            );
        end
    endgenerate

    // Accept any packet addressed to us when out FIFO slot is free
    assign in_ready = !out_valid || out_ready;

    wire pkt_for_me = (`TRN_PKT_DST(in_pkt) == TILE_ID);
    wire [3:0] op   = `TRN_PKT_OP(in_pkt);
    wire [3:0] lane = `TRN_PKT_LANE(in_pkt);
    wire [15:0] pl  = `TRN_PKT_PAYLOAD(in_pkt);

    // R-SI-1 honest checksum: 8-bit XOR-fold. Matches Python
    // tools/receipt_verifier/tri_receipt_verifier.compute_checksum() byte-for-byte.
    wire [7:0] rcpt_checksum_w = job_id_q ^ result_q[7:0];

    assign dbg_result = result_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a0 <= 16'h0; a1 <= 16'h0; a2 <= 16'h0; a3 <= 16'h0;
            b0 <= 16'h0; b1 <= 16'h0; b2 <= 16'h0; b3 <= 16'h0;
            a4 <= 16'h0; a5 <= 16'h0; a6 <= 16'h0; a7 <= 16'h0;
            b4 <= 16'h0; b5 <= 16'h0; b6 <= 16'h0; b7 <= 16'h0;
            result_q <= 16'h0;
            result_valid <= 1'b0;
            job_id_q  <= 8'h00;
            nonce_q   <= 8'h00;
            rcpt_dst  <= 2'h0;
            pending_receipt <= 1'b0;
            out_pkt   <= {`TRN_PKT_W{1'b0}};
            out_valid <= 1'b0;
            // L-Z02: all tiles start isolated (operand buses clamped to zero)
            operand_iso_en <= 1'b0;
        end else begin
            // Outbound handshake: clear, then re-arm with RECEIPT if pending.
            if (out_valid && out_ready) begin
                if (pending_receipt) begin
                    // We just handed RESULT to the host; re-fire with the paired RECEIPT.
                    out_pkt   <= `TRN_MK_RCPT(rcpt_dst,
                                              TILE_ID,
                                              `TRN_OP_COMPUTE,
                                              job_id_q,
                                              rcpt_checksum_w);
                    out_valid <= 1'b1;
                    pending_receipt <= 1'b0;
                end else begin
                    // RECEIPT (or any other final packet) handed off.
                    out_valid <= 1'b0;
                end
            end

            // Inbound handling. Note: we still accept LOAD_*/COMPUTE packets while
            // out_valid is high if in_ready latched them; pkt_for_me is the gate.
            if (in_valid && in_ready && pkt_for_me) begin
                case (op)
                    `TRN_OP_LOAD_A: begin
                        // L-Z02: arm isolator on first LOAD_A — tile is now active
                        operand_iso_en <= 1'b1;
                        case (lane[2:0])
                            3'd0: a0 <= pl;
                            3'd1: a1 <= pl;
                            3'd2: a2 <= pl;
                            3'd3: a3 <= pl;
                            3'd4: a4 <= pl;  // dot8 upper lane 4
                            3'd5: a5 <= pl;  // dot8 upper lane 5
                            3'd6: a6 <= pl;  // dot8 upper lane 6
                            3'd7: a7 <= pl;  // dot8 upper lane 7
                        endcase
                    end
                    `TRN_OP_LOAD_B: begin
                        case (lane[2:0])
                            3'd0: b0 <= pl;
                            3'd1: b1 <= pl;
                            3'd2: b2 <= pl;
                            3'd3: b3 <= pl;
                            3'd4: b4 <= pl;  // dot8 upper lane 4
                            3'd5: b5 <= pl;  // dot8 upper lane 5
                            3'd6: b6 <= pl;  // dot8 upper lane 6
                            3'd7: b7 <= pl;  // dot8 upper lane 7
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
                        if (!out_valid || out_ready) begin
                            out_pkt   <= `TRN_MK_PKT(`TRN_OP_RESULT,
                                                    `TRN_PKT_SRC(in_pkt),
                                                    TILE_ID,
                                                    4'h0,
                                                    result_q);
                            out_valid <= 1'b1;
                            // Schedule the paired RECEIPT for the cycle after the
                            // RESULT handshake completes. Remember the host id.
                            rcpt_dst        <= `TRN_PKT_SRC(in_pkt);
                            pending_receipt <= 1'b1;
                        end
                    end
                    default: ; // NOP / unknown -> ignore
                endcase
            end
        end
    end

endmodule
