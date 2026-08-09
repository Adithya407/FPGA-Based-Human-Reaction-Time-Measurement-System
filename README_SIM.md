# Simulation Status

Tracks the simulation status of each RTL module as it's developed. Update this
table when a module's testbench is added, run, or passes.

Status legend: Not Started | In Progress | Passing | Failing

| Module | RTL File | Testbench | Status | Notes |
|---|---|---|---|---|
| FSM | rtl/fsm_controller.v | tb/fsm_controller_tb.v | Passing | 6-state control FSM; normal + false-start + start-button-exit paths verified |
| LFSR | rtl/lfsr.v | tb/lfsr_tb.v | Passing | 8-bit Fibonacci, poly x^8+x^6+x^5+x^4+1; period 255 verified, never stuck at 0x00 |
| Synchronous Counter | rtl/counter.v | tb/counter_tb.v | Passing | 1 ms tick from 125 MHz (CLKS_PER_MS param), 10-bit saturating ms, start/stop/done; 6 checks pass |
| Debounce | rtl/debounce.v | tb/debounce_tb.v | Passing | 2-FF sync + stability counter (STABLE_COUNT param, ~10ms @125MHz); bounces rejected, edges propagate in window+2 |
| BCD Converter | rtl/bcd_converter.v | tb/bcd_converter_tb.v | Passing | Double-dabble, binary->3 BCD digits, clamps >999; all 0..999 verified |
| Seven-Segment Driver | rtl/seven_seg_driver.v | tb/seven_seg_driver_tb.v | Passing | Multiplexed 3-digit, ~1kHz/digit @125MHz; encoding 0-9 + one-hot mux verified |
| Top-Level Integration | rtl/top.v | tb/top_tb.v | Passing | Wires all 6 modules; comprehensive TB: normal trial (display readback), false start, back-to-back re-arm |

## Simulation Tools

- **ModelSim:** `sim/run_modelsim.do` — compiles/runs every module TB + top_tb (verified working).
- **Vivado (xsim):** `sim/run_vivado_sim.tcl` — project-mode script; creates/opens a sim-only project, sets `top_tb` as sim top, runs behavioral sim until `$finish` (covers all 3 scenarios), adds top-level + key internal signals (FSM state, lfsr_value, ms_elapsed) to the waveform and saves a `.wcfg`. Run GUI: `vivado -source sim/run_vivado_sim.tcl`; batch: `vivado -mode batch -source sim/run_vivado_sim.tcl`.
  - **Must be run as BEHAVIORAL simulation** (the script pins `launch_simulation -mode behavioral`). The testbench uses hierarchical references into DUT internals (`dut.ms_elapsed`, `dut.u_fsm.state`); these RTL nets don't exist in a post-synthesis/post-implementation timing or functional sim, which fails with e.g. `'ms_elapsed' is not declared under prefix 'dut'`. In the GUI, use *Run Simulation → Run Behavioral Simulation* (not post-synthesis).

## Log

- 2026-08-08: Project directory structure created (rtl/, tb/, sim/, constraints/, docs/). No modules implemented yet.
- 2026-08-08: LFSR (rtl/lfsr.v) + testbench added. Simulated in ModelSim (Intel FPGA Edition 2020.1): both checks pass — never stuck at 0x00 over 300 cycles, maximal-length period of 255 confirmed.
- 2026-08-08: Counter (rtl/counter.v) + testbench added. Simulated in ModelSim: all 6 checks pass — elapsed-ms matches expected across exact/non-exact tick boundaries, done/running flags correct, count holds after stop. TB overrides CLKS_PER_MS=10 for speed; RTL default is 125000 (125 MHz -> 1 ms).
- 2026-08-09: Debounce (rtl/debounce.v) + testbench added. Simulated in ModelSim: all checks pass — bouncy pulses shorter than the window never disturb the output; clean rising/falling edges propagate after exactly window+2 clocks (STABLE_COUNT + 2-FF sync). TB overrides STABLE_COUNT=20 for speed; RTL default is 1250000 (~10 ms @ 125 MHz).
- 2026-08-09: BCD converter (rtl/bcd_converter.v) + testbench added. Simulated in ModelSim: exhaustive check of all 0..999 passes, plus clamp-to-999 for out-of-range inputs (double-dabble, combinational).
- 2026-08-09: Seven-segment driver (rtl/seven_seg_driver.v) + testbench added. Simulated in ModelSim: segment encoding for digits 0-9 correct; multiplex scan verified (exactly one anode active, segment bus matches the active slot's digit). Refresh ~1kHz/digit @125MHz (REFRESH_CLKS param; TB uses 4 for speed). Active levels parameterized (SEG_ACTIVE_LOW / AN_ACTIVE_LOW) for common-anode vs common-cathode boards.
- 2026-08-09: FSM controller (rtl/fsm_controller.v) + testbench added. Simulated in ModelSim: all state transitions pass across the normal path (IDLE->RANDOM_WAIT->STIMULUS->MEASURING->RESULT->IDLE), the false-start path (early press -> FALSE_START -> IDLE), and RESULT exit via start_button. Outputs checked per state (counter_reset in IDLE, led+counter_start in STIMULUS, counter_stop pulse on response press, display_enable in RESULT, false_start_flag in FALSE_START). Random delay = MIN_WAIT_CLKS + lfsr_value*WAIT_SCALE; all timing parameterized (TB uses small values). Note: TB fix - counter_stop is a combinational pulse valid at the capturing posedge, sampled before the state-advancing edge.
- 2026-08-09: Top-level integration (rtl/top.v) added, wiring lfsr + 2x debounce + fsm_controller + counter + bcd_converter + seven_seg_driver. Compiles/elaborates clean (0 errors, 0 warnings). Notes: added btn_start input (FSM needs a trial-start button; not in the original port list) and led_false_start output; display anodes are blanked unless FSM display_enable is high; the FSM's lfsr_enable is unused since lfsr.v has no enable port (LFSR free-runs).
- 2026-08-09: Comprehensive top-level TB (tb/top_tb.v) added, replacing the initial smoke test. All 3 scenarios pass: (1) normal trial reconstructs the measured value from the multiplexed seg/an display outputs and confirms it equals the counter's ms and is plausible for the fixed wait; (2) false start -> FALSE_START LED -> clean IDLE; (3) two back-to-back trials with independent LFSR-randomized delays, verifying counter clear + display blank on re-arm (trial A=7ms, B=16ms). Includes a state-transition monitor ($display) and per-scenario PASS/FAIL. TB fixes (not RTL): sample ms_elapsed a few cycles after IDLE (synchronous counter reset); use if/else instead of a ternary for string $display.
- 2026-08-09: Constraints file (constraints/zybo_top.xdc) added with PLACEHOLDER ZYBO pin assignments for all top.v ports (clk + 125MHz create_clock, btn_reset/btn_start, led_stimulus/led_false_start, pmod_button_in, seg[6:0], an[2:0]). Every line commented with the ZYBO ref-manual signal name (sysclk/BTNx/LDx/JxN) and marked "verify" -- pins must be checked against the official ZYBO master XDC for the actual board revision before implementation. Removed the earlier empty stub constraints/zybo_z7.xdc (superseded).
