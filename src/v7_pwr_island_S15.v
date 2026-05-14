// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// v7_pwr_island_S15.v — S-15 Power island isolator (dual-rail 1.8V / 0.9V)
// TT-Shuttle Squeeze v7 · W15-TT-D Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// G-15 FALSIFICATION: SKY130 low-VT cells produce clean waveforms @ 0.9 V in
//                     SPICE; else single-rail 1.8 V.
//
// S-15 dual-rail Vdd: compute path at 1.8 V, ROM + scan-chain at 0.9 V.
// Energy ∝ V² → −75% on slow control paths.
// This RTL model captures the isolation + level-shifter boundary cell wrappers.
// Actual LDO + level-shifter cells are technology-specific (sky130_fd_sc_hd__lpflow*);
// this module provides the structural wrapper and isolation enable logic.

`default_nettype none

module v7_pwr_island_S15 #(
    parameter WIDTH = 8  // data bus width crossing the rail boundary
) (
    // 1.8 V domain signals
    input  wire             iso_en_hv,      // 1 = compute island active (1.8 V)
    input  wire [WIDTH-1:0] data_hv_in,     // data from 1.8 V compute domain
    output wire [WIDTH-1:0] data_lv_out,    // level-shifted out to 0.9 V domain

    // 0.9 V domain signals
    input  wire [WIDTH-1:0] data_lv_in,     // data from 0.9 V control domain
    output wire [WIDTH-1:0] data_hv_out,    // level-shifted out to 1.8 V domain
    output wire             iso_ok          // isolation handshake: 1 = boundary stable
);

    // Isolation clamp: when compute island is powered down, clamp outputs to 0
    // (* SYNTHESIS_CELL = "sky130_fd_sc_hd__lpflow_isobufsrc_1" *)
    wire [WIDTH-1:0] iso_clamped;
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : iso_clamp
            assign iso_clamped[i] = iso_en_hv & data_hv_in[i];
        end
    endgenerate

    // Level-shifter stub: 1.8V → 0.9V (HV→LV)
    // Real cells: sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_isowell_tap_1
    // RTL approximation (behaviour preserved; cell replaced in tech-mapping)
    assign data_lv_out = iso_clamped[WIDTH-1:0];

    // Level-shifter stub: 0.9V → 1.8V (LV→HV)
    assign data_hv_out = data_lv_in[WIDTH-1:0];

    // Isolation handshake: always OK in RTL model (driven by power-sequencer in real flow)
    assign iso_ok = 1'b1;

endmodule
`default_nettype wire
