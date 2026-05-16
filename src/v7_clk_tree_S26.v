// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// v7_clk_tree_S26.v — S-26 Fine-grain clock tree (per-PE gated distribution)
// TT-Shuttle Squeeze v7 · W15-TT-D Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// G-26 FALSIFICATION: Razor error rate < 0.1% on synthetic dot4 traffic @
//                     180 MHz post-route; else conservative 125 MHz.
//
// S-26 fine-grain clock tree: one ICG per PE cluster.
// Distributes gated clocks to N_PE processing elements with independent enable
// lines, so idle PEs draw zero dynamic power. The tree is balanced in 2 stages:
//   Stage 1: global buffer → 2 half-tile branches (left/right)
//   Stage 2: per-PE ICG from v7_clock_gate_S13 (imported structurally)
//
// The Razor flip-flops on the critical path are fed from the fastest
// (non-gated) clk path; they are instantiated in the compute datapath, not here.

`default_nettype none

module v7_clk_tree_S26 #(
    parameter N_PE = 8  // number of PEs in the tile (TT 8×2 = 8 per row)
) (
    input  wire             clk_root,          // raw PLL clock
    input  wire [N_PE-1:0]  pe_enable,         // per-PE enable from power controller
    output wire [N_PE-1:0]  clk_pe            // gated per-PE clocks
);

    // Stage-1: Two global buffers splitting the root clock (half-tile)
    // (* SYNTHESIS_BUF = "sky130_fd_sc_hd__clkbuf_16" *)
    wire clk_left, clk_right;
    assign clk_left  = clk_root;
    assign clk_right = clk_root;

    // Stage-2: Per-PE ICG from v7_clock_gate_S13
    genvar i;
    generate
        for (i = 0; i < N_PE; i = i + 1) begin : pe_icg
            // Select left or right branch based on PE index
            wire clk_branch = (i < N_PE / 2) ? clk_left : clk_right;
            v7_clock_gate_S13 icg_inst (
                .clk     (clk_branch),
                .enable  (pe_enable[i]),
                .clk_out (clk_pe[i])
            );
        end
    endgenerate

endmodule
`default_nettype wire
