// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// v7_leakage_mon_S27.v — S-27 Leakage monitor (simulation model)
// TT-Shuttle Squeeze v7 · W15-TT-D Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// G-27 FALSIFICATION: host-driven DVFS demo cycles clk_in 25 → 50 → 125 MHz
//                     internal with ≤ 1 µs settling; else DVFS disabled.
//
// S-27 per-app DVFS controller: this module is the on-chip side of the DVFS
// loop. It tracks the toggle-activity rate of registered PE outputs as a proxy
// for dynamic power consumption. When toggle rate is low (< LO_THRESH), it
// signals the host to reduce clk_in (saving 75% dynamic power at 0.5× freq).
//
// Activity metric: count toggle events in a TIME_WIN-cycle window.
// Toggle rate = toggles / (N_BITS * TIME_WIN) — reported as 8-bit saturating value.

`default_nettype none

module v7_leakage_mon_S27 #(
    parameter N_BITS    = 8,    // width of monitored signal
    parameter TIME_WIN  = 64,   // measurement window in cycles
    parameter LO_THRESH = 4,    // low-activity threshold → suggest freq scale-down
    parameter HI_THRESH = 48    // high-activity threshold → suggest freq scale-up
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [N_BITS-1:0] monitor_bus,    // probe point: sampled PE output bus
    output reg  [7:0]        activity_rate,  // toggle rate (8-bit, saturating)
    output wire              suggest_down,   // 1 → suggest host to lower clk_in
    output wire              suggest_up      // 1 → suggest host to raise clk_in
);

    reg [N_BITS-1:0] prev_bus;
    reg [15:0]       toggle_cnt;
    reg [15:0]       cycle_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_bus      <= {N_BITS{1'b0}};
            toggle_cnt    <= 16'h0000;
            cycle_cnt     <= 16'h0000;
            activity_rate <= 8'h00;
        end else begin
            prev_bus <= monitor_bus;

            // Count bit toggles this cycle
            begin : count_toggles
                integer b;
                reg [7:0] xors;
                xors = {N_BITS{1'b0}};
                for (b = 0; b < N_BITS; b = b + 1)
                    xors[b] = monitor_bus[b] ^ prev_bus[b];
                // Popcount — no * operator; use add-reduction
                toggle_cnt <= toggle_cnt
                    + {{15{1'b0}}, xors[0]}
                    + {{15{1'b0}}, xors[1]}
                    + {{15{1'b0}}, xors[2]}
                    + {{15{1'b0}}, xors[3]}
                    + {{15{1'b0}}, xors[4]}
                    + {{15{1'b0}}, xors[5]}
                    + {{15{1'b0}}, xors[6]}
                    + {{15{1'b0}}, xors[7]};
            end

            if (cycle_cnt >= (TIME_WIN[15:0] - 16'd1)) begin
                cycle_cnt <= 16'h0000;
                // Saturate to 8 bits
                activity_rate <= (toggle_cnt[15:8] != 8'h00) ? 8'hFF : toggle_cnt[7:0];
                toggle_cnt    <= 16'h0000;
            end else begin
                cycle_cnt <= cycle_cnt + 16'h0001;
            end
        end
    end

    assign suggest_down = (activity_rate <= LO_THRESH[7:0]);
    assign suggest_up   = (activity_rate >= HI_THRESH[7:0]);

endmodule
`default_nettype wire
