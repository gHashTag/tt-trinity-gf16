# constraints.sdc — TRI-1 MAX (tt_um_trinity_max) timing constraints
# ICA-M-006 FIX (W15-TT-E, 2026-05-15)
# R-SI-4: clock_hz = 50_000_000 (20 ns period, no PLL inside user logic)
# phi^2 + phi^-2 = 3 · Wave-24 · EPIC #61 W15-TT-E · DOI 10.5281/zenodo.19227877

# Primary clock: TT board 50 MHz
create_clock -name clk -period 20.0 [get_ports clk]

# Input/output delays (TT board typical: 4 ns in/out at 50 MHz)
set_input_delay  -clock clk -max 4.0 [all_inputs]
set_output_delay -clock clk -max 4.0 [all_outputs]

# Clock uncertainty (jitter + skew budget)
set_clock_uncertainty 0.5 [get_clocks clk]

# False paths on async reset (active-low, synchronous in user logic)
set_false_path -from [get_ports rst_n]
