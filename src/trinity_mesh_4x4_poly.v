`default_nettype none
// trinity_mesh_4x4_poly.v — 4-tile GF(2^4) polynomial mesh fabric.
//
// Anchor: phi^2+phi^-2=3  DOI 10.5281/zenodo.19227877
// Apache-2.0
// Author: Vasilev Dmitrii <admin@t27.ai>  ORCID 0009-0008-4294-6159
//
// Wave-16a PATH-3 SHADOW: experimental GF(2^4) poly mesh.
//   - 4 tiles, each running gf16_dot4_poly (4x gf16_poly_mul instances)
//   - Reuses trinity_router_2x2 crossbar (topology unchanged)
//   - RECEIPT protocol: identical to trinity_mesh_2x2 (G4 DePIN-compatible)
//   - info.yaml UNCHANGED — tt_um_trinity_max stays as active top
//   - Zero $mul cells (R-SI-1). 4-bit native GF(2^4) lanes per tile.
//
// Wave-16b promotion path: point info.yaml at tt_um_trinity_max_poly after
// TTSKY26c freeze.
//
// NOT a replacement for trinity_mesh_2x2.v on the current Octad freeze.
// DO NOT open PR from this file.

`include "trinity_packet.vh"

module trinity_mesh_4x4_poly (
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

    // Debug — lower 4 bits carry native GF(2^4) result of tile 0
    output wire [15:0]                dbg_tile0_result
);

    wire [4*`TRN_PKT_W-1:0] t_pkt_flat;
    wire [3:0]              t_valid;
    wire [3:0]              t_ready;

    wire [4*`TRN_PKT_W-1:0] t_ret_pkt_flat;
    wire [3:0]              t_ret_valid;
    wire [3:0]              t_ret_ready;

    // Reuse the existing 2x2 crossbar router (4 tile ports, single-hop)
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

    // Per-tile wires
    wire [`TRN_PKT_W-1:0] t_in_pkt  [0:3];
    wire [`TRN_PKT_W-1:0] t_out_pkt [0:3];
    wire [15:0]           tile_dbg  [0:3];

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_tile
            assign t_in_pkt[i] = t_pkt_flat[(i+1)*`TRN_PKT_W-1 -: `TRN_PKT_W];
            assign t_ret_pkt_flat[(i+1)*`TRN_PKT_W-1 -: `TRN_PKT_W] = t_out_pkt[i];

            trinity_gf16_tile_poly #(.TILE_ID(i[1:0])) u_tile (
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
        end
    endgenerate

    assign dbg_tile0_result = tile_dbg[0];

endmodule
