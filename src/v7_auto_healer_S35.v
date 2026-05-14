// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 TRI-NET-G1 / TT-Shuttle Squeeze v7
//
// v7_auto_healer_S35.v — Auto-Healer FSM with fault injection, bypass mux, 40 ns MTTR
// Stream S-35 · Wave W15-TT-F · Anchor φ²+φ⁻²=3
//
// G-35 FALSIFICATION: inject permanent stuck-at fault on PE[3] → recovery in
//                     ≤ 120 ns measured at output port → else scope reduced.
//
// Reference: Auto-Healer ICS 2025 (https://hpcrl.github.io/ICS2025-webpage/)
//
// This module implements a "self-healing model" — no claims of trusted execution.
//
// FSM states: NORMAL → FAULT_DETECT → BYPASS → RECOVER → NORMAL
//
// Timing:
//   Clock assumed 1 GHz (1 ns/cycle).
//   MTTR counter = 40 cycles → 40 ns MTTR for transient faults.
//   Permanent fault recovery: 3 × 40 = 120 cycles → 120 ns.
//
// Fault injection port (for testbench / G-35 gate):
//   fault_inject[N] forces PE[N] output stuck-at-0.
//
// PE bypass mux:
//   When a PE is flagged faulty, its output is replaced by the
//   redundant spare PE output (spare_pe_out).
//
// No wildcard (*) in synth RTL.

`default_nettype none

module v7_auto_healer_S35 #(
    parameter NUM_PE      = 4,            // number of PEs watched
    parameter DATA_W      = 8,            // PE output width
    parameter MTTR_CYCLES = 40,           // cycles to MTTR @ 1 GHz = 40 ns
    parameter MTTR_CNT_W  = 6            // ceil(log2(MTTR_CYCLES+1)) = 6
) (
    input  wire                       clk,
    input  wire                       rst_n,

    // ---- Live PE outputs (from main compute path) ----
    input  wire [(NUM_PE*DATA_W)-1:0] pe_out,         // normal PE outputs

    // ---- Spare/redundant PE output ----
    input  wire [DATA_W-1:0]          spare_pe_out,   // hot spare PE result

    // ---- Error inputs (from TMR voter or BIST scan) ----
    input  wire [NUM_PE-1:0]          pe_err,         // per-PE error flag

    // ---- Fault injection (testbench / G-35 gate) ----
    // Setting fault_inject[i]=1 forces pe_err[i] permanently for testing.
    input  wire [NUM_PE-1:0]          fault_inject,

    // ---- Healer outputs ----
    output reg  [(NUM_PE*DATA_W)-1:0] healed_out,     // muxed safe output
    output reg  [NUM_PE-1:0]          bypass_active,  // which PEs are bypassed
    output wire                       healing_active, // FSM not in NORMAL

    // ---- Status / telemetry ----
    output reg  [3:0]                 fsm_state_out,  // current FSM state (scan-chain)
    output reg  [MTTR_CNT_W-1:0]     mttr_counter,   // countdown to recovery
    output reg                        fault_permanent  // fault persisted > 3×MTTR
);

    // ================================================================
    // FSM state encoding
    // ================================================================
    localparam [2:0]
        ST_NORMAL       = 3'd0,
        ST_FAULT_DETECT = 3'd1,
        ST_BYPASS       = 3'd2,
        ST_RECOVER      = 3'd3,
        ST_PERMANENT    = 3'd4;   // extended recovery for permanent faults

    reg [2:0] state;
    reg [2:0] state_next;

    assign healing_active = (state != ST_NORMAL);

    // Combined error: real PE error OR injected fault
    wire [NUM_PE-1:0] err_combined;
    assign err_combined = pe_err | fault_inject;

    wire any_err;
    assign any_err = |err_combined;

    // Latch which PE is faulted (first one detected)
    reg [NUM_PE-1:0] faulted_pe;

    // Recovery attempt counter (counts retries before declaring permanent)
    reg [1:0] retry_count;

    // ================================================================
    // MTTR countdown counter
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mttr_counter <= {MTTR_CNT_W{1'b0}};
        end else begin
            case (state)
                ST_BYPASS: begin
                    // Start countdown when bypass begins
                    if (state_next == ST_BYPASS)
                        mttr_counter <= (mttr_counter == {MTTR_CNT_W{1'b0}})
                                        ? MTTR_CYCLES[MTTR_CNT_W-1:0]
                                        : mttr_counter - 1'b1;
                end
                ST_RECOVER: begin
                    // Wind down to zero, then check
                    if (mttr_counter != {MTTR_CNT_W{1'b0}})
                        mttr_counter <= mttr_counter - 1'b1;
                end
                ST_PERMANENT: begin
                    mttr_counter <= MTTR_CYCLES[MTTR_CNT_W-1:0];
                end
                default: mttr_counter <= {MTTR_CNT_W{1'b0}};
            endcase
        end
    end

    // ================================================================
    // FSM next-state logic
    // ================================================================
    always @(*) begin
        state_next = state;
        case (state)
            ST_NORMAL: begin
                if (any_err)
                    state_next = ST_FAULT_DETECT;
            end

            ST_FAULT_DETECT: begin
                // One-cycle detection → immediately bypass
                state_next = ST_BYPASS;
            end

            ST_BYPASS: begin
                // Wait MTTR cycles then attempt recovery
                if (mttr_counter == {{(MTTR_CNT_W-1){1'b0}}, 1'b1})
                    state_next = ST_RECOVER;
            end

            ST_RECOVER: begin
                if (!any_err) begin
                    // Fault gone — return to normal
                    state_next = ST_NORMAL;
                end else if (retry_count >= 2'd2) begin
                    // Three attempts, still failing → permanent
                    state_next = ST_PERMANENT;
                end else begin
                    // Try again
                    state_next = ST_BYPASS;
                end
            end

            ST_PERMANENT: begin
                // Permanent fault: hold bypass indefinitely, assert fault_permanent
                // Only exit if fault_inject is cleared AND no PE err
                if (!any_err)
                    state_next = ST_NORMAL;
            end

            default: state_next = ST_NORMAL;
        endcase
    end

    // ================================================================
    // FSM state register + retry counter
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_NORMAL;
            faulted_pe    <= {NUM_PE{1'b0}};
            retry_count   <= 2'd0;
            fault_permanent <= 1'b0;
        end else begin
            state <= state_next;

            case (state)
                ST_NORMAL: begin
                    retry_count     <= 2'd0;
                    fault_permanent <= 1'b0;
                    if (any_err)
                        faulted_pe <= err_combined;
                end

                ST_FAULT_DETECT: begin
                    faulted_pe <= err_combined;
                end

                ST_RECOVER: begin
                    if (any_err && retry_count < 2'd3)
                        retry_count <= retry_count + 1'b1;
                end

                ST_PERMANENT: begin
                    fault_permanent <= 1'b1;
                end

                default: begin end
            endcase
        end
    end

    // ================================================================
    // Bypass mux: replace faulted PE output with spare
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            healed_out     <= {(NUM_PE*DATA_W){1'b0}};
            bypass_active  <= {NUM_PE{1'b0}};
            fsm_state_out  <= 4'd0;
        end else begin
            fsm_state_out <= {1'b0, state};

            // Determine which PEs are bypassed
            bypass_active <= ((state == ST_BYPASS)     ||
                              (state == ST_RECOVER)    ||
                              (state == ST_PERMANENT)  ||
                              (state == ST_FAULT_DETECT))
                             ? faulted_pe
                             : {NUM_PE{1'b0}};

            // PE 0 output mux
            healed_out[DATA_W-1:0] <=
                (bypass_active[0]) ? spare_pe_out : pe_out[DATA_W-1:0];

            // PE 1 output mux
            healed_out[(2*DATA_W)-1:DATA_W] <=
                (bypass_active[1]) ? spare_pe_out : pe_out[(2*DATA_W)-1:DATA_W];

            // PE 2 output mux
            healed_out[(3*DATA_W)-1:(2*DATA_W)] <=
                (bypass_active[2]) ? spare_pe_out : pe_out[(3*DATA_W)-1:(2*DATA_W)];

            // PE 3 output mux
            healed_out[(4*DATA_W)-1:(3*DATA_W)] <=
                (bypass_active[3]) ? spare_pe_out : pe_out[(4*DATA_W)-1:(3*DATA_W)];
        end
    end

endmodule
