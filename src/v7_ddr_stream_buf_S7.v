// SPDX-License-Identifier: Apache-2.0
// v7_ddr_stream_buf_S7.v — W15-TT-A: DDR streaming ping-pong buffer (S-7)
// TRI-NET-G1 / TT-Shuttle Squeeze v7  |  Anchor: phi^2 + phi^-2 = 3
//
// G-7 FALSIFICATION: while the compute side processes buffer-A, the IO side
//   can fill buffer-B without stall; stall (fill stall while compute is busy)
//   → test FAIL.  Verified by simulation stimulus that fires both sides
//   concurrently and checks io_stall == 0 while compute_busy == 1.
//
// S-7: DDR bidir uio[] as streaming DDR data path (16-bit per DDR cycle).
//   This ping-pong buffer hides the IO latency behind compute:
//     — Buffer A fills from the IO side while Buffer B drains to compute
//     — On swap: A becomes the compute source, B the IO sink
//   Projection: 400 MB/s IO peak (16 bits × DDR 100 MHz effective); actual
//   board bandwidth is projection only, not a silicon-measured value.
//
// No `*` — buffer addressing uses only increment/decrement.
// USB-3 boundary: the FT60x lives in trinity_usb3_fifo_bridge.v; this module
// uses the bidir uio GPIO path, separate from USB-3.
//
`default_nettype none

module v7_ddr_stream_buf_S7 #(
    parameter BUF_DEPTH  = 8,    // words per half-buffer; power-of-2
    parameter DATA_W     = 16    // DDR word width (8 uio × 2 edges)
) (
    input  wire              clk,
    input  wire              rst_n,

    // ---- IO fill side (from v7_io_burst_S3 or DDR pads) ----
    input  wire [DATA_W-1:0] io_data,
    input  wire              io_valid,
    output wire              io_ready,
    output wire              io_stall,  // G-7 falsification probe

    // ---- Compute drain side (to scheduler / tile) ----
    output reg  [DATA_W-1:0] cmp_data,
    output reg               cmp_valid,
    input  wire              cmp_ready,

    // Status
    output wire              swap_flag,    // pulses one cycle on buffer swap
    output wire              compute_busy  // high while compute side is draining
);

    localparam AW = 3;  // log2(8)

    // -----------------------------------------------------------------------
    // Dual buffers (A=0, B=1), indexed by [buf_sel]
    // -----------------------------------------------------------------------
    reg [DATA_W-1:0] bufA [0:BUF_DEPTH-1];
    reg [DATA_W-1:0] bufB [0:BUF_DEPTH-1];

    // io_buf: which buffer the IO side is currently writing (0=A, 1=B)
    // cmp_buf: which buffer the compute side is draining (always opposite)
    reg io_buf;      // 0 → writing bufA; 1 → writing bufB
    reg cmp_buf;     // 0 → reading bufA; 1 → reading bufB

    reg [AW-1:0] io_wptr;
    reg [AW-1:0] cmp_rptr;
    reg          cmp_buf_full;  // set when compute buffer has BUF_DEPTH words ready
    reg          io_buf_full;   // set when io buffer has been filled
    reg          swapping;

    assign swap_flag    = swapping;
    assign compute_busy = cmp_buf_full || (cmp_rptr != {AW{1'b0}});
    assign io_stall     = io_buf_full;   // G-7: must be 0 while compute is busy
    assign io_ready     = !io_buf_full;

    // -----------------------------------------------------------------------
    // IO fill path
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin : p_io_fill
        integer ii;
        if (!rst_n) begin
            io_wptr    <= {AW{1'b0}};
            io_buf     <= 1'b0;
            io_buf_full<= 1'b0;
        end else begin
            // Swap handshake: when compute side drains its buffer and io has
            // a full buffer, swap the roles.
            if (swapping) begin
                // After swap: io writes into the freshly-emptied buffer
                io_buf      <= cmp_buf;   // take over the just-drained side
                io_wptr     <= {AW{1'b0}};
                io_buf_full <= 1'b0;
            end else if (io_valid && io_ready) begin
                if (io_buf == 1'b0)
                    bufA[io_wptr] <= io_data;
                else
                    bufB[io_wptr] <= io_data;

                if (io_wptr == (BUF_DEPTH[AW-1:0] - {{(AW-1){1'b0}}, 1'b1})) begin
                    io_buf_full <= 1'b1;
                    io_wptr     <= {AW{1'b0}};
                end else begin
                    io_wptr <= io_wptr + {{(AW-1){1'b0}}, 1'b1};
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // Compute drain path
    // -----------------------------------------------------------------------
    reg swap_r;
    assign swapping = swap_r;

    always @(posedge clk or negedge rst_n) begin : p_cmp_drain
        if (!rst_n) begin
            cmp_rptr     <= {AW{1'b0}};
            cmp_buf      <= 1'b1;      // start draining bufB (empty at reset)
            cmp_buf_full <= 1'b0;
            cmp_valid    <= 1'b0;
            cmp_data     <= {DATA_W{1'b0}};
            swap_r       <= 1'b0;
        end else begin
            swap_r <= 1'b0;  // default: no swap pulse

            // Accept io-full → arm compute side
            if (!cmp_buf_full && io_buf_full && !swap_r) begin
                cmp_buf      <= io_buf;   // compute drains the filled buffer
                cmp_buf_full <= 1'b1;
                cmp_rptr     <= {AW{1'b0}};
                swap_r       <= 1'b1;     // trigger IO side to swap
            end

            // Drain: issue data words to compute
            if (cmp_buf_full) begin
                if (!cmp_valid || cmp_ready) begin
                    cmp_data  <= (cmp_buf == 1'b0) ? bufA[cmp_rptr] : bufB[cmp_rptr];
                    cmp_valid <= 1'b1;
                    if (cmp_rptr == (BUF_DEPTH[AW-1:0] - {{(AW-1){1'b0}}, 1'b1})) begin
                        cmp_rptr     <= {AW{1'b0}};
                        cmp_buf_full <= 1'b0;
                        // Do NOT clear cmp_valid here; last word still in flight
                    end else begin
                        cmp_rptr <= cmp_rptr + {{(AW-1){1'b0}}, 1'b1};
                    end
                end
            end else begin
                if (cmp_valid && cmp_ready)
                    cmp_valid <= 1'b0;
            end
        end
    end

endmodule
