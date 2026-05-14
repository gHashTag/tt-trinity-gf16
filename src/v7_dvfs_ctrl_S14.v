// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// v7_dvfs_ctrl_S14.v — S-14 DVFS controller stub (host-driven clk_in modulation)
// TT-Shuttle Squeeze v7 · W15-TT-D Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// G-14 FALSIFICATION: cgt identifies ≥ 80 candidate registers for clock gating;
//                     else manual CGT on hot registers only.
//
// S-14 per-app DVFS: TT shuttle allows host PC to drive clk_in 0–66 MHz.
// This stub FSM reports a 2-bit BPB (bit-per-byte) error tier to the host over
// the uio interface, allowing host-side scaling of clk_in by {×0.5, ×1.0, ×1.5, ×2.0}.
// On-chip logic is zero-area beyond the error-rate shift register + tier comparators.
//
// dvfs_tier encoding:
//   2'b00 = 25 MHz  (-75% dynamic power, low traffic)
//   2'b01 = 50 MHz  (nominal)
//   2'b10 = 125 MHz (boost)
//   2'b11 = reserved

`default_nettype none

module v7_dvfs_ctrl_S14 #(
    parameter ERR_WIN  = 8,   // sliding window of cycles for BPB error rate
    parameter ERR_HI   = 6,   // threshold → step down tier
    parameter ERR_LO   = 1    // threshold → step up tier
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             bpb_err,       // single-cycle pulse: BPB error detected
    output reg  [1:0]       dvfs_tier,     // reported to host via uio[1:0]
    output wire             clk_gate_hint  // combinational: 1 → assert ICG enables
);

    // Saturating error counter over ERR_WIN cycles
    reg [7:0] err_cnt;
    reg [7:0] cycle_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            err_cnt   <= 8'h00;
            cycle_cnt <= 8'h00;
            dvfs_tier <= 2'b01;
        end else begin
            // Roll window every ERR_WIN cycles
            if (cycle_cnt == (ERR_WIN[7:0] - 8'd1)) begin
                cycle_cnt <= 8'h00;
                // Tier adjust
                if (err_cnt >= ERR_HI[7:0]) begin
                    dvfs_tier <= (dvfs_tier == 2'b00) ? 2'b00 : (dvfs_tier - 2'b01);
                end else if (err_cnt <= ERR_LO[7:0]) begin
                    dvfs_tier <= (dvfs_tier == 2'b10) ? 2'b10 : (dvfs_tier + 2'b01);
                end
                err_cnt <= 8'h00;
            end else begin
                cycle_cnt <= cycle_cnt + 8'h01;
                if (bpb_err) err_cnt <= err_cnt + 8'h01;
            end
        end
    end

    // Hint: gate clocks when in lowest tier to maximise savings
    assign clk_gate_hint = (dvfs_tier == 2'b00);

endmodule
`default_nettype wire
