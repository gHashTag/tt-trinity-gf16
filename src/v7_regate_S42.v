// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// v7_regate_S42.v — S-42 ReGate PE-level power gating (1-cycle wake)
// TT-Shuttle Squeeze v7 · W15-TT-D Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// G-42 FALSIFICATION: SPICE: gated PE static current ≤ 1 nA @ 25°C nominal.
//
// S-42 ReGate-style PE-level fine-grain power gating:
//   Every PE has a 1-bit nz_detect (S-16 sparsity flag) wired to a sleep
//   transistor. Idle PE gates off in 1 cycle. Wake-up: 1 state machine cycle
//   to charge internal nodes before resuming compute.
//
//   Combined with S-29 RBB: idle PE → clock-gated + power-gated + body-biased
//   → leakage approaches zero (sub-pA).
//
// Cite: ReGate arXiv 2508.02536 (+0.68% area total, +6.36% per-PE, -10.1% SA energy)
//
// Wake-up FSM states:
//   SLEEP  (2'b00): sleep transistor OFF; clk gated
//   WAKE   (2'b01): sleep transistor turning ON; 1-cycle charge-up
//   ACTIVE (2'b10): fully active, compute running

`default_nettype none

module v7_regate_S42 (
    input  wire  clk,
    input  wire  rst_n,
    input  wire  nz_detect,      // from S-16 zero-skip: 1 = non-zero weight → PE needed
    output wire  sleep_n,        // sleep transistor enable (active-low = sleep)
    output wire  pe_clk_en,      // 1 = allow clk to PE (fed to ICG S-13)
    output wire  pe_active        // 1 = PE is fully active (ready for compute)
);

    // FSM states
    localparam SLEEP  = 2'b00;
    localparam WAKE   = 2'b01;
    localparam ACTIVE = 2'b10;

    reg [1:0] state_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= SLEEP;
        end else begin
            case (state_q)
                SLEEP: begin
                    // Wake request: nz_detect asserted
                    if (nz_detect) state_q <= WAKE;
                    else           state_q <= SLEEP;
                end
                WAKE: begin
                    // 1-cycle charge-up; unconditionally advance to ACTIVE
                    state_q <= ACTIVE;
                end
                ACTIVE: begin
                    // Return to sleep when no work
                    if (!nz_detect) state_q <= SLEEP;
                    else            state_q <= ACTIVE;
                end
                default: state_q <= SLEEP;
            endcase
        end
    end

    // Output decode
    assign sleep_n   = (state_q != SLEEP);     // HIGH = sleep transistor ON (not sleeping)
    assign pe_clk_en = (state_q == ACTIVE);    // clock only when fully active
    assign pe_active = (state_q == ACTIVE);

endmodule
`default_nettype wire
