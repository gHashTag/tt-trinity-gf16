// SPDX-License-Identifier: Apache-2.0
// v7_pe_mesh_2x2_S6.v — W15-TT-A: 4×(2×2) PE-mesh wrapper (S-6)
// TRI-NET-G1 / TT-Shuttle Squeeze v7  |  Anchor: phi^2 + phi^-2 = 3
//
// G-6 FALSIFICATION: all 4 trinity_mesh_2x2 sub-meshes accept and return a
//   COMPUTE packet within 32 clock cycles of issue; any sub-mesh that fails
//   to return a RESULT within 32 cycles is flagged by timeout_vec → test FAIL.
//
// S-6: 4×(2×2) PE-mesh — on-chip systolic wrapper.
//   This module instantiates 4 independent trinity_mesh_2x2 fabrics and
//   exposes a flat host injection/ejection interface with mesh-select routing.
//   Each sub-mesh contains 4 GF16 tiles (16 PEs total across all sub-meshes).
//
// Charter hard rules:
//   - No `*` (shift-add/XOR compute only; all multiplication lives in gf16_mul)
//   - On-chip 2×2 PE only; this IS the on-chip mesh (G1/G2 inter-node stays off-chip)
//   - No Linux, no USB-3 direct compute
//   - R5 honesty: counts below are projections
//
// Projection: 4 sub-meshes × 4 tiles × 4-lane dot4 @ 50 MHz = 3.2 GOPS (projection).
//
`default_nettype none

`include "trinity_packet.vh"

// Mesh-level packet extension: [33:32] = sub-mesh select, [31:0] = Trinity packet
// The host injects 34-bit words; top 2 bits select which trinity_mesh_2x2 to target.
// The ejection side demuxes similarly.

module v7_pe_mesh_2x2_S6 (
    input  wire         clk,
    input  wire         rst_n,

    // Host injection — 2-bit mesh_sel + standard Trinity packet
    input  wire [1:0]                   h_sel,          // which sub-mesh (0..3)
    input  wire [`TRN_PKT_W-1:0]        h_in_pkt,
    input  wire                         h_in_valid,
    output wire                         h_in_ready,

    // Host ejection — result packet from any sub-mesh (round-robin)
    output reg  [`TRN_PKT_W-1:0]        h_out_pkt,
    output reg                          h_out_valid,
    output reg  [1:0]                   h_out_sel,      // which sub-mesh returned
    input  wire                         h_out_ready,

    // Debug: tile-0 result from each sub-mesh
    output wire [15:0]  dbg_mesh0_tile0,
    output wire [15:0]  dbg_mesh1_tile0,
    output wire [15:0]  dbg_mesh2_tile0,
    output wire [15:0]  dbg_mesh3_tile0,

    // Watchdog: bit per sub-mesh asserted if a COMPUTE has not returned within
    // TIMEOUT_CYCLES (projection check, not silicon measured)
    output wire [3:0]   timeout_vec
);

    parameter TIMEOUT_CYCLES = 6'd32;  // G-6 falsification window

    // -----------------------------------------------------------------------
    // Per-sub-mesh wires
    // -----------------------------------------------------------------------
    wire [`TRN_PKT_W-1:0] m_in_pkt   [0:3];
    wire                  m_in_valid  [0:3];
    wire                  m_in_ready  [0:3];
    wire [`TRN_PKT_W-1:0] m_out_pkt  [0:3];
    wire                  m_out_valid [0:3];
    wire                  m_out_ready [0:3];

    // -----------------------------------------------------------------------
    // Injection mux: route host packet to selected sub-mesh
    // -----------------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_inj
            assign m_in_pkt[gi]   = h_in_pkt;
            assign m_in_valid[gi] = h_in_valid && (h_sel == gi[1:0]);
        end
    endgenerate

    // host_in_ready follows the targeted sub-mesh
    assign h_in_ready = (h_sel == 2'd0) ? m_in_ready[0] :
                        (h_sel == 2'd1) ? m_in_ready[1] :
                        (h_sel == 2'd2) ? m_in_ready[2] :
                                          m_in_ready[3];

    // -----------------------------------------------------------------------
    // 4 sub-mesh instances
    // -----------------------------------------------------------------------
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_mesh
            trinity_mesh_2x2 u_mesh (
                .clk             (clk),
                .rst_n           (rst_n),
                .host_in_pkt     (m_in_pkt[gi]),
                .host_in_valid   (m_in_valid[gi]),
                .host_in_ready   (m_in_ready[gi]),
                .host_out_pkt    (m_out_pkt[gi]),
                .host_out_valid  (m_out_valid[gi]),
                .host_out_ready  (m_out_ready[gi]),
                .dbg_tile0_result()   // tied off per-mesh; top-level uses named outputs
            );
        end
    endgenerate

    // Dedicated debug outputs for each sub-mesh tile-0
    // (re-instantiate separately to expose dbg_tile0_result per mesh)
    // NOTE: the generate-loop above ties dbg_tile0_result; separate
    //       convenience assignments use m_out_pkt for simplicity since
    //       detailed per-tile debug is not needed for the G-6 falsification gate.
    assign dbg_mesh0_tile0 = m_out_pkt[0][15:0];
    assign dbg_mesh1_tile0 = m_out_pkt[1][15:0];
    assign dbg_mesh2_tile0 = m_out_pkt[2][15:0];
    assign dbg_mesh3_tile0 = m_out_pkt[3][15:0];

    // -----------------------------------------------------------------------
    // Ejection: round-robin arbitration across 4 sub-meshes
    // -----------------------------------------------------------------------
    reg  [1:0] rr_ptr;

    wire [1:0] rr0 = rr_ptr;
    wire [1:0] rr1 = rr_ptr + 2'd1;
    wire [1:0] rr2 = rr_ptr + 2'd2;
    wire [1:0] rr3 = rr_ptr + 2'd3;

    reg  [1:0] sel;
    reg        sel_valid;

    always @(*) begin
        sel       = 2'd0;
        sel_valid = 1'b0;
        if      (m_out_valid[rr0]) begin sel = rr0; sel_valid = 1'b1; end
        else if (m_out_valid[rr1]) begin sel = rr1; sel_valid = 1'b1; end
        else if (m_out_valid[rr2]) begin sel = rr2; sel_valid = 1'b1; end
        else if (m_out_valid[rr3]) begin sel = rr3; sel_valid = 1'b1; end
    end

    wire buf_free = (!h_out_valid) || h_out_ready;

    assign m_out_ready[0] = (sel == 2'd0) && sel_valid && buf_free;
    assign m_out_ready[1] = (sel == 2'd1) && sel_valid && buf_free;
    assign m_out_ready[2] = (sel == 2'd2) && sel_valid && buf_free;
    assign m_out_ready[3] = (sel == 2'd3) && sel_valid && buf_free;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr      <= 2'd0;
            h_out_pkt   <= {`TRN_PKT_W{1'b0}};
            h_out_valid <= 1'b0;
            h_out_sel   <= 2'd0;
        end else begin
            if (h_out_valid && h_out_ready)
                h_out_valid <= 1'b0;

            if (buf_free && sel_valid) begin
                h_out_pkt   <= m_out_pkt[sel];
                h_out_valid <= 1'b1;
                h_out_sel   <= sel;
                rr_ptr      <= sel + 2'd1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // G-6 watchdog: projection timeout counter per sub-mesh
    // -----------------------------------------------------------------------
    reg [5:0] wdog [0:3];
    reg [3:0] wdog_armed;
    reg [3:0] timeout_r;

    assign timeout_vec = timeout_r;

    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_wdog
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    wdog[gi]       <= 6'd0;
                    wdog_armed[gi] <= 1'b0;
                    timeout_r[gi]  <= 1'b0;
                end else begin
                    // Arm when COMPUTE sent to this sub-mesh
                    if (m_in_valid[gi] && m_in_ready[gi] &&
                        (`TRN_PKT_OP(m_in_pkt[gi]) == `TRN_OP_COMPUTE)) begin
                        wdog[gi]       <= 6'd0;
                        wdog_armed[gi] <= 1'b1;
                        timeout_r[gi]  <= 1'b0;
                    end
                    // Disarm when RESULT received
                    if (m_out_valid[gi] && m_out_ready[gi] &&
                        (`TRN_PKT_OP(m_out_pkt[gi]) == `TRN_OP_RESULT)) begin
                        wdog_armed[gi] <= 1'b0;
                        timeout_r[gi]  <= 1'b0;
                    end
                    // Count and flag
                    if (wdog_armed[gi]) begin
                        if (wdog[gi] == TIMEOUT_CYCLES) begin
                            timeout_r[gi] <= 1'b1;  // G-6 falsification signal
                        end else begin
                            wdog[gi] <= wdog[gi] + 6'd1;
                        end
                    end
                end
            end
        end
    endgenerate

endmodule
