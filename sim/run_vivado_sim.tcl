# ============================================================================
# run_vivado_sim.tcl -- Vivado (xsim) behavioral simulation of the reaction-time
#                       system, top module = tb/top_tb.v
#
# Creates (or re-opens) a simulation-only Vivado project, adds the RTL and the
# top-level testbench, runs behavioral simulation long enough to cover all three
# testbench scenarios (normal trial / false start / back-to-back trials), and
# populates + saves the waveform including key internal signals.
#
# Usage:
#   GUI (waveform opens live):
#       vivado -source run_vivado_sim.tcl
#   Batch (no GUI; waveform db + wcfg still saved):
#       vivado -mode batch -source run_vivado_sim.tcl
#   or from the Vivado Tcl console:
#       cd <this sim/ dir>; source run_vivado_sim.tcl
# ============================================================================

# ---- Configuration ---------------------------------------------------------
set proj_name  reaction_time_sim
set proj_dir   ./vivado_sim
# ZYBO (Zynq-7010). For Zybo Z7-20 use: xc7z020clg400-1
set part       xc7z010clg400-1
set rtl_dir    ../rtl
set tb_dir     ../tb
set sim_top    top_tb
set wcfg_file  [file normalize $proj_dir/${sim_top}_waves.wcfg]

# ---- Create or re-open the project -----------------------------------------
if {[file exists $proj_dir/$proj_name.xpr]} {
    puts "INFO: opening existing project $proj_dir/$proj_name.xpr"
    open_project $proj_dir/$proj_name.xpr
} else {
    puts "INFO: creating simulation project $proj_name in $proj_dir"
    create_project $proj_name $proj_dir -part $part -force
}

# ---- Add design sources ----------------------------------------------------
# All synthesizable RTL.
add_files -norecurse [glob $rtl_dir/*.v]

# Top-level testbench (simulation fileset only).
add_files -fileset sim_1 -norecurse $tb_dir/top_tb.v

# ---- Set the simulation top module -----------------------------------------
set_property top $sim_top [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sim_1

# Don't auto-run on launch; we set up the waveform first, then run explicitly.
set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]

# ---- Launch BEHAVIORAL simulation ------------------------------------------
# IMPORTANT: this testbench is a behavioral verification TB. It reaches into the
# DUT with hierarchical references (dut.ms_elapsed, dut.u_fsm.state, ...) for its
# assertions and waveform. Those RTL net names only exist in behavioral sim.
# A post-synthesis/post-implementation TIMING (or functional) simulation runs
# against the synthesized netlist, where those nets are optimized/renamed away --
# that is what produced errors like "'ms_elapsed' is not declared under prefix
# 'dut'" (snapshot top_tb_time_synth). Always run BEHAVIORAL sim for this TB, so
# -mode is pinned explicitly below rather than left to the project default.
puts "INFO: launching BEHAVIORAL simulation (top = $sim_top)"
launch_simulation -mode behavioral

# ---- Waveform setup --------------------------------------------------------
# Log the whole hierarchy so every signal is captured in the waveform database.
log_wave -r /*

# Top-level testbench / board I/O signals.
add_wave /top_tb/clk
add_wave /top_tb/btn_reset
add_wave /top_tb/btn_start
add_wave /top_tb/pmod_button_in
add_wave /top_tb/led_stimulus
add_wave /top_tb/led_false_start
add_wave /top_tb/seg
add_wave /top_tb/an

# Key internal signals (explicitly requested).
add_wave /top_tb/dut/u_fsm/state       ;# FSM state
add_wave /top_tb/dut/lfsr_value        ;# pseudo-random delay value
add_wave /top_tb/dut/ms_elapsed        ;# measured elapsed time (ms)

# A few more useful internals for debugging the control path.
add_wave /top_tb/dut/button_db         ;# debounced response button
add_wave /top_tb/dut/start_db          ;# debounced start button
add_wave /top_tb/dut/u_fsm/counter_start
add_wave /top_tb/dut/u_fsm/counter_stop
add_wave /top_tb/dut/u_fsm/display_enable

# Show the FSM state as an unsigned index (0=IDLE .. 5=FALSE_START).
catch { set_property radix unsigned [get_waves /top_tb/dut/u_fsm/state] }

# ---- Run long enough to cover all three scenarios --------------------------
# The testbench ends with $finish (~9 us). `run all` runs until that $finish,
# guaranteeing all three scenarios complete. (As an explicit floor, the three
# scenarios finish well within 20 us -- use `run 20us` if $finish is removed.)
puts "INFO: running simulation until testbench \$finish ..."
run all

# ---- Save the waveform -----------------------------------------------------
# Save the wave configuration so it can be re-opened later. The waveform
# database (.wdb) is written automatically by xsim.
save_wave_config $wcfg_file
puts "INFO: waveform configuration saved to $wcfg_file"

puts "INFO: simulation complete. In GUI mode the waveform viewer is populated;"
puts "INFO: in batch mode reopen with:  open_wave_database <...>.wdb ; open_wave_config $wcfg_file"
