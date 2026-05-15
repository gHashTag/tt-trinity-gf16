`default_nettype none
// trinity_gf16_tile_poly.v — packet-addressable GF(2^4) compute tile using
// the polynomial multiplier (gf16_poly_mul).
//
// Anchor: phi^2+phi^-2=3  DOI 10.5281/zenodo.19227877
// Apache-2.0
// Author: Vasilev Dmitrii <admin@t27.ai>  ORCID 0009-0008-4294-6159
//
// Wave-16a PATH-3 SHADOW: new tile variant for experimental GF(2^4) poly mesh.
// ZERO RISK to Octad PR #35-40, #43 — this module is NOT referenced by any
// existing top-level or info.yaml entry.
//
// Protocol identical to trinity_gf16_tile.v (DOT_WIDTH=4 mode):
//   - 4-bit GF16 operands packed in low 4 bits of 16-bit packet payload
//   - LOAD_A / LOAD_B / COMPUTE / READ_RES / RECEIPT sequence preserved
//   - RECEIPT: checksum = job_id_q ^ result_q[7:0], job_id_lo = job_id_q
//   - R-SI-1: no $mul cells anywhere in hierarchy

`include "trinity_packet.vh"

module trinity_gf16_tile_poly #(
    parameter [1:0] TILE_ID = 2'b00
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

    // Debug visibility — lower 4 bits carry native GF(2^4) result
    output wire [15:0]             dbg_result
);

    // Operand registers — 4-bit native GF(2^4) lanes
    // Payload arrives in in_pkt[3:0] (low 4 bits of 16-bit payload field)
    reg [3:0] a0, a1, a2, a3;
    reg [3:0] b0, b1, b2, b3;
    // Result stored in 16-bit register; upper 12 bits always 0 in poly mode
    reg [15:0] result_q;
    reg        result_valid;

    // DePIN receipt registers (matching trinity_gf16_tile.v protocol)
    reg [7:0]  job_id_q;
    reg [7:0]  nonce_q;
    reg [1:0]  rcpt_dst;
    reg        pending_receipt;

    // Combinational GF(2^4) dot product
    wire [3:0] dot_out;

    gf16_dot4_poly u_dot (
        .a0(a0), .a1(a1), .a2(a2), .a3(a3),
        .b0(b0), .b1(b1), .b2(b2), .b3(b3),
        .result(dot_out)
    );

    // Packet decode
    wire pkt_for_me = (`TRN_PKT_DST(in_pkt) == TILE_ID);
    wire [3:0] op   = `TRN_PKT_OP(in_pkt);
    wire [3:0] lane = `TRN_PKT_LANE(in_pkt);
    wire [15:0] pl  = `TRN_PKT_PAYLOAD(in_pkt);

    // R-SI-1 honest checksum: 8-bit XOR-fold
    wire [7:0] rcpt_checksum_w = job_id_q ^ result_q[7:0];

    assign dbg_result = result_q;

    // Tile is always ready to accept if we're not holding an unaccepted outbound
    assign in_ready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a0 <= 4'h0; a1 <= 4'h0; a2 <= 4'h0; a3 <= 4'h0;
            b0 <= 4'h0; b1 <= 4'h0; b2 <= 4'h0; b3 <= 4'h0;
            result_q      <= 16'h0;
            result_valid  <= 1'b0;
            job_id_q      <= 8'h00;
            nonce_q       <= 8'h00;
            rcpt_dst      <= 2'h0;
            pending_receipt <= 1'b0;
            out_pkt       <= {`TRN_PKT_W{1'b0}};
            out_valid     <= 1'b0;
        end else begin
            // Outbound handshake
            if (out_valid && out_ready) begin
                if (pending_receipt) begin
                    out_pkt   <= `TRN_MK_RCPT(rcpt_dst,
                                              TILE_ID,
                                              `TRN_OP_COMPUTE,
                                              job_id_q,
                                              rcpt_checksum_w);
                    out_valid <= 1'b1;
                    pending_receipt <= 1'b0;
                end else begin
                    out_valid <= 1'b0;
                end
            end

            // Inbound handling
            if (in_valid && in_ready && pkt_for_me) begin
                case (op)
                    `TRN_OP_LOAD_A: begin
                        case (lane[1:0])
                            2'd0: a0 <= pl[3:0];
                            2'd1: a1 <= pl[3:0];
                            2'd2: a2 <= pl[3:0];
                            2'd3: a3 <= pl[3:0];
                        endcase
                    end
                    `TRN_OP_LOAD_B: begin
                        case (lane[1:0])
                            2'd0: b0 <= pl[3:0];
                            2'd1: b1 <= pl[3:0];
                            2'd2: b2 <= pl[3:0];
                            2'd3: b3 <= pl[3:0];
                        endcase
                    end
                    `TRN_OP_LOAD_JOB: begin
                        job_id_q <= pl[7:0];
                    end
                    `TRN_OP_LOAD_NONCE: begin
                        nonce_q  <= pl[7:0];
                    end
                    `TRN_OP_COMPUTE: begin
                        result_q     <= {12'h000, dot_out};
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
                            rcpt_dst        <= `TRN_PKT_SRC(in_pkt);
                            pending_receipt <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule
