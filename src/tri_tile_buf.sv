// tri_tile_buf.sv — Per-tile activation row-buffer with ping-pong (2 banks)
// Hailo-style inter-layer activation streaming (Wave-16a shadow feature)
// R-SI-1: 0 $mul — all logic is mux/FF/combinational decode only.
//
// Anchor: φ²+φ⁻²=3 · DOI 10.5281/zenodo.19227877
// Author: Vasilev Dmitrii <admin@t27.ai> ORCID 0009-0008-4294-6159

`default_nettype none

module tri_tile_buf #(
    parameter DATA_W  = 16,   // activation word width (GF16 → 16-bit)
    parameter ROWS    = 8,    // number of rows per tile
    parameter IDX_W   = 3    // ceil(log2(ROWS))
) (
    input  wire                 clk,
    // Write port — current layer writes into the inactive bank
    input  wire                 valid_in,
    input  wire [DATA_W-1:0]    row_data,
    input  wire [IDX_W-1:0]     row_idx,
    // Read port — next layer reads from the active (completed) bank
    input  wire [IDX_W-1:0]     rd_idx,
    output reg  [DATA_W-1:0]    row_out,
    // Bank-swap handshake
    input  wire                 swap,    // pulse: retire write bank → becomes read bank
    output wire                 bank_sel // current write bank indicator (0 or 1)
);

    // -----------------------------------------------------------------------
    // Ping-pong storage: 2 banks × ROWS entries × DATA_W bits
    // Implemented as individual registers (no SRAM macro needed for sim/synth)
    // -----------------------------------------------------------------------
    reg [DATA_W-1:0] bank0 [0:ROWS-1];
    reg [DATA_W-1:0] bank1 [0:ROWS-1];

    // Current write bank (toggles on swap)
    reg wr_bank;

    assign bank_sel = wr_bank;

    // -----------------------------------------------------------------------
    // Write logic — write into inactive (current wr_bank) bank
    // -----------------------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (swap)
            wr_bank <= ~wr_bank;   // flip write bank on swap pulse

        if (valid_in) begin
            if (wr_bank == 1'b0) begin
                bank0[row_idx] <= row_data;
            end else begin
                bank1[row_idx] <= row_data;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Read logic — read from the completed (opposite) bank combinatorially,
    // register output one cycle for timing closure.
    // -----------------------------------------------------------------------
    wire [DATA_W-1:0] rd_data;

    // Read bank is always the opposite of the write bank
    assign rd_data = (wr_bank == 1'b1) ? bank0[rd_idx] : bank1[rd_idx];

    always @(posedge clk) begin
        row_out <= rd_data;
    end

    // -----------------------------------------------------------------------
    // Reset / initialisation block (simulation only; synthesises away)
    // -----------------------------------------------------------------------
    initial begin : init_banks
        integer j;
        wr_bank = 1'b0;
        for (j = 0; j < ROWS; j = j + 1) begin
            bank0[j] = {DATA_W{1'b0}};
            bank1[j] = {DATA_W{1'b0}};
        end
    end

endmodule

`default_nettype wire
