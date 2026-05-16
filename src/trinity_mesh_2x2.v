`default_nettype none
// trinity_mesh_2x2.v - v0 mesh fabric: 4 GF16 tiles + 1 router with host injection/ejection.
// Apache-2.0
//
// L-S16 Sparse PE v2 upgrade: 4 sparse_pe_v2 instances wired alongside the
// trinity_gf16_tile compute path. Each tile now exposes:
//   - skip_strobe[i]: 1-cycle pulse when tile i had all-zero operands this cycle
//   - sat_skip_cnt[i][7:0]: 8-bit saturating count of all-zero cycles per tile
// These are collected in dbg_sparse_* outputs for telemetry / CI verification.
//
// Topology unchanged: 4 addressable compute tiles behind one crossbar.
// This is the same single-hop fabric; sparse_pe_v2 sits *alongside* each tile,
// monitoring the same operand registers via the tile's debug interface.
//
// Implementation note: sparse_pe_v2 monitors tile operands b0..b3 / a0..a3.
// Since trinity_gf16_tile does not expose operand registers as outputs, the
// sparse_pe_v2 instances are connected to the flat packet payload bus so that
// zero-weight detection is done at the mesh injection layer (packet scan).
// The skip_strobe and sat_skip_cnt are routed to dbg outputs for test visibility.
//
// For full intra-tile integration, see trinity_gf16_tile.v where the sparse
// path can be instantiated at the MAC level (see S-16 PATCH in spec).
//
// R-SI-1 compliant. Pure Verilog-2005.
// Anchor: phi^2 + phi^-2 = 3 (DOI: 10.5281/zenodo.19227877)

`include "trinity_packet.vh"

module trinity_mesh_2x2 (
    input  wire                       clk,
    input  wire                       rst_n,

    // Host injection (issue packets to tiles)
    input  wire [`TRN_PKT_W-1:0]      host_in_pkt,
    input  wire                       host_in_valid,
    output wire                       host_in_ready,

    // Host ejection (RESULT packets from tiles)
    output wire [`TRN_PKT_W-1:0]      host_out_pkt,
    output wire                       host_out_valid,
    input  wire                       host_out_ready,

    // Debug — original
    output wire [15:0]                dbg_tile0_result,

    // L-S16 debug outputs: sparse PE telemetry for all 4 PEs
    output wire [3:0]                 dbg_skip_strobe,   // skip_strobe[i] per tile
    output wire [31:0]                dbg_sat_skip_cnt   // 4 × 8-bit sat_skip_cnt
);

    wire [4*`TRN_PKT_W-1:0] t_pkt_flat;
    wire [3:0]              t_valid;
    wire [3:0]              t_ready;

    wire [4*`TRN_PKT_W-1:0] t_ret_pkt_flat;
    wire [3:0]              t_ret_valid;
    wire [3:0]              t_ret_ready;

    trinity_router_2x2 u_router (
        .clk            (clk),
        .rst_n          (rst_n),
        .host_in_pkt    (host_in_pkt),
        .host_in_valid  (host_in_valid),
        .host_in_ready  (host_in_ready),
        .host_out_pkt   (host_out_pkt),
        .host_out_valid (host_out_valid),
        .host_out_ready (host_out_ready),
        .t_pkt_flat     (t_pkt_flat),
        .t_valid        (t_valid),
        .t_ready        (t_ready),
        .t_ret_pkt_flat (t_ret_pkt_flat),
        .t_ret_valid    (t_ret_valid),
        .t_ret_ready    (t_ret_ready)
    );

    // Per-tile wires (sliced from the flat buses)
    wire [`TRN_PKT_W-1:0] t_in_pkt   [0:3];
    wire [`TRN_PKT_W-1:0] t_out_pkt  [0:3];
    wire [15:0]           tile_dbg   [0:3];

    // L-S16: sparse PE telemetry per tile
    wire        spe_skip_strobe [0:3];
    wire        spe_clk_en      [0:3];
    wire [7:0]  spe_sat_cnt     [0:3];
    wire [15:0] spe_result      [0:3];
    wire [3:0]  spe_lane_active [0:3];

    // L-S16: sparse_pe_v2 inputs derived from injected packet payload.
    // When a LOAD_B (weight) packet is received, payload = b-operand GF16 word.
    // We present the packet payload on b0; b1..b3 are 0 (packet loads one lane/cycle).
    // This matches the per-lane load protocol and captures non-zero detection on
    // every b-lane load cycle (the most impactful zero-skip opportunity).
    wire [15:0] spe_payload [0:3];

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_tile
            assign t_in_pkt[i]  = t_pkt_flat[(i+1)*`TRN_PKT_W-1 -: `TRN_PKT_W];
            assign t_ret_pkt_flat[(i+1)*`TRN_PKT_W-1 -: `TRN_PKT_W] = t_out_pkt[i];

            // Payload extraction (b-lane operand word from packet)
            assign spe_payload[i] = `TRN_PKT_PAYLOAD(t_in_pkt[i]);

            // L-S20: enable DOT_WIDTH=8 (gf16_dot8 = 2x dot4 + adder) for 2x TOPS/tile.
            trinity_gf16_tile #(.TILE_ID(i[1:0]), .DOT_WIDTH(8)) u_tile (
                .clk        (clk),
                .rst_n      (rst_n),
                .in_pkt     (t_in_pkt[i]),
                .in_valid   (t_valid[i]),
                .in_ready   (t_ready[i]),
                .out_pkt    (t_out_pkt[i]),
                .out_valid  (t_ret_valid[i]),
                .out_ready  (t_ret_ready[i]),
                .dbg_result (tile_dbg[i])
            );

            // L-S16: sparse_pe_v2 monitoring this tile's operand lane 0.
            // b0 = current packet payload (weight being loaded this cycle).
            // a0 = tile debug result from previous cycle (act proxy for zero test).
            // b1..b3, a1..a3 = 16'h0000 (only lane 0 monitored at mesh layer).
            // Full intra-tile 4-lane monitoring: see trinity_gf16_tile S-16 PATCH.
            sparse_pe_v2 u_spe (
                .clk         (clk),
                .rst_n       (rst_n),
                .a0          (tile_dbg[i]),    // activation proxy: last result
                .a1          (16'h0000),
                .a2          (16'h0000),
                .a3          (16'h0000),
                .b0          (spe_payload[i]), // weight: current packet payload
                .b1          (16'h0000),
                .b2          (16'h0000),
                .b3          (16'h0000),
                .result      (spe_result[i]),
                .lane_active (spe_lane_active[i]),
                .skip_strobe (spe_skip_strobe[i]),
                .clk_en      (spe_clk_en[i]),
                .sat_skip_cnt(spe_sat_cnt[i])
            );
        end
    endgenerate

    assign dbg_tile0_result = tile_dbg[0];

    // Aggregate L-S16 telemetry outputs
    assign dbg_skip_strobe  = {spe_skip_strobe[3], spe_skip_strobe[2],
                               spe_skip_strobe[1], spe_skip_strobe[0]};
    assign dbg_sat_skip_cnt = {spe_sat_cnt[3], spe_sat_cnt[2],
                               spe_sat_cnt[1], spe_sat_cnt[0]};

endmodule
