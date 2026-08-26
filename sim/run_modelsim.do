# ModelSim simulation script
# Usage (from the sim/ directory):
#   vsim -c -do run_modelsim.do
#
# Each vsim uses -onfinish stop so a testbench's $finish ends only that
# simulation, not the whole batch session; every block below then runs.
#
# Add RTL/TB file pairs as modules are developed (see ../README_SIM.md).

quit -sim
if {[file exists work]} { vdel -all }
vlib work
vmap work work

# --- Structural primitives library (needed by every RTL module) -------------
# Compiled once into `work`; all modules below instantiate these building
# blocks (dffr, registerN, adderN, mux2N, eqN, geN, gtN, onehot_decoder, ...).
vlog ../rtl/primitives.v

# --- LFSR -------------------------------------------------------------------
vlog ../rtl/lfsr.v
vlog ../tb/lfsr_tb.v
vsim -c -onfinish stop work.lfsr_tb
run -all

# --- Counter ----------------------------------------------------------------
vlog ../rtl/counter.v
vlog ../tb/counter_tb.v
vsim -c -onfinish stop work.counter_tb
run -all

# --- Debounce ---------------------------------------------------------------
vlog ../rtl/debounce.v
vlog ../tb/debounce_tb.v
vsim -c -onfinish stop work.debounce_tb
run -all

# --- BCD converter ----------------------------------------------------------
vlog ../rtl/bcd_converter.v
vlog ../tb/bcd_converter_tb.v
vsim -c -onfinish stop work.bcd_converter_tb
run -all

# --- Seven-segment driver ---------------------------------------------------
vlog ../rtl/seven_seg_driver.v
vlog ../tb/seven_seg_driver_tb.v
vsim -c -onfinish stop work.seven_seg_driver_tb
run -all

# --- FSM controller ---------------------------------------------------------
vlog ../rtl/fsm_controller.v
vlog ../tb/fsm_controller_tb.v
vsim -c -onfinish stop work.fsm_controller_tb
run -all

# --- Top-level integration --------------------------------------------------
vlog ../rtl/top.v
vlog ../tb/top_tb.v
vsim -c -onfinish stop work.top_tb
run -all

# --- add further modules below ---------------------------------------------
# vlog ../rtl/<module>.v
# vlog ../tb/<module>_tb.v
# vsim -c -onfinish stop work.<module>_tb
# run -all
