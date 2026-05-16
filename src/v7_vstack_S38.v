// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// v7_vstack_S38.v — S-38 Voltage stacking 2-tier (V/2 supply current model)
// TT-Shuttle Squeeze v7 · W15-TT-D Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// G-38 FALSIFICATION: SPICE: external Vdd supply current ≤ 60% of equivalent
//                     flat-supply baseline at same MAC throughput.
//
// S-38 Voltage stacking 2-tier:
//   Cluster-A runs on (Vdd_top - Vdd_mid) = 0.9 V
//   Cluster-B runs on (Vdd_mid - GND)     = 0.9 V
//   External supply current halved: I_ext = I_total / 2
//
// Cite: NSF Voltage-Stacked PDS — https://par.nsf.gov/servlets/purl/10186068
//
// ─────────────────────────────────────────────────────────────────────────────
// SPICE-ANCHOR BLOCK (S-38):
//   Technology : SKY130 (1.8 V nominal)
//   Stack topology: VDD_TOP=1.8V → cluster_A (0.9V swing) → VDD_MID=0.9V
//                   VDD_MID=0.9V → cluster_B (0.9V swing) → GND=0V
//   Level shifters at cluster boundary: sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_*
//   Decoupling caps on VDD_MID: re-use MOM caps from S-32 (~3000 µm²)
//   SPICE sweep: Monte Carlo 100 runs, TT/FF/SS corners, 25°C
//     Metric: I_VDD_TOP vs I_VDD_flat (same compute load)
//     Target: I_VDD_TOP ≤ 0.60 × I_VDD_flat (G-38)
//   Falsification: If P95 I_VDD_TOP > 0.65 × I_VDD_flat → VStack disabled,
//   single-rail 1.8 V fallback.
// ─────────────────────────────────────────────────────────────────────────────
//
// RTL model: mid-rail driver + level-shifter wrappers for the cluster boundary.
// The mid-rail voltage domain itself is not modelled in RTL (SPICE-only);
// this module provides the level-shifter + charge-balance control interface.

`default_nettype none

module v7_vstack_S38 #(
    parameter DATA_W = 8  // data bus width across tier boundary
) (
    input  wire              clk,
    input  wire              rst_n,

    // Cluster-A outputs (running at 0.9V swing, Vdd_top domain)
    input  wire [DATA_W-1:0] tier_a_data,       // data from cluster-A
    input  wire              tier_a_valid,

    // Cluster-B inputs (running at 0.9V swing, Vdd_mid-referenced)
    output wire [DATA_W-1:0] tier_b_data,        // level-shifted data to cluster-B
    output wire              tier_b_valid,

    // Mid-rail balance control
    output reg               charge_bal_pulse,   // pulse to decap refresh
    output wire              vstack_en           // 1 = stacking active (scan-chain gate)
);

    // Level-shifter wrapper: tier_a → tier_b (HV→LV, 1.8V→0.9V referenced)
    // (* SYNTHESIS_CELL = "sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_1" *)
    assign tier_b_data  = tier_a_data;
    assign tier_b_valid = tier_a_valid;

    // Charge-balance pulse: periodic refresh of mid-rail decoupling caps
    // Fires every 256 cycles to prevent droop
    reg [7:0] bal_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bal_cnt         <= 8'h00;
            charge_bal_pulse <= 1'b0;
        end else begin
            if (bal_cnt == 8'hFF) begin
                bal_cnt          <= 8'h00;
                charge_bal_pulse <= 1'b1;
            end else begin
                bal_cnt          <= bal_cnt + 8'h01;
                charge_bal_pulse <= 1'b0;
            end
        end
    end

    // vstack_en: always enabled in this RTL model; gated by scan-chain in silicon
    assign vstack_en = 1'b1;

endmodule
`default_nettype wire
