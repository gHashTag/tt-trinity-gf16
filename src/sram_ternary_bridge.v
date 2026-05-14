// SPDX-License-Identifier: Apache-2.0
// Author: Dmitrii Vasilev <admin@t27.ai>
//
// L-S39: 4 KiB SRAM Ternary Bridge
//
// SRAM physical storage : 4 KiB = 4096 bytes = 32768 bits
//                         2 bits per ternary cell → 16384 cells
//                         Organized as 2048 words x 16 bits (8 cells/word)
//
// Write port (SRAM-side):
//   One 16-bit Q1.15 FP weight per cycle (wr_valid).
//   Passes through phi_prior_quantizer (N_LANES=1, 1-cycle pipe).
//   Eight consecutive ternary cells assembled into one 16-bit SRAM word.
//   SRAM word written when 8th cell completes.
//   Total write latency: 2 cycles (1 quantizer pipe + 1 SRAM write).
//
// Read port (Mesh-side):
//   8 lanes x 2-bit = 16-bit packed ternary per cycle (rd_en → rd_data 1 cycle later).
//
// Quantizer rule (Wave-9b L-S37 identical, DOI 10.5281/zenodo.19227877):
//   |w| >= 12533 (Q1.15) => sign(w) => 2'b00(+1) or 2'b10(-1)
//   |w| <  12533         => zero    => 2'b01
//
// Constraints: No */DSP. Pipeline FFs: (* keep *)(* no_retiming *). Apache-2.0.

`default_nettype none

module sram_ternary_bridge #(
    parameter integer N_CELLS = 16384,   // total 2-bit ternary cells (4 KiB * 4)
    parameter integer LANES   = 8        // mesh lanes per cycle
) (
    input  wire        clk,
    input  wire        rst_n,

    // Write port
    input  wire        wr_valid,         // high for one cycle per FP weight
    input  wire [15:0] wr_fp_in,         // Q1.15 signed FP weight

    // Read port
    input  wire        rd_en,            // advance rd pointer, latch output
    output wire [15:0] rd_data,          // 8-lane * 2-bit packed ternary

    // Status
    output wire        full,             // all N_CELLS written (wr wrapped)
    output wire        empty             // rd caught up with wr
);

    // ---------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------
    localparam integer N_WORDS  = N_CELLS / LANES;   // 2048
    localparam integer WORD_AW  = 11;                // clog2(2048) = 11
    localparam integer CELL_AW  = 14;                // clog2(16384) = 14
    localparam integer LANE_AW  = 3;                 // clog2(8) = 3

    // ---------------------------------------------------------------
    // SRAM: 2048 words x 16 bits
    // ---------------------------------------------------------------
    (* keep *) reg [15:0] mem [0:N_WORDS-1];

    // ---------------------------------------------------------------
    // Quantizer: phi_prior_quantizer N_LANES=1
    // ---------------------------------------------------------------
    wire [1:0] quant_tern;   // 1-cycle pipelined output

    phi_prior_quantizer #(
        .N_LANES (1),
        .W_BITS  (16)
    ) u_quant (
        .clk      (clk),
        .rst_n    (rst_n),
        .fp_in    (wr_fp_in),
        .tern_out (quant_tern)
    );

    // ---------------------------------------------------------------
    // Write datapath
    // ---------------------------------------------------------------
    // Stage-0 pipeline: delay wr_valid by 1 cycle to align with quant_tern
    (* keep *)(* no_retiming *)
    reg              wr_valid_d;

    // Cell write pointer (counts FP inputs, 0 .. N_CELLS-1)
    (* keep *)(* no_retiming *)
    reg [CELL_AW-1:0] wr_cell_ptr;

    // Lane counter within current SRAM word (0..7)
    (* keep *)(* no_retiming *)
    reg [LANE_AW-1:0] wr_lane_cnt;

    // SRAM word write pointer
    (* keep *)(* no_retiming *)
    reg [WORD_AW-1:0] wr_word_ptr;

    // Per-lane holding registers (filled one lane per cycle)
    (* keep *)(* no_retiming *)
    reg [1:0] lane_hold [0:LANES-1];

    // SRAM write enable + address
    (* keep *)(* no_retiming *)
    reg              sram_we;
    (* keep *)(* no_retiming *)
    reg [WORD_AW-1:0] sram_waddr;

    // Stage-0: advance cell pointer and pipeline valid
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_valid_d  <= 1'b0;
            wr_cell_ptr <= {CELL_AW{1'b0}};
        end else begin
            wr_valid_d  <= wr_valid;
            if (wr_valid)
                wr_cell_ptr <= wr_cell_ptr + {{(CELL_AW-1){1'b0}}, 1'b1};
        end
    end

    assign full = (wr_cell_ptr == {CELL_AW{1'b0}}) && wr_valid_d;

    // Stage-1: receive quantized ternary, fill lane_hold, trigger SRAM write
    integer li;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_lane_cnt <= {LANE_AW{1'b0}};
            wr_word_ptr <= {WORD_AW{1'b0}};
            sram_we     <= 1'b0;
            sram_waddr  <= {WORD_AW{1'b0}};
            for (li = 0; li < LANES; li = li + 1)
                lane_hold[li] <= 2'b01;
        end else begin
            sram_we <= 1'b0;
            if (wr_valid_d) begin
                // Store quant_tern into lane indexed by wr_lane_cnt
                if (wr_lane_cnt == 3'd0) lane_hold[0] <= quant_tern;
                if (wr_lane_cnt == 3'd1) lane_hold[1] <= quant_tern;
                if (wr_lane_cnt == 3'd2) lane_hold[2] <= quant_tern;
                if (wr_lane_cnt == 3'd3) lane_hold[3] <= quant_tern;
                if (wr_lane_cnt == 3'd4) lane_hold[4] <= quant_tern;
                if (wr_lane_cnt == 3'd5) lane_hold[5] <= quant_tern;
                if (wr_lane_cnt == 3'd6) lane_hold[6] <= quant_tern;
                if (wr_lane_cnt == 3'd7) lane_hold[7] <= quant_tern;

                wr_lane_cnt <= wr_lane_cnt + {{(LANE_AW-1){1'b0}}, 1'b1};

                // When 8th lane written, trigger SRAM write on next cycle
                if (wr_lane_cnt == 3'd7) begin
                    sram_we    <= 1'b1;
                    sram_waddr <= wr_word_ptr;
                    wr_word_ptr <= wr_word_ptr + {{(WORD_AW-1){1'b0}}, 1'b1};
                end
            end
        end
    end

    // Assemble 16-bit word: lane 0 at [1:0], lane 7 at [15:14]
    // (lane 7 captured this cycle is now in lane_hold[7] only after the
    //  always block; but sram_we fires 1 cycle later via the registered write below)
    // So the SRAM write clock after sram_we is asserted reads the already-updated lane_hold.
    wire [15:0] assembled;
    assign assembled = { lane_hold[7], lane_hold[6], lane_hold[5], lane_hold[4],
                         lane_hold[3], lane_hold[2], lane_hold[1], lane_hold[0] };

    // SRAM write
    always @(posedge clk) begin
        if (sram_we)
            mem[sram_waddr] <= assembled;
    end

    // ---------------------------------------------------------------
    // Read datapath
    // ---------------------------------------------------------------
    (* keep *)(* no_retiming *)
    reg [WORD_AW-1:0] rd_ptr;

    (* keep *)(* no_retiming *)
    reg [15:0] rd_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= {WORD_AW{1'b0}};
            rd_reg <= 16'd0;
        end else if (rd_en) begin
            rd_reg <= mem[rd_ptr];
            rd_ptr <= rd_ptr + {{(WORD_AW-1){1'b0}}, 1'b1};
        end
    end

    assign rd_data = rd_reg;
    assign empty   = (rd_ptr == wr_word_ptr);

endmodule

`default_nettype wire
