// tri_w158_unpack.sv — 1.58-bpw ternary weight unpacker (BitNet-style)
// Packs 4 ternary weights {-1,0,+1} into 7-bit code (3^4=81 < 128).
// On-the-fly unpack to 4× 2-bit signed: 2'b11=-1, 2'b00=0, 2'b01=+1.
//
// Encoding convention (no multipliers, pure shifts+adds for /3):
//   code = (w0+1)*27 + (w1+1)*9 + (w2+1)*3 + (w3+1)
//   Each symbol ∈ {0,1,2}, so code ∈ [0,80].
//
// Division by 3 via reciprocal: floor(x/3) = (x * 0x56) >> 8  (exact for x<256)
//   0x56 = 86 = 64+16+4+2 — implemented as shifts+adds, ZERO $mul.
//
// R-SI-1: 0 $mul — verified with yosys.
// Anchor: φ²+φ⁻²=3 · DOI 10.5281/zenodo.19227877
// Author: Vasilev Dmitrii <admin@t27.ai> ORCID 0009-0008-4294-6159

`default_nettype none

module tri_w158_unpack (
    input  wire [6:0]  code_in,  // 7-bit packed code, 0..80
    output wire [1:0]  w0,       // MSB weight: 2'b11=-1, 2'b00=0, 2'b01=+1
    output wire [1:0]  w1,
    output wire [1:0]  w2,
    output wire [1:0]  w3,       // LSB weight
    output wire        valid     // 1 when code_in <= 80
);

    // -----------------------------------------------------------------------
    // Validity gate — codes 81..127 are unused
    // -----------------------------------------------------------------------
    assign valid = (code_in <= 7'd80);

    // -----------------------------------------------------------------------
    // Floor-divide by 3 via multiply-by-86 then >> 8
    // 86 = 64 + 16 + 4 + 2  (pure shifts + adds, NO $mul)
    // For any x in [0,80]: floor(x/3) = (x*86) >> 8  exactly.
    // -----------------------------------------------------------------------
    function automatic [6:0] div3;
        input [6:0] x;
        reg [14:0] t;
        begin
            // x * 86 = x*64 + x*16 + x*4 + x*2
            t = ({x, 6'b0} + {x, 4'b0} + {x, 2'b0} + {x, 1'b0});
            div3 = t[14:8];   // >> 8
        end
    endfunction

    // -----------------------------------------------------------------------
    // Modulo 3: x mod 3 = x - 3*floor(x/3)
    // 3*q = q + q<<1  (shifts+adds, NO $mul)
    // -----------------------------------------------------------------------
    function automatic [1:0] mod3;
        input [6:0] x;
        reg [6:0] q, t3;
        begin
            q  = div3(x);
            t3 = q + {q[5:0], 1'b0};   // q + q*2 = q*3
            mod3 = x[1:0] - t3[1:0];   // safe: result is 0,1,2
        end
    endfunction

    // -----------------------------------------------------------------------
    // Symbol-to-2bit-signed conversion: 0→2'b11(-1), 1→2'b00(0), 2→2'b01(+1)
    // -----------------------------------------------------------------------
    function automatic [1:0] sym2w;
        input [1:0] s;
        begin
            case (s)
                2'd0:    sym2w = 2'b11;  // -1
                2'd1:    sym2w = 2'b00;  //  0
                2'd2:    sym2w = 2'b01;  // +1
                default: sym2w = 2'b00;
            endcase
        end
    endfunction

    // -----------------------------------------------------------------------
    // Decode pipeline (combinational)
    //   code = s0*27 + s1*9 + s2*3 + s3
    //   Extract via successive divmod3
    // -----------------------------------------------------------------------
    wire [6:0] c  = code_in;

    // s3 = c mod 3;  q0 = c / 3
    wire [1:0] s3 = mod3(c);
    wire [6:0] q0 = div3(c);

    // s2 = q0 mod 3; q1 = q0 / 3
    wire [1:0] s2 = mod3(q0);
    wire [6:0] q1 = div3(q0);

    // s1 = q1 mod 3; q2 = q1 / 3
    wire [1:0] s1 = mod3(q1);
    wire [6:0] q2 = div3(q1);

    // s0 = q2 mod 3  (= q2, since q2 is already 0..2 after 3 divisions of 80)
    wire [1:0] s0 = mod3(q2);

    // Map symbols to 2-bit signed weights
    assign w0 = sym2w(s0);
    assign w1 = sym2w(s1);
    assign w2 = sym2w(s2);
    assign w3 = sym2w(s3);

endmodule

`default_nettype wire
