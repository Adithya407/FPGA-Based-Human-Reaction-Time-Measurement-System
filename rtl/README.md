# rtl/

Synthesizable Verilog source for the reaction-time measurement system.

Planned modules (see top-level [README.md](../README.md)):

- `fsm.v` — top-level control FSM (idle, random delay, stimulus, measurement, result, false-start reset)
- `lfsr.v` — pseudo-random delay generator
- `counter.v` — synchronous elapsed-time counter
- `debounce.v` — PMOD push-button debouncer
- `seven_seg.v` — seven-segment display driver
- `top.v` — top-level module tying the above together, targeting the ZYBO (Zynq-7000)

Only synthesizable code belongs here — no testbenches or simulation-only constructs.
