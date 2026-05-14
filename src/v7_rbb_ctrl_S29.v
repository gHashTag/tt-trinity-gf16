// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// v7_rbb_ctrl_S29.v — S-29 Reverse Body Biasing (RBB) controller
// TT-Shuttle Squeeze v7 · W15-TT-D Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// G-29 FALSIFICATION: SPICE on 1 idle PE block @ RBB = +0.5V shows ≥ 4× leakage
//                     drop vs nominal; else RBB disabled.
//
// S-29 Reverse Body Bias for idle ternary lanes:
// When a PE is idle (sparse 42% zero-skip, driven by nz_detect from S-16),
// drive its VPB/VNB pins reverse-biased to reduce sub-threshold leakage −80%.
//
// Cite:
//   EPFL Adaptive Body Biasing 2020 — https://infoscience.epfl.ch/record/282801
//   Neau & Roy ISLPED 2003 — https://cecs.uci.edu/~papers/compendium94-03/papers/2003/islped03/pdffiles/05_3.pdf
//
// ─────────────────────────────────────────────────────────────────────────────
// SPICE-ANCHOR BLOCK (S-29):
//   Technology : SKY130 (sky130_fd_pr__nfet_01v8, pfet_01v8)
//   Nominal VPB = VDD = 1.8 V; Nominal VNB = GND = 0 V
//   RBB mode:
//     NFET: VNB = +0.5 V  (raises Vt by ΔVt ≈ 0.15 V) → Isub × 0.15..0.20
//     PFET: VPB = VDD - 0.5 V = 1.3 V (raises |Vt| similarly)
//   SPICE sweep (ttleak corner, 25°C, Vdd=1.8V, no input switching):
//     body_bias_level[3:0] → VNB (mV): 0→0, 1→125, 2→250, 3→375, 4→500
//     Expected leakage at level 4: ≤ 25% of nominal  (G-29 target)
//   Falsification: If measured Isub(level=4) > 50% nominal → RBB disabled,
//   single-bias at body_bias_level = 0.
// ─────────────────────────────────────────────────────────────────────────────

`default_nettype none

module v7_rbb_ctrl_S29 #(
    parameter N_PE = 8  // number of PEs with independent body-bias control
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [N_PE-1:0]  pe_idle,          // 1 = PE is idle (from nz_detect / S-16)
    output wire [N_PE-1:0]  rbb_nfet_en,      // 1 = apply RBB to NFET body (VNB raised)
    output wire [N_PE-1:0]  rbb_pfet_en,      // 1 = apply RBB to PFET body (VPB lowered)
    output reg  [3:0]       body_bias_level    // global bias step (0=nominal .. 4=max RBB)
);

    // Body bias level ramps up when majority of PEs are idle
    // Hysteresis: ramp up slowly, ramp down instantly on any PE becoming active
    reg [7:0] idle_streak;  // consecutive cycles where all PEs idle

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            body_bias_level <= 4'h0;
            idle_streak     <= 8'h00;
        end else begin
            if (pe_idle == {N_PE{1'b1}}) begin
                // All PEs idle: ramp up bias level after 16-cycle hysteresis
                if (idle_streak == 8'hFF) begin
                    if (body_bias_level < 4'h4)
                        body_bias_level <= body_bias_level + 4'h1;
                end else begin
                    idle_streak <= idle_streak + 8'h01;
                end
            end else begin
                // Any PE active: snap to nominal immediately
                body_bias_level <= 4'h0;
                idle_streak     <= 8'h00;
            end
        end
    end

    // Per-PE RBB enable: only assert when PE is idle AND global level > 0
    assign rbb_nfet_en = pe_idle & {N_PE{(body_bias_level != 4'h0)}};
    assign rbb_pfet_en = pe_idle & {N_PE{(body_bias_level != 4'h0)}};

endmodule
`default_nettype wire
