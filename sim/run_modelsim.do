# ModelSim simulation script
# Usage (from the sim/ directory):
#   vsim -c -do run_modelsim.do
#
# Add RTL/TB file pairs as modules are developed (see ../README_SIM.md).

quit -sim
if {[file exists work]} { vdel -all }
vlib work
vmap work work

# --- LFSR -------------------------------------------------------------------
vlog ../rtl/lfsr.v
vlog ../tb/lfsr_tb.v
vsim -c work.lfsr_tb
run -all

# --- Counter ----------------------------------------------------------------
vlog ../rtl/counter.v
vlog ../tb/counter_tb.v
vsim -c work.counter_tb
run -all

# --- Debounce ---------------------------------------------------------------
vlog ../rtl/debounce.v
vlog ../tb/debounce_tb.v
vsim -c work.debounce_tb
run -all

# --- BCD converter ----------------------------------------------------------
vlog ../rtl/bcd_converter.v
vlog ../tb/bcd_converter_tb.v
vsim -c work.bcd_converter_tb
run -all

# --- Seven-segment driver ---------------------------------------------------
vlog ../rtl/seven_seg_driver.v
vlog ../tb/seven_seg_driver_tb.v
vsim -c work.seven_seg_driver_tb
run -all

# --- FSM controller ---------------------------------------------------------
vlog ../rtl/fsm_controller.v
vlog ../tb/fsm_controller_tb.v
vsim -c work.fsm_controller_tb
run -all

# --- Top-level integration --------------------------------------------------
vlog ../rtl/top.v
vlog ../tb/top_tb.v
vsim -c work.top_tb
run -all

# --- add further modules below ---------------------------------------------
# vlog ../rtl/<module>.v
# vlog ../tb/<module>_tb.v
# vsim -c work.<module>_tb
# run -all
