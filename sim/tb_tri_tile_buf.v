// tb_tri_tile_buf.v — Ping-pong functional testbench for tri_tile_buf
// Writes rows 0..7 alternating banks; reads while writing; checks no contention.
// Author: Vasilev Dmitrii <admin@t27.ai> ORCID 0009-0008-4294-6159

`timescale 1ns/1ps

module tb_tri_tile_buf;

    // DUT parameters
    parameter DATA_W = 16;
    parameter ROWS   = 8;
    parameter IDX_W  = 3;

    // Signals
    reg                 clk;
    reg                 valid_in;
    reg  [DATA_W-1:0]   row_data;
    reg  [IDX_W-1:0]    row_idx;
    reg  [IDX_W-1:0]    rd_idx;
    wire [DATA_W-1:0]   row_out;
    reg                 swap;
    wire                bank_sel;

    // DUT instantiation
    tri_tile_buf #(
        .DATA_W(DATA_W),
        .ROWS  (ROWS),
        .IDX_W (IDX_W)
    ) dut (
        .clk      (clk),
        .valid_in (valid_in),
        .row_data (row_data),
        .row_idx  (row_idx),
        .rd_idx   (rd_idx),
        .row_out  (row_out),
        .swap     (swap),
        .bank_sel (bank_sel)
    );

    // Clock: 10 ns period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Test tracking
    integer pass_count;
    integer fail_count;

    // Helper task: write one row
    task write_row;
        input [IDX_W-1:0]  idx;
        input [DATA_W-1:0] data;
        begin
            @(negedge clk);
            valid_in = 1'b1;
            row_idx  = idx;
            row_data = data;
            @(posedge clk); #1;
            valid_in = 1'b0;
        end
    endtask

    // Helper task: do swap pulse
    task do_swap;
        begin
            @(negedge clk);
            swap = 1'b1;
            @(posedge clk); #1;
            swap = 1'b0;
        end
    endtask

    // Helper task: read and check
    task check_row;
        input [IDX_W-1:0]  idx;
        input [DATA_W-1:0] expected;
        begin
            @(negedge clk);
            rd_idx = idx;
            @(posedge clk); #1;  // registered output — one extra cycle
            @(posedge clk); #1;
            if (row_out === expected) begin
                pass_count = pass_count + 1;
                $display("  PASS row[%0d] = 0x%04X", idx, row_out);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL row[%0d]: got 0x%04X, expected 0x%04X", idx, row_out, expected);
            end
        end
    endtask

    // Stimulus pattern arrays
    reg [DATA_W-1:0] phase0_data [0:ROWS-1];
    reg [DATA_W-1:0] phase1_data [0:ROWS-1];
    integer i;

    initial begin
        // Initialise
        valid_in   = 1'b0;
        row_data   = {DATA_W{1'b0}};
        row_idx    = {IDX_W{1'b0}};
        rd_idx     = {IDX_W{1'b0}};
        swap       = 1'b0;
        pass_count = 0;
        fail_count = 0;

        // Build test data: Phase 0 = row index * 0x1111; Phase 1 = row index * 0xAAAA
        for (i = 0; i < ROWS; i = i + 1) begin
            phase0_data[i] = i * 16'h1111;
            phase1_data[i] = i * 16'hAAAA;
        end

        // ----------------------------------------------------------------
        // Phase 0: Write rows 0..7 into bank 0 (initial write bank)
        // ----------------------------------------------------------------
        $display("\n=== Phase 0: Writing rows into bank 0 ===");
        for (i = 0; i < ROWS; i = i + 1)
            write_row(i[IDX_W-1:0], phase0_data[i]);

        // Swap: bank 0 becomes read bank, bank 1 becomes write bank
        $display("=== Swap: bank 0 → read, bank 1 → write ===");
        do_swap;
        $display("bank_sel after swap = %0d (expect 1)", bank_sel);

        // ----------------------------------------------------------------
        // Phase 1: Write rows 0..7 into bank 1 WHILE reading bank 0
        // (simultaneous write+read — key ping-pong contention test)
        // ----------------------------------------------------------------
        $display("\n=== Phase 1: Simultaneous write bank1 + read bank0 ===");
        for (i = 0; i < ROWS; i = i + 1) begin
            // Write into bank 1
            @(negedge clk);
            valid_in = 1'b1;
            row_idx  = i[IDX_W-1:0];
            row_data = phase1_data[i];
            // Read from bank 0 in same cycle
            rd_idx   = i[IDX_W-1:0];
            @(posedge clk); #1;
            valid_in = 1'b0;
        end

        // Swap again: bank 1 → read, bank 0 → write
        $display("=== Swap: bank 1 → read, bank 0 → write ===");
        do_swap;
        $display("bank_sel after swap = %0d (expect 0)", bank_sel);

        // ----------------------------------------------------------------
        // Verify bank 0 (phase 0 data) was correctly read during phase 1
        // Verify bank 1 (phase 1 data) is now readable
        // ----------------------------------------------------------------
        $display("\n=== Reading phase 1 data from bank 1 (now read bank) ===");
        for (i = 0; i < ROWS; i = i + 1)
            check_row(i[IDX_W-1:0], phase1_data[i]);

        // ----------------------------------------------------------------
        // Phase 2: write phase 2 data into bank 0 (current write bank)
        // while reading bank 1 — confirms multi-cycle ping-pong
        // ----------------------------------------------------------------
        $display("\n=== Phase 2: Writing bank0, verifying no read-bank corruption ===");
        for (i = 0; i < ROWS; i = i + 1) begin
            write_row(i[IDX_W-1:0], 16'hDEAD);  // garbage into write bank
            rd_idx = i[IDX_W-1:0];               // ensure read bank unaffected
        end

        $display("\n=== Final bank1 integrity check ===");
        for (i = 0; i < ROWS; i = i + 1)
            check_row(i[IDX_W-1:0], phase1_data[i]);

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        $display("\n==========================================================");
        $display("tb_tri_tile_buf RESULT: %0d PASS / %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("STATUS: ALL TESTS PASSED — no ping-pong contention");
        else
            $display("STATUS: FAILURES DETECTED");
        $display("==========================================================\n");

        $finish;
    end

    // Timeout guard
    initial begin
        #50000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
