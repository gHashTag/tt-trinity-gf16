// SPDX-License-Identifier: Apache-2.0
// adaptive_strobe_fsm.v — L-S25 Adaptive Strobe FSM
// TRI-1 v2 · Wave-7b · PhD Ch.13/S13
//
// 4-state FSM: IDLE → ARM → STROBE → COOLDOWN
// Strobe period adapts to traffic load using Lucas numbers:
//   L_5 = 11 (light traffic / idle)
//   L_6 = 18 (medium traffic)
//   L_7 = 29 (heavy traffic / busy)
//
// φ-weighted hysteresis via phi_weight[3:0] (Q0.4 ≈ 0..1 range)
// controls how many cycles of stable traffic state trigger a period change.
//
// Outputs:
//   strobe_en   — 1-cycle pulse coinciding with STROBE state entry
//   state_dbg   — current FSM state [1:0]
//
// Style: registered outputs, async active-low reset, no DSP inference.
`default_nettype none

module adaptive_strobe_fsm (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       traffic_busy,
    input  wire [3:0] phi_weight,    // Q0.4 hysteresis tuning (0=fast, 15=slow)
    output reg        strobe_en,
    output reg  [1:0] state_dbg
);

    // FSM state encoding
    localparam [1:0]
        S_IDLE     = 2'b00,
        S_ARM      = 2'b01,
        S_STROBE   = 2'b10,
        S_COOLDOWN = 2'b11;

    // Lucas period constants
    localparam [5:0] LUCAS_L5 = 6'd11;
    localparam [5:0] LUCAS_L6 = 6'd18;
    localparam [5:0] LUCAS_L7 = 6'd29;

    // Current target period register (holds one of L5/L6/L7)
    reg [5:0] period_r;       // active strobe period
    reg [5:0] cnt_r;          // free-running counter within period
    reg [1:0] state_r;        // FSM state

    // Traffic hysteresis counters
    // hyst_cnt saturates at 5 (or phi_weight-scaled) before switching
    reg [4:0] busy_cnt_r;     // consecutive busy cycles
    reg [4:0] idle_cnt_r;     // consecutive idle cycles

    // φ-scaled threshold: base 5, add upper bits of phi_weight
    // phi_weight[3:2] → 0..3 extra cycles, giving threshold range 5..8
    wire [4:0] hyst_thresh = 5'd5 + {3'd0, phi_weight[3:2]};

    // Next-state logic (combinational)
    reg [1:0] state_next;
    reg [5:0] period_next;

    always @(*) begin
        state_next  = state_r;
        period_next = period_r;

        case (state_r)
            S_IDLE: begin
                // Transition to ARM immediately (IDLE is a 1-cycle gateway)
                state_next = S_ARM;
            end
            S_ARM: begin
                // Wait until counter reaches period
                if (cnt_r >= period_r - 6'd1)
                    state_next = S_STROBE;
            end
            S_STROBE: begin
                // Single-cycle strobe pulse, then go to COOLDOWN
                state_next = S_COOLDOWN;
            end
            S_COOLDOWN: begin
                // Brief 2-cycle cooldown then back to ARM
                if (cnt_r >= 6'd1)
                    state_next = S_ARM;
            end
            default: state_next = S_IDLE;
        endcase

        // Period adaptation: evaluate on every cycle
        if (busy_cnt_r >= hyst_thresh)
            period_next = LUCAS_L7;
        else if (idle_cnt_r >= hyst_thresh)
            period_next = LUCAS_L5;
        else
            period_next = LUCAS_L6;
    end

    // Sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r    <= S_IDLE;
            cnt_r      <= 6'd0;
            period_r   <= LUCAS_L5;
            strobe_en  <= 1'b0;
            state_dbg  <= S_IDLE;
            busy_cnt_r <= 5'd0;
            idle_cnt_r <= 5'd0;
        end else begin
            // Update FSM state
            state_r   <= state_next;
            period_r  <= period_next;
            state_dbg <= state_next;

            // strobe_en pulses for exactly 1 cycle when entering STROBE
            strobe_en <= (state_next == S_STROBE) ? 1'b1 : 1'b0;

            // Counter management
            case (state_r)
                S_IDLE: begin
                    cnt_r <= 6'd0;
                end
                S_ARM: begin
                    if (cnt_r >= period_r - 6'd1)
                        cnt_r <= 6'd0;
                    else
                        cnt_r <= cnt_r + 6'd1;
                end
                S_STROBE: begin
                    cnt_r <= 6'd0;
                end
                S_COOLDOWN: begin
                    if (cnt_r >= 6'd1)
                        cnt_r <= 6'd0;
                    else
                        cnt_r <= cnt_r + 6'd1;
                end
                default: cnt_r <= 6'd0;
            endcase

            // Hysteresis counters: saturating at 31
            if (traffic_busy) begin
                busy_cnt_r <= (busy_cnt_r == 5'd31) ? 5'd31 : busy_cnt_r + 5'd1;
                idle_cnt_r <= 5'd0;
            end else begin
                idle_cnt_r <= (idle_cnt_r == 5'd31) ? 5'd31 : idle_cnt_r + 5'd1;
                busy_cnt_r <= 5'd0;
            end
        end
    end

endmodule
`default_nettype wire
