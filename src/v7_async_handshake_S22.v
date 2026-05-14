// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 TRI-NET-G1 / TT-Shuttle Squeeze v7
//
// v7_async_handshake_S22.v — 4-phase bundled-data handshake for inter-tile dot32 transfer
// Stream S-22 · Wave W15-TT-F · Anchor φ²+φ⁻²=3
//
// G-22 FALSIFICATION: async lane completes 1000 dot4 ops without handshake
//                     violations in simulation → else lane scheduled Wave-16
//
// 4-phase protocol (Null Convention Logic / ACT-style):
//   Phase 0: Sender drives req=0, data stable (null)
//   Phase 1: Sender drives req=1, data valid  → wait ack=1
//   Phase 2: Sender de-asserts req=0           → wait ack=0
//   Phase 3: Idle — both req=0, ack=0          → ready for next cycle
//
// This is a "self-healing model" for asynchronous communication.
// No claims of trusted execution are made.
//
// No wildcard (*) instantiations — all ports explicit.
// `default_nettype none required by caller.

`default_nettype none

module v7_async_handshake_S22 #(
    parameter DATA_W = 32   // bundled data width (dot32 transfer)
) (
    // ---------------------------------------------------------------
    // Sender side
    // ---------------------------------------------------------------
    input  wire              send_clk,       // sender local clock (sync wrapper)
    input  wire              send_rst_n,
    input  wire [DATA_W-1:0] send_data,      // data to transfer
    input  wire              send_valid,     // pulse: data is ready to send
    output reg               send_ready,     // high when sender can accept next item

    // ---------------------------------------------------------------
    // Async handshake wires (cross-clock)
    // ---------------------------------------------------------------
    output reg               req,            // request line (sender → receiver)
    input  wire              ack,            // acknowledge line (receiver → sender)

    // ---------------------------------------------------------------
    // Receiver side
    // ---------------------------------------------------------------
    input  wire              recv_clk,       // receiver local clock
    input  wire              recv_rst_n,
    output reg  [DATA_W-1:0] recv_data,      // captured data
    output reg               recv_valid,     // one-cycle strobe: data is valid
    input  wire              recv_ready,     // receiver can accept

    // Acknowledge output driven by receiver
    output reg               ack_out         // connect to `ack` input above
);

    // ================================================================
    // Sender FSM
    // States: IDLE → ASSERT_REQ → WAIT_ACK → DEASSERT_REQ → WAIT_NACK
    // ================================================================
    localparam [2:0]
        S_IDLE         = 3'd0,
        S_ASSERT_REQ   = 3'd1,
        S_WAIT_ACK     = 3'd2,
        S_DEASSERT_REQ = 3'd3,
        S_WAIT_NACK    = 3'd4;

    reg [2:0]       send_state;
    reg [DATA_W-1:0] latch_data;

    // Two-stage synchroniser: ack → send_clk domain
    reg ack_s1, ack_sync;
    always @(posedge send_clk or negedge send_rst_n) begin
        if (!send_rst_n) begin
            ack_s1   <= 1'b0;
            ack_sync <= 1'b0;
        end else begin
            ack_s1   <= ack;
            ack_sync <= ack_s1;
        end
    end

    always @(posedge send_clk or negedge send_rst_n) begin
        if (!send_rst_n) begin
            send_state <= S_IDLE;
            req        <= 1'b0;
            send_ready <= 1'b1;
            latch_data <= {DATA_W{1'b0}};
        end else begin
            case (send_state)
                S_IDLE: begin
                    send_ready <= 1'b1;
                    req        <= 1'b0;
                    if (send_valid) begin
                        latch_data <= send_data;
                        send_ready <= 1'b0;
                        send_state <= S_ASSERT_REQ;
                    end
                end

                S_ASSERT_REQ: begin
                    req        <= 1'b1;
                    send_state <= S_WAIT_ACK;
                end

                S_WAIT_ACK: begin
                    // Wait until receiver asserts ack
                    if (ack_sync) begin
                        send_state <= S_DEASSERT_REQ;
                    end
                end

                S_DEASSERT_REQ: begin
                    req        <= 1'b0;
                    send_state <= S_WAIT_NACK;
                end

                S_WAIT_NACK: begin
                    // Wait until receiver de-asserts ack (phase 3 complete)
                    if (!ack_sync) begin
                        send_ready <= 1'b1;
                        send_state <= S_IDLE;
                    end
                end

                default: send_state <= S_IDLE;
            endcase
        end
    end

    // ================================================================
    // Receiver FSM
    // States: IDLE → WAIT_REQ → CAPTURE → ASSERT_ACK → WAIT_DEASSERT → DEASSERT_ACK
    // ================================================================
    localparam [2:0]
        R_IDLE          = 3'd0,
        R_WAIT_REQ      = 3'd1,
        R_CAPTURE       = 3'd2,
        R_ASSERT_ACK    = 3'd3,
        R_WAIT_DEASSERT = 3'd4,
        R_DEASSERT_ACK  = 3'd5;

    reg [2:0] recv_state;

    // Two-stage synchroniser: req → recv_clk domain
    reg req_s1, req_sync;
    always @(posedge recv_clk or negedge recv_rst_n) begin
        if (!recv_rst_n) begin
            req_s1   <= 1'b0;
            req_sync <= 1'b0;
        end else begin
            req_s1   <= req;
            req_sync <= req_s1;
        end
    end

    always @(posedge recv_clk or negedge recv_rst_n) begin
        if (!recv_rst_n) begin
            recv_state <= R_IDLE;
            ack_out    <= 1'b0;
            recv_data  <= {DATA_W{1'b0}};
            recv_valid <= 1'b0;
        end else begin
            recv_valid <= 1'b0;  // default: pulse for one cycle only

            case (recv_state)
                R_IDLE: begin
                    ack_out    <= 1'b0;
                    recv_state <= R_WAIT_REQ;
                end

                R_WAIT_REQ: begin
                    if (req_sync) begin
                        recv_state <= R_CAPTURE;
                    end
                end

                R_CAPTURE: begin
                    // Latch bundled data when req is seen stable
                    recv_data  <= latch_data; // combinational path from sender latch
                    recv_valid <= 1'b1;
                    recv_state <= R_ASSERT_ACK;
                end

                R_ASSERT_ACK: begin
                    ack_out    <= 1'b1;
                    recv_state <= R_WAIT_DEASSERT;
                end

                R_WAIT_DEASSERT: begin
                    // Wait for sender to de-assert req
                    if (!req_sync) begin
                        recv_state <= R_DEASSERT_ACK;
                    end
                end

                R_DEASSERT_ACK: begin
                    ack_out    <= 1'b0;
                    recv_state <= R_IDLE;
                end

                default: recv_state <= R_IDLE;
            endcase
        end
    end

endmodule
