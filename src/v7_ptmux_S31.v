// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-31 Pass-Transistor MUX (sim model)
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-31 FALSIFICATION: PT-mux PE matches Coq-verified dot4 within 1 LSB on
//                     100% of test vectors; else feature-gated off.
//
// Pass-transistor 3:1 T-MUX model for ternary weight selection.
// Physical: w in {-1,0,+1} selects one of three signal paths via pass NMOS.
// Simulation model: behavioural RTL equivalent.
// Cite: Bentham MNS 2022 T-Mux (DOI 10.2174/1876402914666220425124154).
//
// For each weight/activation pair:
//   sel=2'b00 -> zero path (weight=0)
//   sel=2'b01 -> positive path (weight=+1): output = activation
//   sel=2'b11 -> negative path (weight=-1): output = ~activation (invert)
// Accumulator sums 4 PT-mux outputs.

`default_nettype none

module v7_ptmux_S31 #(
    parameter N    = 4,   // number of ternary MAC lanes
    parameter ACCW = 8    // accumulator width
) (
    // Ternary encoding: {w_valid[i], w_sign[i]}
    // w_valid=0 -> zero; w_valid=1,w_sign=0 -> +1; w_valid=1,w_sign=1 -> -1
    input  wire [N-1:0]  w_valid,
    input  wire [N-1:0]  w_sign,
    input  wire [N-1:0]  act,         // binary activations

    output wire signed [ACCW-1:0] acc_out  // combinational dot product
);

    // PT-mux function: select path based on weight
    // positive: pass act through (+1 contribution)
    // negative: invert act (-1 contribution, i.e., NOT reduces by 1 then +0 => treat as subtract)
    // zero:     no contribution

    // Signed partial: +1 if (w_valid=1,w_sign=0,act=1), -1 if (w_valid=1,w_sign=1,act=1), else 0
    wire signed [ACCW-1:0] part [0:N-1];
    genvar i;
    generate
        for (i = 0; i < N; i = i+1) begin : gen_ptmux
            assign part[i] = (w_valid[i] & act[i]) ?
                                 (w_sign[i] ? {{(ACCW-1){1'b1}}, 1'b1}   // -1 sign-extended
                                            : {{(ACCW-1){1'b0}}, 1'b1})  // +1 sign-extended
                               : {ACCW{1'b0}};
        end
    endgenerate

    // Tree reduction (no *)
    wire signed [ACCW-1:0] sum01 = part[0] + part[1];
    wire signed [ACCW-1:0] sum23 = part[2] + part[3];
    assign acc_out = sum01 + sum23;

endmodule
`default_nettype wire
