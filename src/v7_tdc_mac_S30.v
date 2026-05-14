// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-30 Time-Domain MAC (TDC Delay Line)
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-30 FALSIFICATION: time-domain PE output matches Coq-verified dot4 within
//                     1 LSB on 100% of test vectors; else feature-gated off.
//
// All-digital time-domain MAC model (SPIKA-lite style).
// Each ternary weight {-1,0,+1} encodes pulse width {0,1,2} clock cycles.
// Accumulator is an up/down counter. SIM-ONLY delay chain model.
//
// 4-weight dot product: weight_i in {-1,0,+1}, activation_i in {0,1}.
// MAC output = sum_i( weight_i * activation_i )

`default_nettype none

module v7_tdc_mac_S30 #(
    parameter N      = 4,   // number of inputs (dot-N)
    parameter ACCW   = 8    // accumulator width
) (
    input  wire             clk,
    input  wire             rst,
    input  wire             start,      // begin accumulation
    // Ternary weights: encoded as {w_valid, w_sign} per element
    input  wire [N-1:0]     w_valid,    // 1 = weight is non-zero
    input  wire [N-1:0]     w_sign,     // 1 = weight is -1, 0 = weight is +1
    // Binary activations
    input  wire [N-1:0]     act,        // activation bits

    output reg  signed [ACCW-1:0] acc,  // accumulated result
    output reg                    done  // pulsed 1 cycle when complete
);

    // TDC model: for each input i, generate pulse of width:
    //   pulse_width[i] = act[i] & w_valid[i] ? (1 or 2) : 0
    // w_sign=0 -> +1 contribution, w_sign=1 -> -1 contribution
    // In all-digital model, we compute combinationally and register once.

    // Combinational partial products (no * operator):
    // contribution_i = act[i] ? (w_valid[i] ? (w_sign[i] ? -1 : +1) : 0) : 0
    // Represented as signed 2-bit: 2'b01=+1, 2'b11=-1, 2'b00=0

    reg signed [ACCW-1:0] partial [0:N-1];
    reg signed [ACCW-1:0] new_acc;
    integer k;

    always @(*) begin
        for (k = 0; k < N; k = k+1) begin
            if (act[k] & w_valid[k])
                partial[k] = w_sign[k] ? {{(ACCW-1){1'b1}}, 1'b1} // -1
                                       : {{(ACCW-1){1'b0}}, 1'b1}; // +1
            else
                partial[k] = {ACCW{1'b0}};
        end
        new_acc = {ACCW{1'b0}};
        for (k = 0; k < N; k = k+1)
            new_acc = new_acc + partial[k];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            acc  <= {ACCW{1'b0}};
            done <= 1'b0;
        end else if (start) begin
            acc  <= new_acc;
            done <= 1'b1;
        end else begin
            done <= 1'b0;
        end
    end

endmodule
`default_nettype wire
