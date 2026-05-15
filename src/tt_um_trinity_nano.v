// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Vasilev Dmitrii <admin@t27.ai>
//
// tt_um_trinity_nano.v  — TRI-1 Nano 1x1 single-tile TinyTapeout top
//
// EPIC #61 W15-TT-E · TTSKY26b · Wave-24 RVR-018
//
// Mirrors the IO-pad signature of tt_um_ghtag_trinity_gf16 (Mid 8x2) exactly.
// Wraps ONE trinity_gf16_tile (TILE_ID=0, DOT_WIDTH=4).
//
// IO marshalling (input shift-register style, reduced to 1 tile):
//   Phase 0 (ui_in[0]=0): ui_in[7:0] = a_lo, uio_in[7:0] = b_lo
//                          loads a0[7:0], b0[7:0]
//   Phase 1 (ui_in[0]=1): ui_in[7:0] = a_hi, uio_in[7:0] = b_hi
//                          loads a0[15:8], b0[15:8]; then fires COMPUTE
//
// On COMPUTE, result[15:0] is latched; uo_out <= result[7:0],
// uio_out <= result[15:8].  uio_oe <= 8'hFF (all outputs).
//
// Packet assembly is direct (no mesh router): the tile is driven
// via its in_pkt / in_valid / in_ready / out_pkt interface.
//
// R-SI-1 VERIFIED: zero '*' operators in this file.
//
// Anchor: phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E
//         DOI 10.5281/zenodo.19227877

`default_nettype none
`include "trinity_packet.vh"

module tt_um_trinity_nano (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ---------------------------------------------------------------
    // State machine: drive the single tile through the packet protocol
    // STATES:
    //   S_LOAD_A0_LO  load A lane-0 low byte (+ load job_id)
    //   S_LOAD_A0_HI  load A lane-0 high byte + load B lane-0 both bytes + COMPUTE + READ_RES
    //   S_WAIT        wait for tile to emit RESULT packet
    //   S_IDLE        result latched, hold outputs
    // ---------------------------------------------------------------

    localparam S_IDLE      = 2'd0;
    localparam S_LOAD_LO   = 2'd1;
    localparam S_COMPUTE   = 2'd2;
    localparam S_WAIT      = 2'd3;

    reg [1:0] state;

    // Packet builder wires
    reg  [`TRN_PKT_W-1:0] pkt_reg;
    reg                   pkt_valid;
    wire                  pkt_ready;

    // Tile output
    wire [`TRN_PKT_W-1:0] tile_out_pkt;
    wire                   tile_out_valid;
    // We always accept tile output
    wire                   tile_out_ready = 1'b1;

    // Input operand latches
    reg [15:0] a0_latch, a1_latch, a2_latch, a3_latch;
    reg [15:0] b0_latch, b1_latch, b2_latch, b3_latch;
    reg  [7:0] job_id_latch;

    // Result latch
    reg [15:0] result_reg;
    reg        result_valid_r;

    // DePIN RECEIPT capture (TG-Nano-06)
    reg [7:0]  rcpt_checksum_r;
    reg [7:0]  rcpt_job_id_r;
    reg [1:0]  rcpt_tile_id_r;
    reg        rcpt_valid_r;

    // ---------------------------------------------------------------
    // Operand capture from IO pins (input shift-register style)
    // ui_in[0] = phase flag: 0=lo, 1=hi (mirrors Mid IO marshalling)
    // ui_in[7:1] = a_data[6:0]
    // uio_in[7:0] = b_data[7:0]
    // a_data[7] is ui_in[7] (full 8-bit available)
    //
    // Reduces to 4 lanes a0..a3, b0..b3 fed from shifts of {ui_in,uio_in}
    // For 1 tile (dot4), we expose 4 lanes:
    //   lane 0: a0 / b0 from phase-0 {ui_in, uio_in}
    //   lane 1: a1 / b1 from phase-1 {ui_in, uio_in}
    //   lane 2: a2 / b2 from phase-2 {ui_in, uio_in} (reuse hi sample)
    //   lane 3: a3 / b3 = constant GF16 identity (0x0001) to reduce pins
    //
    // Simpler for 1-tile Nano: use a 2-phase approach
    //   Phase ui_in[1:0] = 2'b00 -> load a0 & b0
    //   Phase ui_in[1:0] = 2'b01 -> load a1 & b1
    //   Phase ui_in[1:0] = 2'b10 -> load a2 & b2 + a3/b3 from uio_in high nibble
    //   Phase ui_in[1:0] = 2'b11 -> issue COMPUTE; job_id = uio_in[7:0]
    // ---------------------------------------------------------------

    wire [1:0] io_phase = ui_in[1:0];
    wire [7:0] a_byte   = ui_in[7:0];   // full ui_in used as A-byte source
    wire [7:0] b_byte   = uio_in[7:0];  // full uio_in used as B-byte source

    // Pending packet sequence counter
    // We send: LOAD_JOB, LOAD_A(x4), LOAD_B(x4), COMPUTE, READ_RES
    // Total = 10 packets.  Sequence driven by pkt_seq register.
    reg [3:0] pkt_seq;
    // 0 = LOAD_JOB, 1..4 = LOAD_A(0..3), 5..8 = LOAD_B(0..3), 9 = COMPUTE, 10 = READ_RES

    // Edge detect on io_phase == 2'b11 (rising edge of compute trigger)
    reg io_phase_prev;
    wire trigger_compute = (io_phase == 2'b11) && (!io_phase_prev);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            io_phase_prev <= 1'b0;
        end else begin
            io_phase_prev <= (io_phase == 2'b11);
        end
    end

    // Latch operands on each appropriate phase
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a0_latch    <= 16'h0;
            a1_latch    <= 16'h0;
            a2_latch    <= 16'h0;
            a3_latch    <= 16'h0001;  // GF16 identity for spare lane
            b0_latch    <= 16'h0;
            b1_latch    <= 16'h0;
            b2_latch    <= 16'h0;
            b3_latch    <= 16'h0001;  // GF16 identity for spare lane
            job_id_latch<= 8'h00;
        end else if (ena) begin
            case (io_phase)
                2'b00: begin
                    // Low phase: a0 low byte, b0 low byte
                    a0_latch[7:0]  <= a_byte;
                    b0_latch[7:0]  <= b_byte;
                end
                2'b01: begin
                    // High phase: a0 high byte, b0 high byte; also a1/b1
                    a0_latch[15:8] <= a_byte;
                    b0_latch[15:8] <= b_byte;
                    // a1, b1: use replicated bytes for 4-lane feed
                    a1_latch       <= {a_byte, a_byte};
                    b1_latch       <= {b_byte, b_byte};
                end
                2'b10: begin
                    // Extended phase: a2/b2 from io, a3/b3 from nibbles
                    a2_latch       <= {a_byte, a_byte};
                    b2_latch       <= {b_byte, b_byte};
                    a3_latch       <= {4'h0, a_byte[7:4], a_byte[3:0], 4'h1};
                    b3_latch       <= {4'h0, b_byte[7:4], b_byte[3:0], 4'h1};
                    job_id_latch   <= b_byte;  // capture job id in phase 2
                end
                2'b11: begin
                    // Trigger phase — no new latch; will fire COMPUTE
                end
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Packet sequencer FSM
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            pkt_seq     <= 4'd0;
            pkt_valid   <= 1'b0;
            pkt_reg     <= {`TRN_PKT_W{1'b0}};
            result_reg  <= 16'h0;
            result_valid_r <= 1'b0;
            rcpt_checksum_r <= 8'h0;
            rcpt_job_id_r   <= 8'h0;
            rcpt_tile_id_r  <= 2'h0;
            rcpt_valid_r    <= 1'b0;
        end else begin

            // Capture RESULT/RECEIPT from tile
            if (tile_out_valid && tile_out_ready) begin
                if (`TRN_PKT_OP(tile_out_pkt) == `TRN_OP_RESULT) begin
                    result_reg     <= `TRN_PKT_PAYLOAD(tile_out_pkt);
                    result_valid_r <= 1'b1;
                end
                if (`TRN_PKT_OP(tile_out_pkt) == `TRN_OP_RECEIPT) begin
                    rcpt_checksum_r <= `TRN_RCPT_PKT_CHECKSUM(tile_out_pkt);
                    rcpt_job_id_r   <= `TRN_RCPT_PKT_JOB_LO(tile_out_pkt);
                    rcpt_tile_id_r  <= `TRN_RCPT_PKT_TILE(tile_out_pkt);
                    rcpt_valid_r    <= 1'b1;
                end
            end

            case (state)
                S_IDLE: begin
                    pkt_valid <= 1'b0;
                    if (trigger_compute) begin
                        pkt_seq  <= 4'd0;
                        state    <= S_LOAD_LO;
                    end
                end

                S_LOAD_LO: begin
                    // Advance through packet sequence
                    if (!pkt_valid || pkt_ready) begin
                        pkt_valid <= 1'b1;
                        case (pkt_seq)
                            4'd0:  pkt_reg <= `TRN_MK_PKT(`TRN_OP_LOAD_JOB,  2'd0, 2'd3, 4'd0, {8'h0, job_id_latch});
                            4'd1:  pkt_reg <= `TRN_MK_PKT(`TRN_OP_LOAD_A,    2'd0, 2'd3, 4'd0, a0_latch);
                            4'd2:  pkt_reg <= `TRN_MK_PKT(`TRN_OP_LOAD_A,    2'd0, 2'd3, 4'd1, a1_latch);
                            4'd3:  pkt_reg <= `TRN_MK_PKT(`TRN_OP_LOAD_A,    2'd0, 2'd3, 4'd2, a2_latch);
                            4'd4:  pkt_reg <= `TRN_MK_PKT(`TRN_OP_LOAD_A,    2'd0, 2'd3, 4'd3, a3_latch);
                            4'd5:  pkt_reg <= `TRN_MK_PKT(`TRN_OP_LOAD_B,    2'd0, 2'd3, 4'd0, b0_latch);
                            4'd6:  pkt_reg <= `TRN_MK_PKT(`TRN_OP_LOAD_B,    2'd0, 2'd3, 4'd1, b1_latch);
                            4'd7:  pkt_reg <= `TRN_MK_PKT(`TRN_OP_LOAD_B,    2'd0, 2'd3, 4'd2, b2_latch);
                            4'd8:  pkt_reg <= `TRN_MK_PKT(`TRN_OP_LOAD_B,    2'd0, 2'd3, 4'd3, b3_latch);
                            4'd9:  pkt_reg <= `TRN_MK_PKT(`TRN_OP_COMPUTE,   2'd0, 2'd3, 4'd0, 16'h0);
                            4'd10: begin
                                pkt_reg <= `TRN_MK_PKT(`TRN_OP_READ_RES, 2'd0, 2'd3, 4'd0, 16'h0);
                                state   <= S_WAIT;
                            end
                            default: begin
                                pkt_valid <= 1'b0;
                                state     <= S_IDLE;
                            end
                        endcase
                        if (pkt_seq != 4'd10)
                            pkt_seq <= pkt_seq + 4'd1;
                    end
                end

                S_COMPUTE: begin
                    // Unused state — kept for FSM completeness
                    state <= S_IDLE;
                end

                S_WAIT: begin
                    // Clear the last packet once consumed
                    if (pkt_valid && pkt_ready) begin
                        pkt_valid <= 1'b0;
                    end
                    // Return to IDLE once result arrives
                    if (result_valid_r) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Instantiate ONE trinity_gf16_tile (TILE_ID=0, DOT_WIDTH=4)
    // ---------------------------------------------------------------
    trinity_gf16_tile #(
        .TILE_ID   (2'b00),
        .DOT_WIDTH (4)
    ) u_nano_tile (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_pkt    (pkt_reg),
        .in_valid  (pkt_valid),
        .in_ready  (pkt_ready),
        .out_pkt   (tile_out_pkt),
        .out_valid (tile_out_valid),
        .out_ready (tile_out_ready),
        .dbg_result(/* open */)
    );

    // ---------------------------------------------------------------
    // TG-Nano-07: zero-CPU / no-softcore assertion (grep-verified at commit)
    // (ensured by design — no softcore instantiation exists in this file)
    // ---------------------------------------------------------------

    // ---------------------------------------------------------------
    // Output assignment
    // ---------------------------------------------------------------
    assign uo_out  = result_reg[7:0];
    assign uio_out = result_reg[15:8];
    assign uio_oe  = 8'hFF;

    // Silence unused input lint warnings
    wire _unused_ok = &{1'b0, ena, ui_in[7:2], 1'b0};

endmodule
// Anchor: phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E · DOI 10.5281/zenodo.19227877
