// SPDX-License-Identifier: Apache-2.0
// d2d_serdes_stub.v — L-S47 Die-to-Die SerDes Stub (digital only)
//
// 8b/10b-lite encoding: {ctrl[1:0], payload[7:0]} = 10-bit line word
// TX side: payload[7:0] + ctrl[1:0] → line[9:0] + line_valid, req/ack
// RX side: line[9:0] + line_valid   → payload[7:0] + ctrl[1:0], req/ack
// 1-cycle pipeline per side (registered outputs)
// No * / no DSP (R-SI-1)
// Author: Dmitrii Vasilev <admin@t27.ai>
// DOI: 10.5281/zenodo.19227877
// Anchor: φ² + φ⁻² = 3

`timescale 1ns/1ps

// ============================================================
// D2D SerDes Stub — TX + RX in one module
// ============================================================
module d2d_serdes_stub (
    input  wire        clk,
    input  wire        rst_n,

    // --- TX interface ---
    input  wire [7:0]  tx_payload,      // 8-bit data payload
    input  wire [1:0]  tx_ctrl,         // 2 control bits (K-comma etc.)
    input  wire        tx_valid,        // source asserts valid
    output wire        tx_ready,        // stub asserts ready (ack)

    // --- Line (TX → RX) ---
    output wire [9:0]  tx_line,         // encoded 10-bit line word
    output wire        tx_line_valid,   // line valid sideband

    // --- RX interface ---
    input  wire [9:0]  rx_line,         // encoded 10-bit line word
    input  wire        rx_line_valid,   // line valid sideband
    output wire [7:0]  rx_payload,      // decoded 8-bit payload
    output wire [1:0]  rx_ctrl,         // decoded control bits
    output wire        rx_valid,        // RX asserts data valid
    input  wire        rx_ready         // downstream asserts ready
);

    // ----------------------------------------------------------
    // TX path — 1-cycle pipeline
    // 8b/10b-lite encode: line = {ctrl[1:0], payload[7:0]}
    // tx_ready: stub accepts every cycle (no backpressure on line)
    // ----------------------------------------------------------

    (* keep *) (* no_retiming *) reg [9:0]  tx_line_r;
    (* keep *) (* no_retiming *) reg        tx_line_valid_r;

    assign tx_ready = 1'b1; // always ready — 1-deep registered, no backpressure

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_line_r       <= 10'b0;
            tx_line_valid_r <= 1'b0;
        end else begin
            if (tx_valid) begin
                // 8b/10b-lite encode: {ctrl[1:0], payload[7:0]}
                tx_line_r       <= {tx_ctrl, tx_payload};
                tx_line_valid_r <= 1'b1;
            end else begin
                tx_line_r       <= 10'b0;
                tx_line_valid_r <= 1'b0;
            end
        end
    end

    assign tx_line       = tx_line_r;
    assign tx_line_valid = tx_line_valid_r;

    // ----------------------------------------------------------
    // RX path — 1-cycle pipeline
    // 8b/10b-lite decode: {ctrl, payload} = rx_line
    // Backpressure: if rx_ready is low and rx_valid_r is high,
    // hold the current word until rx_ready asserts.
    // ----------------------------------------------------------

    (* keep *) (* no_retiming *) reg [9:0]  rx_line_r;
    (* keep *) (* no_retiming *) reg        rx_valid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_line_r  <= 10'b0;
            rx_valid_r <= 1'b0;
        end else begin
            if (!rx_valid_r || rx_ready) begin
                // Capture when slot is empty or being drained
                rx_line_r  <= rx_line;
                rx_valid_r <= rx_line_valid;
            end
            // else: stall — hold current word
        end
    end

    // 8b/10b-lite decode: straightforward field extraction
    assign rx_payload = rx_line_r[7:0];
    assign rx_ctrl    = rx_line_r[9:8];
    assign rx_valid   = rx_valid_r;

endmodule
