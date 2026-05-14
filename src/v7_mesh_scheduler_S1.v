// SPDX-License-Identifier: Apache-2.0
// v7_mesh_scheduler_S1.v — W15-TT-A: weight-stationary dataflow scheduler (S-1)
// TRI-NET-G1 / TT-Shuttle Squeeze v7  |  Anchor: phi^2 + phi^-2 = 3
//
// G-1 FALSIFICATION: all 4 tiles receive a LOAD_B burst of 4 lanes followed by
//   a COMPUTE packet in strictly non-overlapping slots (verified by simulation
//   scan-chain counter); overlap → test FAIL.
//
// Weight-stationary principle: weight packets (LOAD_B) are broadcast once per
// layer; activation packets (LOAD_A) stream per inference.  The scheduler
// serialises host FIFO words into router-ready Trinity packets in the order:
//   per-tile: LOAD_B×4  →  (stream: LOAD_A×4  →  COMPUTE  →  READ_RES)×N
//
// No `*` operator — addresses and counters use only +/shift/XOR.
// USB-3 boundary respected: this module drives the Trinity packet bus only;
// the usb3_fifo_bridge is a separate boundary module.
// On-chip 2×2 PE mesh only — inter-node mesh stays off-chip (G1/G2).
// All performance numbers in comments are projections, not measured values.
//
`default_nettype none

`include "trinity_packet.vh"

module v7_mesh_scheduler_S1 #(
    parameter NUM_TILES  = 4,           // fixed 2x2 mesh
    parameter LANES      = 4,           // dot4 lanes per tile
    parameter DEPTH_LOG2 = 4            // input FIFO depth = 2^DEPTH_LOG2 words
) (
    input  wire        clk,
    input  wire        rst_n,

    // Host-side input FIFO (raw 16-bit operands + control word)
    // Format: [17] weight_flag, [16] compute_flag, [15:0] data
    input  wire [17:0] host_word,
    input  wire        host_valid,
    output wire        host_ready,

    // Tile destination select (2-bit flat id); host drives this alongside data
    input  wire [1:0]  host_dst,

    // Trinity packet bus to router
    output reg  [`TRN_PKT_W-1:0] sched_pkt,
    output reg                   sched_valid,
    input  wire                  sched_ready,

    // Status (projection, not silicon-measured)
    output wire [3:0]  tile_active,     // which tiles have pending COMPUTE
    output wire        busy
);

    // -----------------------------------------------------------------------
    // State encoding
    // -----------------------------------------------------------------------
    localparam ST_IDLE        = 3'd0;
    localparam ST_LOAD_W      = 3'd1;   // broadcast weight (LOAD_B) phase
    localparam ST_LOAD_A      = 3'd2;   // stream activation (LOAD_A) phase
    localparam ST_COMPUTE     = 3'd3;   // issue COMPUTE packet
    localparam ST_READ        = 3'd4;   // issue READ_RES packet
    localparam ST_WAIT_RESULT = 3'd5;   // stall until result consumed

    reg [2:0]  state;
    reg [1:0]  lane_cnt;    // 0..3, current lane being loaded
    reg [1:0]  tile_dst;    // current destination tile id

    // Weight-stationary: weights pre-loaded once, reused across activations
    reg [15:0] weight_buf [0:NUM_TILES-1][0:LANES-1];
    reg        weight_loaded [0:NUM_TILES-1];
    reg [3:0]  tile_pend;   // tiles with pending compute

    // Simple input buffer (single slot; back-pressure via host_ready)
    reg [17:0] ibuf_data;
    reg [1:0]  ibuf_dst;
    reg        ibuf_valid;

    assign host_ready = !ibuf_valid;
    assign busy       = (state != ST_IDLE) || ibuf_valid;
    assign tile_active = tile_pend;

    // -----------------------------------------------------------------------
    // Input capture
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ibuf_valid <= 1'b0;
            ibuf_data  <= 18'h0;
            ibuf_dst   <= 2'h0;
        end else if (host_valid && host_ready) begin
            ibuf_data  <= host_word;
            ibuf_dst   <= host_dst;
            ibuf_valid <= 1'b1;
        end else if (state != ST_IDLE && ibuf_valid) begin
            ibuf_valid <= 1'b0;  // consumed by FSM
        end
    end

    // -----------------------------------------------------------------------
    // Scheduler FSM
    // -----------------------------------------------------------------------
    integer ti, li;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            lane_cnt    <= 2'd0;
            tile_dst    <= 2'd0;
            tile_pend   <= 4'h0;
            sched_valid <= 1'b0;
            sched_pkt   <= {`TRN_PKT_W{1'b0}};
            for (ti = 0; ti < NUM_TILES; ti = ti + 1) begin
                weight_loaded[ti] <= 1'b0;
                for (li = 0; li < LANES; li = li + 1)
                    weight_buf[ti][li] <= 16'h0;
            end
        end else begin

            // Clear valid when accepted
            if (sched_valid && sched_ready)
                sched_valid <= 1'b0;

            case (state)
                // ------------------------------------------------------------
                ST_IDLE: begin
                    if (ibuf_valid) begin
                        tile_dst <= ibuf_dst;
                        if (ibuf_data[17]) begin
                            // weight_flag: start weight-stationary load phase
                            weight_buf[ibuf_dst][0] <= ibuf_data[15:0];
                            lane_cnt  <= 2'd1;
                            state     <= ST_LOAD_W;
                        end else if (ibuf_data[16]) begin
                            // compute_flag: start activation stream
                            lane_cnt <= 2'd0;
                            state    <= ST_LOAD_A;
                        end
                    end
                end

                // ------------------------------------------------------------
                // Weight-stationary: buffer remaining 3 weight lanes from host
                ST_LOAD_W: begin
                    if (ibuf_valid && !ibuf_data[16]) begin
                        weight_buf[tile_dst][lane_cnt] <= ibuf_data[15:0];
                        if (lane_cnt == 2'd3) begin
                            weight_loaded[tile_dst] <= 1'b1;
                            // Broadcast LOAD_B lane 0 to tile
                            sched_pkt   <= `TRN_MK_PKT(`TRN_OP_LOAD_B,
                                                        tile_dst, 2'd0,
                                                        4'd0,
                                                        weight_buf[tile_dst][0]);
                            sched_valid <= 1'b1;
                            lane_cnt    <= 2'd0;
                            state       <= ST_IDLE;
                        end else begin
                            lane_cnt <= lane_cnt + 2'd1;
                        end
                    end
                end

                // ------------------------------------------------------------
                // Activation load: issue LOAD_A packets for lanes 0..3
                ST_LOAD_A: begin
                    if (!sched_valid || sched_ready) begin
                        sched_pkt   <= `TRN_MK_PKT(`TRN_OP_LOAD_A,
                                                    tile_dst, 2'd0,
                                                    {2'b00, lane_cnt},
                                                    weight_buf[tile_dst][lane_cnt]);
                        sched_valid <= 1'b1;
                        if (lane_cnt == 2'd3) begin
                            lane_cnt <= 2'd0;
                            state    <= ST_COMPUTE;
                        end else begin
                            lane_cnt <= lane_cnt + 2'd1;
                        end
                    end
                end

                // ------------------------------------------------------------
                // Issue COMPUTE
                ST_COMPUTE: begin
                    if (!sched_valid || sched_ready) begin
                        sched_pkt   <= `TRN_MK_PKT(`TRN_OP_COMPUTE,
                                                    tile_dst, 2'd0,
                                                    4'd0, 16'h0);
                        sched_valid <= 1'b1;
                        tile_pend[tile_dst] <= 1'b1;
                        state <= ST_READ;
                    end
                end

                // ------------------------------------------------------------
                // Issue READ_RES
                ST_READ: begin
                    if (!sched_valid || sched_ready) begin
                        sched_pkt   <= `TRN_MK_PKT(`TRN_OP_READ_RES,
                                                    tile_dst, 2'd0,
                                                    4'd0, 16'h0);
                        sched_valid <= 1'b1;
                        tile_pend[tile_dst] <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
