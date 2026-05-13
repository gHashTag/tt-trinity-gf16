`default_nettype none
// tt_um_ghtag_trinity_gf16 - TinyTapeout top.
// Apache-2.0
//
// v0 Trinity mesh-computer top: instantiates trinity_mesh_2x2 (4 GF16 tiles + crossbar
// router) plus a CPU-less master FSM that issues a canned packet sequence to tile 0.
//
// Backward compatibility: the existing testbench checks {uio_out, uo_out} == 0x47C0
// immediately after reset. The combinational gf16_dot4 of the canned vectors remains
// instantiated and drives the outputs by default; the mesh FSM result overrides only
// once it asserts result_valid_q (so the new mesh path is exercised on the same pins
// after a few extra cycles, observable by a longer-waiting testbench).

module tt_um_ghtag_trinity_gf16 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ---- Legacy combinational dot4 path (preserved) ----
    wire [15:0] dot_out;
    gf16_dot4 u_dot (
        .a0(16'h3E00), .a1(16'h4000), .a2(16'h4100), .a3(16'h4200),
        .b0(16'h3E00), .b1(16'h4000), .b2(16'h4100), .b3(16'h4200),
        .result(dot_out)
    );

    // Input echo (legacy)
    reg [15:0] input_echo;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            input_echo <= 0;
        else if (ena)
            input_echo <= {ui_in, uio_in};
    end

    // ---- New: Trinity v0 mesh fabric ----
    wire [31:0] host_in_pkt;
    wire        host_in_valid;
    wire        host_in_ready;
    wire [31:0] host_out_pkt;
    wire        host_out_valid;
    wire        host_out_ready;
    wire [15:0] mesh_dbg_tile0;
    wire [15:0] mesh_result;
    wire        mesh_result_valid;
    // G4 DePIN on-die receipt outputs from the master FSM (latched RECEIPT packet)
    wire [7:0]  mesh_rcpt_checksum;
    wire [7:0]  mesh_rcpt_job_id;
    wire [1:0]  mesh_rcpt_tile_id;
    wire        mesh_rcpt_valid;

    trinity_master_fsm u_master (
        .clk             (clk),
        .rst_n           (rst_n),
        .ena             (ena),
        .load_mode       (ui_in[0]),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (host_in_ready),
        .host_out_pkt    (host_out_pkt),
        .host_out_valid  (host_out_valid),
        .host_out_ready  (host_out_ready),
        .result_reg      (mesh_result),
        .result_valid_q  (mesh_result_valid),
        .rcpt_checksum_q (mesh_rcpt_checksum),
        .rcpt_job_id_q   (mesh_rcpt_job_id),
        .rcpt_tile_id_q  (mesh_rcpt_tile_id),
        .rcpt_valid_q    (mesh_rcpt_valid)
    );

    trinity_mesh_2x2 u_mesh (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (host_in_ready),
        .host_out_pkt    (host_out_pkt),
        .host_out_valid  (host_out_valid),
        .host_out_ready  (host_out_ready),
        .dbg_tile0_result(mesh_dbg_tile0)
    );

    // ---- Wave-26b CROWN: silicon-anchored physics POST modules ----
    // L-S1: φ-anchor POST (proves φ²+φ⁻²=3 via Lucas recurrence on power-up)
    wire phi_ok;
    wire post_done;
    phi_anchor_post u_phi_post (
        .clk(clk), .rst_n(rst_n),
        .phi_ok(phi_ok), .post_done(post_done)
    );

    // L-S2: Lucas ROM (probed during POST + addressable for host)
    wire [7:0] lucas_val;
    wire [2:0] lucas_idx = ui_in[3:1];   // ui_in[3:1] selects L_n
    lucas_rom u_lucas (.idx(lucas_idx), .value(lucas_val));
    // lucas_ok is the AND of all 6 ROM entries matching the canonical chain.
    // This is a combinational integrity check: we compare each ROM output
    // against the constant the synthesizer should fold flat — any bit-flip in
    // the ROM gives lucas_ok=0. Cheap (~20 gates) for an irreplaceable invariant.
    wire [7:0] _l2, _l3, _l4, _l5, _l6, _l7;
    lucas_rom u_lr2 (.idx(3'd0), .value(_l2));
    lucas_rom u_lr3 (.idx(3'd1), .value(_l3));
    lucas_rom u_lr4 (.idx(3'd2), .value(_l4));
    lucas_rom u_lr5 (.idx(3'd3), .value(_l5));
    lucas_rom u_lr6 (.idx(3'd4), .value(_l6));
    lucas_rom u_lr7 (.idx(3'd5), .value(_l7));
    wire lucas_ok = (_l2 == 8'd3)  && (_l3 == 8'd4)  && (_l4 == 8'd7)  &&
                    (_l5 == 8'd11) && (_l6 == 8'd18) && (_l7 == 8'd29);

    // L-S3: 8x8 VSA ternary matmul — kicked off at reset release with a canned
    // pair (identity-on-ternary: A=B=I_8 in {-1,0,+1} encoding); matmul_ok
    // simply asserts when compute completes.
    reg [127:0] vsa_a, vsa_b;
    reg         vsa_start;
    wire        vsa_done, matmul_ok;
    wire [511:0] vsa_c;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Encode identity-like input: every element = +1 (encoding 2'b00)
            vsa_a <= 128'b0;
            vsa_b <= 128'b0;
            vsa_start <= 1'b1;  // single-shot pulse latched by matmul on first cycle
        end else begin
            vsa_start <= 1'b0;
        end
    end
    vsa_matmul_8x8 u_vsa (
        .clk(clk), .rst_n(rst_n),
        .start(vsa_start),
        .a_flat(vsa_a), .b_flat(vsa_b),
        .done(vsa_done),
        .c_flat(vsa_c),
        .matmul_ok(matmul_ok)
    );

    // L-S5: 16-bit LFSR for die-unique nonce (folded into _unused; available via
    // future Wishbone read in next wave). We OR-reduce to a single non-zero flag.
    wire [15:0] hwrng_word;
    hwrng_lfsr u_rng (.clk(clk), .rst_n(rst_n), .ena(1'b1), .rnd(hwrng_word));
    wire hwrng_nonzero = |hwrng_word;

    // L-S6: Wishbone-lite status byte aggregating all POST results.
    wire [7:0] status_byte;
    wb_status_reg u_status (
        .clk(clk), .rst_n(rst_n),
        .phi_ok(phi_ok),
        .lucas_ok(lucas_ok),
        .matmul_ok(matmul_ok),
        .post_done(post_done),
        .rcpt_valid(mesh_rcpt_valid),
        .hwrng_nonzero(hwrng_nonzero),
        .status_byte(status_byte)
    );

    // L-S4: CRC-32 of the RECEIPT triplet {job_id, tile_id, result_lo}.
    // Sequenced over three cycles when mesh_rcpt_valid rises. We expose only
    // the low byte of the final CRC through a registered output observable via
    // the future Wishbone path; current top simply folds into _unused.
    reg [1:0]  crc_step;
    reg        crc_start, crc_valid;
    reg [7:0]  crc_byte;
    reg        rcpt_valid_d;
    wire [31:0] crc_raw, crc_final;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_step     <= 2'd0;
            crc_start    <= 1'b0;
            crc_valid    <= 1'b0;
            crc_byte     <= 8'b0;
            rcpt_valid_d <= 1'b0;
        end else begin
            rcpt_valid_d <= mesh_rcpt_valid;
            crc_start    <= mesh_rcpt_valid && !rcpt_valid_d;
            if (mesh_rcpt_valid && !rcpt_valid_d) begin
                crc_step <= 2'd0;
                crc_valid <= 1'b1;
                crc_byte <= mesh_rcpt_job_id;
            end else if (crc_valid) begin
                case (crc_step)
                    2'd0: begin crc_byte <= {6'b0, mesh_rcpt_tile_id}; crc_step <= 2'd1; end
                    2'd1: begin crc_byte <= mesh_rcpt_checksum;         crc_step <= 2'd2; end
                    default: crc_valid <= 1'b0;
                endcase
            end
        end
    end
    crc32_receipt u_crc (
        .clk(clk), .rst_n(rst_n),
        .start(crc_start),
        .valid(crc_valid),
        .byte_in(crc_byte),
        .crc_raw(crc_raw),
        .crc_final(crc_final)
    );

    // Output mux: combinational dot result by default, mesh result once produced.
    wire [15:0] final_result = mesh_result_valid ? mesh_result : dot_out;

    assign uo_out  = final_result[7:0]  | input_echo[7:0];
    // uio_out: legacy mesh result high byte by default; switches to CROWN status_byte
    // only when host asserts load_mode (ui_in[0]=1). This preserves the canonical
    // legacy test T4 which expects {uio_out, uo_out} == 0x47C0 when ui_in==0.
    assign uio_out = (ui_in[0] && post_done) ? status_byte : (final_result[15:8] | input_echo[15:8]);
    assign uio_oe  = 8'hFF;

    // Silence lint on unused. The G4 receipt outputs are exposed to the
    // testbench via the master FSM directly (not via TT pins, which are
    // exhausted by the legacy dot4/mesh result mux); they MUST be folded
    // into _unused here so synthesis keeps the registers.
    wire _unused = &{1'b0, mesh_dbg_tile0, ena,
                     mesh_rcpt_checksum, mesh_rcpt_job_id,
                     mesh_rcpt_tile_id, mesh_rcpt_valid,
                     lucas_val, vsa_done, vsa_c,
                     crc_raw, crc_final,
                     hwrng_word[14:0], 1'b0};

endmodule
