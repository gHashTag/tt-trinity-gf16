// SPDX-License-Identifier: Apache-2.0
// ledger_receipt_v2.v — Per-tile compute receipt generator (L-S44)
// Apache-2.0
//
// Receipt format (128-bit packed):
//   {tile_id[1:0], window_ctr[29:0], result_hash[31:0], merkle_leaf[63:0]}
//
// Hash: 3-round XOR+rotate (ternary-friendly, no SHA, no DSP, no *)
// Constraint R-SI-1: NO multiply / DSP usage.
//
// PhD anchor: Chapter 36 / TG-TRIAD-X — cross-die ledger determinism.
// DOI: 10.5281/zenodo.19227877
// Author: Dmitrii Vasilev <admin@t27.ai>

`default_nettype none

module ledger_receipt_v2 (
    input  wire        clk,
    input  wire        rst_n,
    // Per-tile compute window inputs
    input  wire [1:0]  tile_id,       // which tile (0..3)
    input  wire        window_valid,  // pulse: new compute window result ready
    input  wire [31:0] result,        // 32-bit dot4 / MAC result from this tile
    // Outputs
    output reg  [127:0] receipt,      // packed 128-bit receipt
    output reg          receipt_valid // high for one cycle after receipt is assembled
);

    // -----------------------------------------------------------------------
    // 30-bit window counter — rolls over naturally
    // -----------------------------------------------------------------------
    (* keep *) (* no_retiming *)
    reg [29:0] window_ctr;

    // -----------------------------------------------------------------------
    // Stage-1 pipeline registers — latch inputs on window_valid
    // -----------------------------------------------------------------------
    (* keep *) (* no_retiming *)
    reg [1:0]  s1_tile_id;
    (* keep *) (* no_retiming *)
    reg [29:0] s1_window_ctr;
    (* keep *) (* no_retiming *)
    reg [31:0] s1_result;
    (* keep *) (* no_retiming *)
    reg        s1_valid;

    // -----------------------------------------------------------------------
    // Stage-2 pipeline registers — hash result
    // -----------------------------------------------------------------------
    (* keep *) (* no_retiming *)
    reg [1:0]  s2_tile_id;
    (* keep *) (* no_retiming *)
    reg [29:0] s2_window_ctr;
    (* keep *) (* no_retiming *)
    reg [31:0] s2_result_hash;
    (* keep *) (* no_retiming *)
    reg        s2_valid;

    // -----------------------------------------------------------------------
    // Stage-3 pipeline registers — merkle leaf
    // -----------------------------------------------------------------------
    (* keep *) (* no_retiming *)
    reg [1:0]  s3_tile_id;
    (* keep *) (* no_retiming *)
    reg [29:0] s3_window_ctr;
    (* keep *) (* no_retiming *)
    reg [31:0] s3_result_hash;
    (* keep *) (* no_retiming *)
    reg [63:0] s3_merkle_leaf;
    (* keep *) (* no_retiming *)
    reg        s3_valid;

    // -----------------------------------------------------------------------
    // Lightweight hash function — 3-round XOR+rotate (ternary-friendly)
    // No multiply, no DSP, no SHA.
    // rotate_left_N(x, k) is purely a wire permutation.
    // -----------------------------------------------------------------------

    // rotate_left by 7 bits (32-bit)
    function [31:0] rol32_7;
        input [31:0] x;
        rol32_7 = {x[24:0], x[31:25]};
    endfunction

    // rotate_left by 13 bits (32-bit)
    function [31:0] rol32_13;
        input [31:0] x;
        rol32_13 = {x[18:0], x[31:19]};
    endfunction

    // rotate_left by 17 bits (32-bit)
    function [31:0] rol32_17;
        input [31:0] x;
        rol32_17 = {x[14:0], x[31:15]};
    endfunction

    // 3-round hash: mix result with tile_id and window_ctr seed
    // seed_a derives from tile_id + window_ctr (no mul: shift-xor)
    // Round 1: h  = result ^ (seed_a)
    // Round 2: h  = rol32_7(h) ^ (seed_a >> 5 ^ rol32_13(result))
    // Round 3: h  = rol32_17(h) ^ (seed_a << 3 ^ result)
    function [31:0] hash3;
        input [31:0] data;
        input [1:0]  tid;
        input [29:0] wctr;
        reg   [31:0] seed_a;
        reg   [31:0] h;
        begin
            // Build seed: tile_id in bits [31:30], window_ctr in bits [29:0]
            seed_a = {tid, wctr};
            // Round 1
            h = data ^ seed_a;
            // Round 2: rotate h left by 7, xor with rotated-seed mix
            h = rol32_7(h) ^ (seed_a ^ rol32_13(data));
            // Round 3: rotate h left by 17, xor with another mix
            h = rol32_17(h) ^ ({seed_a[28:0], 3'b000} ^ data);
            hash3 = h;
        end
    endfunction

    // 64-bit merkle leaf: interleave hash with window_ctr + tile_id
    // Merkle leaf packs:
    //   bits [63:32] = hash3(rol32_13(result), tile_id, window_ctr)
    //   bits [31:0]  = result_hash (from stage 2) XOR {window_ctr[29:0], tile_id}
    function [63:0] merkle_leaf_fn;
        input [31:0] rh;      // result_hash from stage-2
        input [31:0] res;     // original result
        input [1:0]  tid;
        input [29:0] wctr;
        reg   [31:0] upper;
        reg   [31:0] lower;
        begin
            upper = hash3(rol32_13(res), tid, wctr);
            lower = rh ^ {wctr, tid};
            merkle_leaf_fn = {upper, lower};
        end
    endfunction

    // -----------------------------------------------------------------------
    // Pipeline stage 1: counter advance + latch inputs
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_ctr  <= 30'b0;
            s1_tile_id  <= 2'b0;
            s1_window_ctr <= 30'b0;
            s1_result   <= 32'b0;
            s1_valid    <= 1'b0;
        end else begin
            s1_valid <= 1'b0;
            if (window_valid) begin
                s1_tile_id    <= tile_id;
                s1_window_ctr <= window_ctr;
                s1_result     <= result;
                s1_valid      <= 1'b1;
                window_ctr    <= window_ctr + 30'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Pipeline stage 2: compute result_hash
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_tile_id      <= 2'b0;
            s2_window_ctr   <= 30'b0;
            s2_result_hash  <= 32'b0;
            s2_valid        <= 1'b0;
        end else begin
            s2_valid <= 1'b0;
            if (s1_valid) begin
                s2_tile_id     <= s1_tile_id;
                s2_window_ctr  <= s1_window_ctr;
                s2_result_hash <= hash3(s1_result, s1_tile_id, s1_window_ctr);
                s2_valid       <= 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Pipeline stage 3: compute merkle_leaf
    // -----------------------------------------------------------------------
    // We need the original result to compute merkle leaf upper half.
    // Carry it through a separate delay register.
    (* keep *) (* no_retiming *)
    reg [31:0] s2_result_orig;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_result_orig <= 32'b0;
        end else begin
            if (s1_valid) begin
                s2_result_orig <= s1_result;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_tile_id      <= 2'b0;
            s3_window_ctr   <= 30'b0;
            s3_result_hash  <= 32'b0;
            s3_merkle_leaf  <= 64'b0;
            s3_valid        <= 1'b0;
        end else begin
            s3_valid <= 1'b0;
            if (s2_valid) begin
                s3_tile_id     <= s2_tile_id;
                s3_window_ctr  <= s2_window_ctr;
                s3_result_hash <= s2_result_hash;
                s3_merkle_leaf <= merkle_leaf_fn(
                    s2_result_hash,
                    s2_result_orig,
                    s2_tile_id,
                    s2_window_ctr
                );
                s3_valid <= 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Output stage: pack receipt
    // Format: {tile_id[1:0], window_ctr[29:0], result_hash[31:0], merkle_leaf[63:0]}
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            receipt       <= 128'b0;
            receipt_valid <= 1'b0;
        end else begin
            receipt_valid <= 1'b0;
            if (s3_valid) begin
                receipt <= {s3_tile_id, s3_window_ctr, s3_result_hash, s3_merkle_leaf};
                receipt_valid <= 1'b1;
            end
        end
    end

endmodule
`default_nettype wire
