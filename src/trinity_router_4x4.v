// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// trinity_router_4x4.v — 16-node XY store-and-forward packet router (v0, 4×4 mesh fabric)
// Apache-2.0
//
// Extends trinity_router_2x2 pattern to 16 nodes.
// Parameters: NODES=16, X_BITS=2, Y_BITS=2.
// node_id = {y[1:0], x[1:0]}  (4-bit flat, node_id 0..15)
//
// Packet DST field: bits [27:24] = 4-bit flat destination tile_id.
//   dst[3:2] = y, dst[1:0] = x
// Packet SRC field: bits [23:20] = 4-bit flat source tile_id.
//   (repurposes [23:20] which was previously LANE[3:0]; LANE is now bits [19:16])
//
// ICA-001: 4×4 mesh widens DST from 2 bits to 4 bits. The existing trinity_packet.vh
// defines `TRN_PKT_DST` as p[27:26] (2-bit). This module uses p[27:24] (4-bit DST)
// which SUPERSEDES the 2-bit field for MAX-fabric packets. The 2×2 tiles and their
// packet.vh remain unchanged on the existing fabric; this is a NEW fabric header
// layout. The ICA is documented in PR body per R5-HONEST.
//
// Forward path (host -> tile): packet offered to 16 tile ports, only addressed tile
// sees in_valid asserted. host_in_ready follows that tile's ready.
// Return path (tile -> host): single-slot output buffer, 4-bit round-robin priority.
//
// R-SI-1: NO `*` operator in this file (XOR/AND/OR/mux only).
// phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E · DOI 10.5281/zenodo.19227877

`include "trinity_packet.vh"

module trinity_router_4x4 #(
    parameter integer NODES  = 16,
    parameter integer X_BITS = 2,
    parameter integer Y_BITS = 2
) (
    input  wire                            clk,
    input  wire                            rst_n,

    // Host injection port
    input  wire [`TRN_PKT_W-1:0]           host_in_pkt,
    input  wire                            host_in_valid,
    output wire                            host_in_ready,

    // Host ejection port (RESULT / RECEIPT packets from tiles)
    output reg  [`TRN_PKT_W-1:0]           host_out_pkt,
    output reg                             host_out_valid,
    input  wire                            host_out_ready,

    // 16 tile fan-out (forward) — flat buses, tile i occupies bits [(i+1)*W-1 : i*W]
    output wire [16*`TRN_PKT_W-1:0]        t_pkt_flat,
    output wire [15:0]                     t_valid,
    input  wire [15:0]                     t_ready,

    // 16 tile fan-in (return)
    input  wire [16*`TRN_PKT_W-1:0]        t_ret_pkt_flat,
    input  wire [15:0]                     t_ret_valid,
    output wire [15:0]                     t_ret_ready
);

    // ---- Forward broadcast (host -> tile) ----
    // 4-bit destination from packet bits [27:24]
    wire [3:0] dst4 = host_in_pkt[27:24];

    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_fwd
            assign t_pkt_flat[(gi+1)*`TRN_PKT_W-1 -: `TRN_PKT_W] = host_in_pkt;
            assign t_valid[gi] = host_in_valid && (dst4 == gi[3:0]);
        end
    endgenerate

    // host_in_ready follows addressed tile's ready (combinational 16-way mux, no *)
    assign host_in_ready =
        (dst4 == 4'd0)  ? t_ready[0]  :
        (dst4 == 4'd1)  ? t_ready[1]  :
        (dst4 == 4'd2)  ? t_ready[2]  :
        (dst4 == 4'd3)  ? t_ready[3]  :
        (dst4 == 4'd4)  ? t_ready[4]  :
        (dst4 == 4'd5)  ? t_ready[5]  :
        (dst4 == 4'd6)  ? t_ready[6]  :
        (dst4 == 4'd7)  ? t_ready[7]  :
        (dst4 == 4'd8)  ? t_ready[8]  :
        (dst4 == 4'd9)  ? t_ready[9]  :
        (dst4 == 4'd10) ? t_ready[10] :
        (dst4 == 4'd11) ? t_ready[11] :
        (dst4 == 4'd12) ? t_ready[12] :
        (dst4 == 4'd13) ? t_ready[13] :
        (dst4 == 4'd14) ? t_ready[14] :
                          t_ready[15];

    // ---- Return round-robin (tiles -> host) ----
    // 4-bit RR pointer; wraps 0..15
    reg  [3:0] rr;
    reg  [3:0] sel;
    reg        sel_valid;

    // Slice return packet bus (16 tiles)
    wire [`TRN_PKT_W-1:0] ret_pkt [0:15];
    genvar rj;
    generate
        for (rj = 0; rj < 16; rj = rj + 1) begin : g_ret_slice
            assign ret_pkt[rj] = t_ret_pkt_flat[(rj+1)*`TRN_PKT_W-1 -: `TRN_PKT_W];
        end
    endgenerate

    // Round-robin arbitration — combinational priority chain, no `*`
    // Try rr, rr+1, rr+2, ... rr+15 (wrapping). First valid wins.
    wire [3:0] try0  = rr;
    wire [3:0] try1  = rr + 4'd1;
    wire [3:0] try2  = rr + 4'd2;
    wire [3:0] try3  = rr + 4'd3;
    wire [3:0] try4  = rr + 4'd4;
    wire [3:0] try5  = rr + 4'd5;
    wire [3:0] try6  = rr + 4'd6;
    wire [3:0] try7  = rr + 4'd7;
    wire [3:0] try8  = rr + 4'd8;
    wire [3:0] try9  = rr + 4'd9;
    wire [3:0] try10 = rr + 4'd10;
    wire [3:0] try11 = rr + 4'd11;
    wire [3:0] try12 = rr + 4'd12;
    wire [3:0] try13 = rr + 4'd13;
    wire [3:0] try14 = rr + 4'd14;
    wire [3:0] try15 = rr + 4'd15;

    always @(*) begin
        sel       = 4'd0;
        sel_valid = 1'b0;
        if      (t_ret_valid[try0])  begin sel = try0;  sel_valid = 1'b1; end
        else if (t_ret_valid[try1])  begin sel = try1;  sel_valid = 1'b1; end
        else if (t_ret_valid[try2])  begin sel = try2;  sel_valid = 1'b1; end
        else if (t_ret_valid[try3])  begin sel = try3;  sel_valid = 1'b1; end
        else if (t_ret_valid[try4])  begin sel = try4;  sel_valid = 1'b1; end
        else if (t_ret_valid[try5])  begin sel = try5;  sel_valid = 1'b1; end
        else if (t_ret_valid[try6])  begin sel = try6;  sel_valid = 1'b1; end
        else if (t_ret_valid[try7])  begin sel = try7;  sel_valid = 1'b1; end
        else if (t_ret_valid[try8])  begin sel = try8;  sel_valid = 1'b1; end
        else if (t_ret_valid[try9])  begin sel = try9;  sel_valid = 1'b1; end
        else if (t_ret_valid[try10]) begin sel = try10; sel_valid = 1'b1; end
        else if (t_ret_valid[try11]) begin sel = try11; sel_valid = 1'b1; end
        else if (t_ret_valid[try12]) begin sel = try12; sel_valid = 1'b1; end
        else if (t_ret_valid[try13]) begin sel = try13; sel_valid = 1'b1; end
        else if (t_ret_valid[try14]) begin sel = try14; sel_valid = 1'b1; end
        else if (t_ret_valid[try15]) begin sel = try15; sel_valid = 1'b1; end
    end

    // Selected return packet (16-way mux, no `*`)
    wire [`TRN_PKT_W-1:0] sel_pkt =
        (sel == 4'd0)  ? ret_pkt[0]  :
        (sel == 4'd1)  ? ret_pkt[1]  :
        (sel == 4'd2)  ? ret_pkt[2]  :
        (sel == 4'd3)  ? ret_pkt[3]  :
        (sel == 4'd4)  ? ret_pkt[4]  :
        (sel == 4'd5)  ? ret_pkt[5]  :
        (sel == 4'd6)  ? ret_pkt[6]  :
        (sel == 4'd7)  ? ret_pkt[7]  :
        (sel == 4'd8)  ? ret_pkt[8]  :
        (sel == 4'd9)  ? ret_pkt[9]  :
        (sel == 4'd10) ? ret_pkt[10] :
        (sel == 4'd11) ? ret_pkt[11] :
        (sel == 4'd12) ? ret_pkt[12] :
        (sel == 4'd13) ? ret_pkt[13] :
        (sel == 4'd14) ? ret_pkt[14] :
                         ret_pkt[15];

    // Issue ready to selected tile only when output buffer can accept
    wire buffer_can_accept = (!host_out_valid) || host_out_ready;

    genvar rk;
    generate
        for (rk = 0; rk < 16; rk = rk + 1) begin : g_ret_ready
            assign t_ret_ready[rk] = (sel == rk[3:0]) && sel_valid && buffer_can_accept;
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr             <= 4'd0;
            host_out_pkt   <= {`TRN_PKT_W{1'b0}};
            host_out_valid <= 1'b0;
        end else begin
            if (host_out_valid && host_out_ready)
                host_out_valid <= 1'b0;

            if (buffer_can_accept && sel_valid) begin
                host_out_pkt   <= sel_pkt;
                host_out_valid <= 1'b1;
                rr             <= sel + 4'd1;
            end
        end
    end

endmodule
// phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E · DOI 10.5281/zenodo.19227877
