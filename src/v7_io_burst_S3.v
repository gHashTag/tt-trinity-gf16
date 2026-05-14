// SPDX-License-Identifier: Apache-2.0
// v7_io_burst_S3.v — W15-TT-A: DDR/IO burst FIFO with 4-beat burst (S-3)
// TRI-NET-G1 / TT-Shuttle Squeeze v7  |  Anchor: phi^2 + phi^-2 = 3
//
// G-3 FALSIFICATION: a burst of exactly 4 data beats is always emitted
//   contiguously (no idle between beats) when burst_start is asserted and
//   the output side is ready; measured by sim stimulus counting 4 consecutive
//   out_valid cycles without a gap → FAIL if gap detected.
//
// S-3 DDR/IO interface burst optimisation:
//   Uses Tiny-Tapeout bidir uio[] pins as DDR data bus (8 pins × DDR = 16-bit
//   per edge).  This module is the on-chip FIFO and burst controller:
//   — 4-beat burst at 50 MHz → projection: 4 × 16-bit / 20 ns = 3.2 Gb/s peak
//   — Actual pin bandwidth limited by TT board (projection only, not measured)
//   — Single-clock domain; DDR edge sampling is done in the IO ring, not here.
//
// No `*`; counters use +1 only.
// USB-3 boundary only (this module uses GPIO uio[], not the USB-3 FIFO bridge).
//
`default_nettype none

module v7_io_burst_S3 #(
    parameter FIFO_DEPTH = 16,   // power-of-2, ≥ 4
    parameter DATA_W     = 16    // one DDR word (8 uio pins × 2 edges)
) (
    input  wire              clk,
    input  wire              rst_n,

    // ---- Write side (from internal datapath) ----
    input  wire [DATA_W-1:0] wr_data,
    input  wire              wr_valid,
    output wire              wr_ready,

    // ---- Burst control ----
    // Assert burst_start for one cycle to arm a 4-beat burst.
    // The module waits until at least 4 words are in the FIFO then emits them
    // back-to-back.  burst_start is ignored while a burst is in progress.
    input  wire              burst_start,

    // ---- Read side (to IO pads, DDR serialiser) ----
    output reg  [DATA_W-1:0] out_data,
    output reg               out_valid,
    input  wire              out_ready,

    // Status
    output wire [4:0]        fill_level,   // how many words are in the FIFO
    output wire              burst_active
);

    // -----------------------------------------------------------------------
    // FIFO storage (distributed flip-flops — no SRAM macro)
    // -----------------------------------------------------------------------
    localparam AW = 4;   // log2(16) = 4

    reg [DATA_W-1:0] mem [0:FIFO_DEPTH-1];
    reg [AW-1:0]     wr_ptr;
    reg [AW-1:0]     rd_ptr;
    reg [AW:0]       count;      // one extra bit for full detection

    wire fifo_full  = (count == FIFO_DEPTH[AW:0]);
    wire fifo_empty = (count == {(AW+1){1'b0}});

    assign wr_ready   = !fifo_full;
    assign fill_level = count[4:0];

    // -----------------------------------------------------------------------
    // Write path
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {AW{1'b0}};
        end else if (wr_valid && wr_ready) begin
            mem[wr_ptr] <= wr_data;
            wr_ptr      <= wr_ptr + {{(AW-1){1'b0}}, 1'b1};
        end
    end

    // -----------------------------------------------------------------------
    // Burst FSM
    // -----------------------------------------------------------------------
    localparam BURST_LEN = 4;

    reg [2:0]  burst_cnt;   // 0..4 (need 3 bits for 0..4)
    reg        bursting;

    assign burst_active = bursting;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr    <= {AW{1'b0}};
            count     <= {(AW+1){1'b0}};
            burst_cnt <= 3'd0;
            bursting  <= 1'b0;
            out_valid <= 1'b0;
            out_data  <= {DATA_W{1'b0}};
        end else begin
            // ---------- Count update ----------
            // Writes and reads can happen simultaneously
            if (wr_valid && wr_ready && !(out_valid && out_ready && bursting))
                count <= count + {{AW{1'b0}}, 1'b1};
            else if (!(wr_valid && wr_ready) && (out_valid && out_ready && bursting))
                count <= count - {{AW{1'b0}}, 1'b1};
            // else both or neither: count unchanged

            // ---------- Burst arming ----------
            if (!bursting && burst_start && (count >= BURST_LEN[AW:0])) begin
                bursting  <= 1'b1;
                burst_cnt <= 3'd0;
            end

            // ---------- Burst emission ----------
            if (bursting) begin
                // If current output slot is free (or just accepted)
                if (!out_valid || out_ready) begin
                    if (burst_cnt < BURST_LEN[2:0]) begin
                        out_data  <= mem[rd_ptr];
                        out_valid <= 1'b1;
                        rd_ptr    <= rd_ptr + {{(AW-1){1'b0}}, 1'b1};
                        burst_cnt <= burst_cnt + 3'd1;
                    end else begin
                        // Burst complete
                        out_valid <= 1'b0;
                        bursting  <= 1'b0;
                        burst_cnt <= 3'd0;
                    end
                end
            end else begin
                // Not bursting: clear output valid if accepted
                if (out_valid && out_ready)
                    out_valid <= 1'b0;
            end
        end
    end

endmodule
