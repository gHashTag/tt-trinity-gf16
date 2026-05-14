// SPDX-License-Identifier: Apache-2.0
// power_gate_fsm.v — L-S42: 4-domain power-gate FSM for 2×2 GF16 mesh
// Author: Dmitrii Vasilev <admin@t27.ai>
// Project: TRI-1 Mid — Trinity GF16 SoC (tt-trinity-gf16)
//
// Architecture:
//   4 independent power domains: PD_NW(0), PD_NE(1), PD_SW(2), PD_SE(3)
//   5 states per domain: OFF(0) → WAKE(1) → ACTIVE(2) → SLEEP_REQ(3) → OFF(0)
//   Central round-robin token arbiter: at most 1 domain transitions per cycle.
//
// State encoding (3-bit one-hot subsets avoided; 3-bit binary used):
//   ST_OFF       = 3'd0
//   ST_WAKE      = 3'd1
//   ST_ACTIVE    = 3'd2
//   ST_SLEEP_REQ = 3'd3
//   ST_SLEEPING  = 3'd4  (transient on way back to OFF)
//
// Anchor: φ² + φ⁻² = 3  (4 domains, 4 tiles)
//
// Pipeline FFs tagged (* keep *)(* no_retiming *) per R-SI-1.
// No * operator / No DSP usage (R-SI-1).

`default_nettype none
`timescale 1ns/1ps

module power_gate_fsm (
    input  wire        clk,
    input  wire        rst_n,

    // Per-domain control inputs
    input  wire [3:0]  wake_req,    // wake_req[i] = request domain i to wake up
    input  wire [3:0]  sleep_req,   // sleep_req[i] = request domain i to sleep

    // Per-domain power control outputs
    output wire [3:0]  pwr_en,      // 1 = power rail enabled
    output wire [3:0]  clk_en,      // 1 = clock enabled
    output wire [3:0]  iso_en,      // 1 = isolation cells active (signals isolated)

    // Status outputs
    output wire [11:0] domain_state, // 3 bits per domain [3:0], state encoding
    output wire [3:0]  arb_token    // one-hot grant token (debug/monitor)
);

    // =========================================================
    // State encoding
    // =========================================================
    localparam [2:0]
        ST_OFF       = 3'd0,   // power off, clock off, isolated
        ST_WAKE      = 3'd1,   // powering up, isolation still active
        ST_ACTIVE    = 3'd2,   // fully running, no isolation
        ST_SLEEP_REQ = 3'd3,   // isolation re-asserted, draining
        ST_SLEEPING  = 3'd4;   // clock off, power off in next cycle

    // =========================================================
    // Per-domain state registers (pipeline FFs)
    // =========================================================
    (* keep *) (* no_retiming *) reg [2:0] state_r [0:3];
    (* keep *) (* no_retiming *) reg [2:0] state_next [0:3];

    // =========================================================
    // Round-robin arbiter token (one-hot, 4-bit)
    // Invariant: popcount(token_r) <= 1 at all times
    // =========================================================
    (* keep *) (* no_retiming *) reg [3:0] token_r;  // one-hot grant token
    (* keep *) (* no_retiming *) reg [3:0] rr_ptr_r; // round-robin pointer (one-hot)

    // =========================================================
    // Transition request: domain wants to change state
    // =========================================================
    wire [3:0] trans_req;
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : gen_trans_req
            assign trans_req[gi] =
                ((state_r[gi] == ST_OFF)       && wake_req[gi])  ||
                ((state_r[gi] == ST_WAKE)       && 1'b1)          ||  // auto-advance WAKE→ACTIVE
                ((state_r[gi] == ST_ACTIVE)     && sleep_req[gi]) ||
                ((state_r[gi] == ST_SLEEP_REQ)  && 1'b1)          ||  // auto-advance SLEEP_REQ→SLEEPING
                ((state_r[gi] == ST_SLEEPING)   && 1'b1);             // auto-advance SLEEPING→OFF
        end
    endgenerate

    // =========================================================
    // Central round-robin arbiter
    // Grants exactly 1 token to the next requesting domain
    // using a rotating priority pointer.
    // =========================================================
    // Priority encoder with round-robin: scan from rr_ptr_r onward
    reg [3:0] grant_next;

    always @(*) begin
        grant_next = 4'b0000;
        // Check each slot in round-robin order starting from rr_ptr_r
        // rr_ptr_r is one-hot; we check [ptr], [ptr+1], [ptr+2], [ptr+3]
        if (rr_ptr_r[0]) begin
            if      (trans_req[0]) grant_next = 4'b0001;
            else if (trans_req[1]) grant_next = 4'b0010;
            else if (trans_req[2]) grant_next = 4'b0100;
            else if (trans_req[3]) grant_next = 4'b1000;
        end else if (rr_ptr_r[1]) begin
            if      (trans_req[1]) grant_next = 4'b0010;
            else if (trans_req[2]) grant_next = 4'b0100;
            else if (trans_req[3]) grant_next = 4'b1000;
            else if (trans_req[0]) grant_next = 4'b0001;
        end else if (rr_ptr_r[2]) begin
            if      (trans_req[2]) grant_next = 4'b0100;
            else if (trans_req[3]) grant_next = 4'b1000;
            else if (trans_req[0]) grant_next = 4'b0001;
            else if (trans_req[1]) grant_next = 4'b0010;
        end else begin // rr_ptr_r[3]
            if      (trans_req[3]) grant_next = 4'b1000;
            else if (trans_req[0]) grant_next = 4'b0001;
            else if (trans_req[1]) grant_next = 4'b0010;
            else if (trans_req[2]) grant_next = 4'b0100;
        end
    end

    // =========================================================
    // Next state logic for each domain
    // A domain may only transition if it holds the token.
    // =========================================================
    integer k;
    always @(*) begin
        for (k = 0; k < 4; k = k + 1) begin
            state_next[k] = state_r[k]; // default: hold
            if (grant_next[k]) begin
                case (state_r[k])
                    ST_OFF:       if (wake_req[k])   state_next[k] = ST_WAKE;
                    ST_WAKE:                          state_next[k] = ST_ACTIVE;
                    ST_ACTIVE:    if (sleep_req[k])  state_next[k] = ST_SLEEP_REQ;
                    ST_SLEEP_REQ:                     state_next[k] = ST_SLEEPING;
                    ST_SLEEPING:                      state_next[k] = ST_OFF;
                    default:                          state_next[k] = ST_OFF;
                endcase
            end
        end
    end

    // =========================================================
    // Sequential update
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r[0] <= ST_OFF;
            state_r[1] <= ST_OFF;
            state_r[2] <= ST_OFF;
            state_r[3] <= ST_OFF;
            token_r    <= 4'b0000;
            rr_ptr_r   <= 4'b0001; // start priority at domain 0
        end else begin
            state_r[0] <= state_next[0];
            state_r[1] <= state_next[1];
            state_r[2] <= state_next[2];
            state_r[3] <= state_next[3];
            token_r    <= grant_next;
            // Advance round-robin pointer to domain AFTER the last granted
            if      (grant_next[0]) rr_ptr_r <= 4'b0010;
            else if (grant_next[1]) rr_ptr_r <= 4'b0100;
            else if (grant_next[2]) rr_ptr_r <= 4'b1000;
            else if (grant_next[3]) rr_ptr_r <= 4'b0001;
            // if no grant, pointer stays
        end
    end

    // =========================================================
    // Output decode
    // pwr_en  = 1 when domain is NOT off (WAKE, ACTIVE, SLEEP_REQ, SLEEPING)
    // clk_en  = 1 when domain is ACTIVE only
    // iso_en  = 1 when NOT in ACTIVE state (isolate when off/transitioning)
    // =========================================================
    genvar oi;
    generate
        for (oi = 0; oi < 4; oi = oi + 1) begin : gen_outputs
            assign pwr_en[oi] = (state_r[oi] == ST_WAKE)       ||
                                 (state_r[oi] == ST_ACTIVE)     ||
                                 (state_r[oi] == ST_SLEEP_REQ)  ||
                                 (state_r[oi] == ST_SLEEPING);
            assign clk_en[oi] = (state_r[oi] == ST_ACTIVE);
            assign iso_en[oi] = (state_r[oi] != ST_ACTIVE);
        end
    endgenerate

    // =========================================================
    // Status outputs
    // =========================================================
    assign domain_state = {state_r[3], state_r[2], state_r[1], state_r[0]};
    assign arb_token    = token_r;

endmodule
`default_nettype wire
