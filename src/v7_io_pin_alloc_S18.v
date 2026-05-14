// SPDX-License-Identifier: Apache-2.0
// v7_io_pin_alloc_S18.v — W15-TT-A: IO permute / floorplan-aware pin allocator (S-18)
// TRI-NET-G1 / TT-Shuttle Squeeze v7  |  Anchor: phi^2 + phi^-2 = 3
//
// G-18 FALSIFICATION: for every input permutation index i in 0..PIN_COUNT-1,
//   perm_out[PERM_TABLE[i]] == data_in[i]; any mismatch → test FAIL.
//   Checked by simulation exhaustive test over all parameter-table entries.
//
// S-18: Floorplan-aware IO pin permutation.
//   OpenLane2 / DREAMPlace may reorder pins for wire-length minimisation (S-45).
//   This module applies a compile-time permutation table so that the logical
//   signal order presented to the mesh matches the physical pin assignment
//   produced by the floorplan tool.  The table is pure combinational (zero FF);
//   synthesis will fold it into the pin-pad connection list.
//
// TT shuttle IO budget: 24 pins total — 8 in, 8 out, 8 bidir uio[].
//   PIN_COUNT = 8 matches the uio[] bus width.
//
// No `*`; purely combinational mux tree.
// USB-3: not involved here (this allocates the bidir uio[] DDR pins, not USB-3).
// R5 honesty: pin order improvement is a projection dependent on DREAMPlace run.
//
`default_nettype none

module v7_io_pin_alloc_S18 #(
    // Number of IO pins to permute (matches uio[] bus width)
    parameter PIN_COUNT = 8,

    // Permutation table: PERM_TABLE[i] = physical pin index for logical signal i
    // Default = identity (no permutation); override per floorplan.
    // Must be a valid permutation (bijection) of 0..PIN_COUNT-1.
    parameter [PIN_COUNT*4-1:0] PERM_TABLE =
        // Packed as {index7, index6, index5, index4, index3, index2, index1, index0}
        // Default identity: perm[i] = i
        { 4'd7, 4'd6, 4'd5, 4'd4, 4'd3, 4'd2, 4'd1, 4'd0 }
) (
    // Logical data bus (from internal datapath, e.g. v7_io_burst_S3 output)
    input  wire [PIN_COUNT-1:0] data_in,

    // Permuted physical pin bus (drives uio[] output enables / data)
    output wire [PIN_COUNT-1:0] perm_out,

    // Inverse permutation input: physical pad samples → logical data_out
    input  wire [PIN_COUNT-1:0] pad_in,
    output wire [PIN_COUNT-1:0] data_out
);

    // -----------------------------------------------------------------------
    // Forward permutation: logical → physical
    //   perm_out[ PERM_TABLE[i] ] = data_in[i]
    // Implemented as a combinational mux tree; Yosys will optimise to wires.
    // -----------------------------------------------------------------------

    // Unpack permutation table
    wire [3:0] perm_idx [0:PIN_COUNT-1];

    genvar gi;
    generate
        for (gi = 0; gi < PIN_COUNT; gi = gi + 1) begin : g_unpack
            assign perm_idx[gi] = PERM_TABLE[gi*4 +: 4];
        end
    endgenerate

    // Build forward output: for each physical pin p, find the logical i where
    // perm_idx[i] == p and assign data_in[i].
    // With static parameters Yosys resolves this to a wire.
    genvar p;
    generate
        for (p = 0; p < PIN_COUNT; p = p + 1) begin : g_fwd
            // One-hot select across logical inputs
            wire [PIN_COUNT-1:0] contrib;
            genvar ii;
            for (ii = 0; ii < PIN_COUNT; ii = ii + 1) begin : g_contrib
                assign contrib[ii] = data_in[ii] & (perm_idx[ii] == p[3:0]);
            end
            assign perm_out[p] = |contrib;
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Inverse permutation: physical → logical
    //   data_out[i] = pad_in[ PERM_TABLE[i] ]
    // -----------------------------------------------------------------------
    generate
        for (gi = 0; gi < PIN_COUNT; gi = gi + 1) begin : g_inv
            // Select one bit from pad_in using the permutation index
            wire [PIN_COUNT-1:0] pad_sel;
            genvar jj;
            for (jj = 0; jj < PIN_COUNT; jj = jj + 1) begin : g_padsel
                assign pad_sel[jj] = pad_in[jj] & (jj[3:0] == perm_idx[gi]);
            end
            assign data_out[gi] = |pad_sel;
        end
    endgenerate

endmodule
