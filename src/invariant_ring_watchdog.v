// SPDX-License-Identifier: Apache-2.0
// invariant_ring_watchdog.v — L-S30 Invariant Ring Watchdog
// TRI-1 v2 · Wave-7b · PhD Ch.14/S14
//
// Parallel watchdog for the top-7 PhD Coq-proven invariants (INV-1..INV-7).
// Each input is 1-bit: 0=OK, 1=violation.
//
// Input sources:
//   inv1_phi_anchor_fail    — phi_anchor_post
//   inv2_lucas_recurrence_fail — lucas_rom
//   inv3_cassini_fail       — cassini_post.cassini_ok inverted
//   inv4_nca_entropy_fail   — nca_entropy_monitor.entropy_violation
//   inv5_bpb_nonneg_fail    — bpb_lower_bound_guard.fault_code[1]
//   inv6_plrm_mutex_fail    — plrm_counter.plrm_error
//   inv7_seed_forbidden_fail — strobe_seed_guard.seed_forbidden
//
// Outputs:
//   invariant_violation     — registered OR of all sticky bits
//   violation_vec[6:0]      — sticky per-invariant bits (only reset clears)
//   first_violation_id[2:0] — lowest INV-N that tripped first (latched)
//   total_violations[15:0]  — saturating count of ALL violation pulse-cycles
//
// Style: registered outputs, async active-low reset, no DSP inference.
`default_nettype none

module invariant_ring_watchdog (
    input  wire        clk,
    input  wire        rst_n,

    // Invariant violation inputs (active-high)
    input  wire        inv1_phi_anchor_fail,
    input  wire        inv2_lucas_recurrence_fail,
    input  wire        inv3_cassini_fail,
    input  wire        inv4_nca_entropy_fail,
    input  wire        inv5_bpb_nonneg_fail,
    input  wire        inv6_plrm_mutex_fail,
    input  wire        inv7_seed_forbidden_fail,

    // Outputs
    output reg         invariant_violation,
    output reg  [6:0]  violation_vec,
    output reg  [2:0]  first_violation_id,
    output reg  [15:0] total_violations
);

    // Bundle all inputs for convenience
    // Index mapping: [0]=INV-1 .. [6]=INV-7
    wire [6:0] inv_in = {
        inv7_seed_forbidden_fail,   // [6] -> INV-7
        inv6_plrm_mutex_fail,       // [5] -> INV-6
        inv5_bpb_nonneg_fail,       // [4] -> INV-5
        inv4_nca_entropy_fail,      // [3] -> INV-4
        inv3_cassini_fail,          // [2] -> INV-3
        inv2_lucas_recurrence_fail, // [1] -> INV-2
        inv1_phi_anchor_fail        // [0] -> INV-1
    };

    // New fires this cycle: any asserted input (used for first_id priority)
    wire [6:0] any_fires = inv_in;

    // Count asserted inputs this cycle (popcount, max 7)
    // Simple adder tree — no DSP inference
    wire [3:0] pop_this = {3'd0, inv_in[0]} + {3'd0, inv_in[1]}
                        + {3'd0, inv_in[2]} + {3'd0, inv_in[3]}
                        + {3'd0, inv_in[4]} + {3'd0, inv_in[5]}
                        + {3'd0, inv_in[6]};

    // Priority encoder: find lowest-index INV asserted this cycle (1-based ID)
    reg [2:0] cur_fire_id;
    always @(*) begin
        if      (inv_in[0]) cur_fire_id = 3'd1;
        else if (inv_in[1]) cur_fire_id = 3'd2;
        else if (inv_in[2]) cur_fire_id = 3'd3;
        else if (inv_in[3]) cur_fire_id = 3'd4;
        else if (inv_in[4]) cur_fire_id = 3'd5;
        else if (inv_in[5]) cur_fire_id = 3'd6;
        else if (inv_in[6]) cur_fire_id = 3'd7;
        else                cur_fire_id = 3'd0;
    end

    // Saturating add: 16-bit + 4-bit, clamp at 0xFFFF
    wire [16:0] sat_add   = {1'b0, total_violations} + {13'd0, pop_this};
    wire [15:0] sat_result = sat_add[16] ? 16'hFFFF : sat_add[15:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            violation_vec       <= 7'd0;
            first_violation_id  <= 3'd0;
            total_violations    <= 16'd0;
            invariant_violation <= 1'b0;
        end else begin
            // Sticky accumulation of per-invariant bits
            violation_vec <= violation_vec | inv_in;

            // Saturating counter: count EVERY violation pulse (re-fires included)
            if (|inv_in)
                total_violations <= sat_result;

            // Latch first-violation ID — set once, never overwritten
            if (first_violation_id == 3'd0 && |inv_in)
                first_violation_id <= cur_fire_id;

            // invariant_violation: registered OR of accumulated sticky vec
            invariant_violation <= |(violation_vec | inv_in);
        end
    end

endmodule
`default_nettype wire
