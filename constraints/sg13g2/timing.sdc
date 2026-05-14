# ============================================================================
# timing.sdc — IHP SG13G2 (130 nm BiCMOS) Timing Constraints
# Target: gf16_mesh_2x2_top  |  Wave-10a 2×2 GF16 Mesh
# Clock period: 4.00 ns (250 MHz)
# PDK: IHP SG13G2 (Apache-2.0 open-source)
# TRL-7 / 2027 MPW freeze target
#
# Author: Dmitrii Vasilev <admin@t27.ai>
# SPDX-License-Identifier: Apache-2.0
# ============================================================================

# ----------------------------------------------------------------------------
# 1. Primary clock
# ----------------------------------------------------------------------------
create_clock -period 4.00 \
             -name clk \
             -waveform {0 2.0} \
             [get_ports clk]

# ----------------------------------------------------------------------------
# 2. Clock uncertainty (jitter + skew budget)
#    IHP SG13G2 CTS target: 150 ps skew + 50 ps jitter = 200 ps total
# ----------------------------------------------------------------------------
set_clock_uncertainty 0.20 [get_clocks clk]

# ----------------------------------------------------------------------------
# 3. Clock transition (typical SG13G2 drive strength estimate)
# ----------------------------------------------------------------------------
set_clock_transition 0.10 [get_clocks clk]

# ----------------------------------------------------------------------------
# 4. Input delays  (~25 % of 4 ns period = 1.00 ns)
#    Applied to all synchronous inputs except clk and rst_n
# ----------------------------------------------------------------------------
set INPUT_DELAY  1.00
set OUTPUT_DELAY 1.00

# Control / reset
set_input_delay  $INPUT_DELAY -clock clk [get_ports rst_n]

# Host injection interface
set_input_delay  $INPUT_DELAY -clock clk [get_ports host_in_pkt]
set_input_delay  $INPUT_DELAY -clock clk [get_ports host_in_valid]
set_input_delay  $INPUT_DELAY -clock clk [get_ports host_out_ready]

# NoC stub — North
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_north_flit_in]
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_north_req_in]
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_north_ack_in]

# NoC stub — South
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_south_flit_in]
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_south_req_in]
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_south_ack_in]

# NoC stub — East
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_east_flit_in]
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_east_req_in]
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_east_ack_in]

# NoC stub — West
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_west_flit_in]
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_west_req_in]
set_input_delay  $INPUT_DELAY -clock clk [get_ports noc_west_ack_in]

# ----------------------------------------------------------------------------
# 5. Output delays  (~25 % of 4 ns period = 1.00 ns)
# ----------------------------------------------------------------------------
# Host ejection interface
set_output_delay $OUTPUT_DELAY -clock clk [get_ports host_in_ready]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports host_out_pkt]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports host_out_valid]

# NoC stub — North
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_north_ack_out]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_north_flit_out]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_north_req_out]

# NoC stub — South
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_south_ack_out]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_south_flit_out]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_south_req_out]

# NoC stub — East
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_east_ack_out]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_east_flit_out]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_east_req_out]

# NoC stub — West
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_west_ack_out]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_west_flit_out]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports noc_west_req_out]

# Debug outputs (no strict timing — false path)
set_output_delay $OUTPUT_DELAY -clock clk [get_ports dbg_tile0_result]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports dbg_tile1_result]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports dbg_tile2_result]
set_output_delay $OUTPUT_DELAY -clock clk [get_ports dbg_tile3_result]

# ----------------------------------------------------------------------------
# 6. False paths
# ----------------------------------------------------------------------------
# Asynchronous reset — false path to all registers
set_false_path -from [get_ports rst_n]

# Debug observation outputs are not timing-critical
set_false_path -to [get_ports dbg_tile0_result]
set_false_path -to [get_ports dbg_tile1_result]
set_false_path -to [get_ports dbg_tile2_result]
set_false_path -to [get_ports dbg_tile3_result]

# ----------------------------------------------------------------------------
# 7. Multicycle paths — NoC req/ack handshake stubs
#    The handshake protocol allows 2-cycle latency on the req/ack signal pair.
#    These paths cross tile boundaries; relax to 2-cycle multicycle setup.
# ----------------------------------------------------------------------------
set_multicycle_path 2 -setup \
    -from [get_ports {noc_north_req_in noc_south_req_in \
                      noc_east_req_in  noc_west_req_in}]

set_multicycle_path 2 -setup \
    -to   [get_ports {noc_north_req_out noc_south_req_out \
                      noc_east_req_out  noc_west_req_out}]

set_multicycle_path 1 -hold \
    -from [get_ports {noc_north_req_in noc_south_req_in \
                      noc_east_req_in  noc_west_req_in}]

set_multicycle_path 1 -hold \
    -to   [get_ports {noc_north_req_out noc_south_req_out \
                      noc_east_req_out  noc_west_req_out}]

# ----------------------------------------------------------------------------
# 8. Driving cell / load (SG13G2 process corner estimates)
#    sg13g2_iobuf assumed for IO; internal 16 fF pin capacitance estimate
# ----------------------------------------------------------------------------
set_driving_cell -lib_cell sg13g2_buf_4 \
                 -pin Y \
                 [all_inputs]

set_load 0.016 [all_outputs]

# ----------------------------------------------------------------------------
# 9. Operating conditions  (SG13G2 typical / slow corners)
# ----------------------------------------------------------------------------
# Uncomment when SG13G2 liberty files are loaded into the tool:
# set_operating_conditions -min typical -max slow

# ============================================================================
# End of timing.sdc
# ============================================================================
