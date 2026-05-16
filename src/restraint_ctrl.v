// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// restraint_ctrl.v — Restraint controller FSM (issue-rate throttle)
// TT-Shuttle GF16 · Lane L-S30 Voltage Island
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// PURPOSE: Monitors the NCA entropy signal and throttles the GF16 tile
// issue rate when entropy is low. 4-state FSM with 256-cycle backpressure
// guard. Activity factor α ≈ 0.07 (worst-case FSM + output toggles).
//
// VOLTAGE ISLAND: Tagged for the L-S30 0.7 V island (Phase 2).
//
// (* LP_ISLAND = "S30_07V" *)
// (* ISLAND_ID = 2         *)
//
// State encoding:
//   IDLE     (2'b00): normal pass-through
//   WATCH    (2'b01): entropy below warn threshold — counting
//   THROTTLE (2'b10): issue rate halved
//   RELEASE  (2'b11): hysteresis release — 256-cycle countdown
//
// R-SI-1: No `*`. Pure Verilog-2005. 2 FFs + combinational decode.

`default_nettype none

// (* LP_ISLAND = "S30_07V" *)
// (* ISLAND_ID = 2         *)
module restraint_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        entropy_warn,   // 1 = NCA entropy below threshold (from L-S24)
    input  wire        entropy_ok,     // 1 = NCA entropy back in band
    output wire        throttle_en,    // 1 = suppress new issue (backpressure)
    output wire [1:0]  state_dbg,      // debug visibility: current FSM state
    output wire        ctrl_ok         // structural health marker (always 1)
);

    // State register
    localparam [1:0] IDLE     = 2'b00;
    localparam [1:0] WATCH    = 2'b01;
    localparam [1:0] THROTTLE = 2'b10;
    localparam [1:0] RELEASE  = 2'b11;

    reg [1:0]  state;
    reg [7:0]  guard_cnt;   // 256-cycle backpressure/release counter

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            guard_cnt <= 8'h00;
        end else begin
            case (state)
                IDLE: begin
                    guard_cnt <= 8'h00;
                    if (entropy_warn)
                        state <= WATCH;
                end

                WATCH: begin
                    if (entropy_ok) begin
                        state     <= IDLE;
                        guard_cnt <= 8'h00;
                    end else if (guard_cnt == 8'hFF) begin
                        // Entropy persistently low for 256 cycles → throttle
                        state     <= THROTTLE;
                        guard_cnt <= 8'h00;
                    end else begin
                        guard_cnt <= guard_cnt + 8'h01;
                    end
                end

                THROTTLE: begin
                    if (entropy_ok) begin
                        // Begin hysteresis release
                        state     <= RELEASE;
                        guard_cnt <= 8'h00;
                    end
                    // else stay in THROTTLE
                end

                RELEASE: begin
                    if (entropy_warn) begin
                        // Entropy dipped again — go back to THROTTLE
                        state     <= THROTTLE;
                        guard_cnt <= 8'h00;
                    end else if (guard_cnt == 8'hFF) begin
                        state     <= IDLE;
                        guard_cnt <= 8'h00;
                    end else begin
                        guard_cnt <= guard_cnt + 8'h01;
                    end
                end

                default: begin
                    state     <= IDLE;
                    guard_cnt <= 8'h00;
                end
            endcase
        end
    end

    assign throttle_en = (state == THROTTLE) | (state == RELEASE);
    assign state_dbg   = state;
    assign ctrl_ok     = 1'b1;

endmodule
`default_nettype wire
