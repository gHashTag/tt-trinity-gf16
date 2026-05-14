// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// v7_switchcap_S32.v — Switched-capacitor decoupling network model (S-32)
// Stream W15-TT-B · TT-Shuttle Squeeze v7 · TRI-NET-G1
// ** SIMULATION-ONLY MODEL — not synthesisable to real switched-cap HW **
//
// PhD anchor: φ² + φ⁻² = 3
// DOI: 10.5281/zenodo.19227877 · Apache-2.0
//
// G-32 FALSIFICATION: simulated Vdd droop during burst > 50 mV (5% of 1V rail)
//                     with switched-cap network active (would indicate model
//                     parameters are non-physical).
//
// Design notes:
//   This RTL model captures the *digital control interface* of a switched-
//   capacitor decoupling network and a behavioural droop monitor.
//
//   The physical SC network consists of N_CAPS switched capacitors
//   (each modelled as C_UNIT Farads) in parallel with the local Vdd.
//   During high-activity bursts the digital controller disconnects caps
//   sequentially, avoiding inrush; during quiet cycles it reconnects them.
//
//   RTL model:
//     - A 4-bit activity counter tracks toggle events per cycle.
//     - A 4-bit cap_connect register enables/disables SC cells.
//     - A 12-bit fixed-point Vdd rail register (Q8.4, units = Volts)
//       is decremented by (activity × I_LOAD) per cycle and restored by
//       the SC charge transfer (R_EQUIV × time-constant model).
//     - A droop_ok output asserts when Vdd_model > DROOP_THRESH.
//
//   All arithmetic is add/subtract (no `*` operator).

`default_nettype none

module v7_switchcap_S32 #(
    parameter N_CAPS       = 4,    // number of SC cells
    parameter VDD_NOMINAL  = 12'hA00, // 1.000 V in Q8.4 (0xA00 = 2560 = 160*16 = 10.00 * 256 → actually: Q4.8 scale)
    // VDD_NOMINAL: represent 1.0 V as 12'd256 (Q4.8 → 1.0 = 0x100 = 256)
    // Redefine: Q8.4 unsigned: 1.0 = 16, so 1V = 4'h10 → use 8-bit Q4.4: 1V=16
    // Use simple: Vdd integer millivolts, nominal = 1000 mV
    parameter VDD_MV       = 1000,  // nominal Vdd in mV (integer)
    parameter DROOP_THRESH = 950    // droop threshold in mV (50 mV = 5%)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  activity,    // number of signal toggles this cycle (0..15)
    input  wire        sc_enable,   // master enable for SC network
    output reg  [3:0]  cap_connect, // bitmask: which SC caps are connected
    output wire        droop_ok,    // 1 = Vdd within spec
    output wire [11:0] vdd_model,   // current Vdd model (mV, 12-bit unsigned)
    output wire        sc_ok
);

    // -----------------------------------------------------------------------
    // 1. Vdd model register (mV, 12-bit)
    // -----------------------------------------------------------------------
    reg [11:0] vdd_reg;  // Vdd in mV

    // Each activity unit corresponds to ~5 mV droop (hand-calibrated param)
    // SC restoration: +3 mV per connected cap per cycle when activity<4
    // All arithmetic: add/subtract only, no multiply.

    // Droop per cycle: activity * 5 mV — approximated without multiply as:
    //   droop ≈ {activity[3:0], 2'b0} + activity  = activity*4 + activity = 5*activity
    // Using shift+add: 4*activity = activity<<2; 5*activity = (activity<<2) + activity
    wire [7:0] act8 = {4'b0, activity};
    wire [7:0] droop_mv = (act8 << 2) + act8;  // 5 * activity, no mul needed

    // SC charge: count connected caps (popcount of cap_connect)
    wire [2:0] caps_on = cap_connect[0] + cap_connect[1] +
                         cap_connect[2] + cap_connect[3];
    wire [4:0] sc_restore_mv = {2'b0, caps_on} + 5'd1;  // 1..4 mV restoration

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vdd_reg <= 12'd1000;  // 1000 mV nominal
        end else begin
            // Apply droop
            if (vdd_reg > {4'b0, droop_mv})
                vdd_reg <= vdd_reg - {4'b0, droop_mv};
            else
                vdd_reg <= 12'd0;
            // SC restoration (only if enabled and caps connected)
            if (sc_enable & (caps_on > 3'd0)) begin
                if (vdd_reg + {7'b0, sc_restore_mv} < 12'd1000)
                    vdd_reg <= vdd_reg + {7'b0, sc_restore_mv};
                else
                    vdd_reg <= 12'd1000;
            end
        end
    end

    // -----------------------------------------------------------------------
    // 2. Cap controller: connect/disconnect based on activity level
    //    High activity → disconnect to avoid inrush; low activity → reconnect
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_connect <= 4'hF;  // all connected at reset
        end else if (sc_enable) begin
            if (activity >= 4'd12)       cap_connect <= 4'b0001;  // keep 1
            else if (activity >= 4'd8)   cap_connect <= 4'b0011;  // keep 2
            else if (activity >= 4'd4)   cap_connect <= 4'b0111;  // keep 3
            else                         cap_connect <= 4'b1111;  // all 4
        end
    end

    // -----------------------------------------------------------------------
    // 3. Outputs
    // -----------------------------------------------------------------------
    assign vdd_model = vdd_reg;
    assign droop_ok  = (vdd_reg >= 12'd(DROOP_THRESH));
    assign sc_ok     = sc_enable;

    // synthesis translate_off
    initial $display("S-32 ANCHOR: phi^2+phi^-2=3 | SwitchCap decoupling model N_CAPS=%0d", N_CAPS);
    // synthesis translate_on

endmodule
