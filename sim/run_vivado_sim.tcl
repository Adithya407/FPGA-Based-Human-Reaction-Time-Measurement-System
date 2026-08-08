# Vivado (non-project mode) simulation script
# Usage: vivado -mode batch -source run_vivado_sim.tcl
#
# Fill in RTL/TB file names as modules are added (see ../README_SIM.md).

# read_verilog ../rtl/<module>.v
# read_verilog -sv ../tb/<module>_tb.v

# set_property top <module>_tb [get_fileset sim_1]
# launch_simulation
# run all
