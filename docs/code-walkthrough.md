# Code Walkthrough — Line by Line, Branch by Branch

A complete reading guide to every source file in
**FPGA-Based Human Reaction Time Measurement System**
(`github.com/Adithya407/FPGA-Based-Human-Reaction-Time-Measurement-System`),
covering all three branches: **`main`**, **`Struct_mod`**, and **`Option3`**.

> **How to read this.** Open the file being discussed side by side with this
> document. Each section gives the file's purpose, then a `Lines` → `What it does`
> table walking the file from top to bottom. Line numbers refer to the version of
> the file **on the branch named in the section heading**.

---

## Table of contents

1. [Branch map — what actually differs](#1-branch-map--what-actually-differs)
2. [System architecture (common to all branches)](#2-system-architecture-common-to-all-branches)
3. [Branch `main` — the behavioral design](#3-branch-main--the-behavioral-design)
4. [Branch `main` — the testbenches](#4-branch-main--the-testbenches)
5. [Branch `main` — scripts, constraints, docs](#5-branch-main--scripts-constraints-docs)
6. [Branch `Struct_mod` — the full structural rewrite](#6-branch-struct_mod--the-full-structural-rewrite)
7. [Branch `Option3` — the practical mixed style](#7-branch-option3--the-practical-mixed-style)
8. [Verification results](#8-verification-results)
9. [Observations, gotchas and known rough edges](#9-observations-gotchas-and-known-rough-edges)

---

## 1. Branch map — what actually differs

The three branches form a **straight line**, not a fork. Each is the previous one
plus one commit:

```
01e6254  Initial commit
7cf8cbe  Revise README with project details and objectives
af6bee0  Add complete RTL design and testbench suite
e2088df  Improve Vivado behavioral simulation flow       <-- tip of  main
7e3f03c  Refactor RTL into structural primitive netlists  <-- tip of  Struct_mod
ca867aa  Refactor FSM and BCD logic to behavioral RTL     <-- tip of  Option3
```

So `Struct_mod` contains everything on `main`, and `Option3` contains everything
on `Struct_mod`. The *design intent*, however, is three different **modelling
styles** describing the same hardware:

| | `main` | `Struct_mod` | `Option3` |
|---|---|---|---|
| Nickname in the repo docs | original / behavioral | **Option 1** | **Option 3** |
| `rtl/primitives.v` | absent | **present** | present |
| `rtl/lfsr.v` | behavioral | **structural** | structural |
| `rtl/debounce.v` | behavioral | **structural** | structural |
| `rtl/counter.v` | behavioral | **structural** | structural |
| `rtl/seven_seg_driver.v` | behavioral | **structural** | structural |
| `rtl/bcd_converter.v` | behavioral | structural | **behavioral again** |
| `rtl/fsm_controller.v` | behavioral | structural | **behavioral again** |
| `rtl/top.v` | netlist + behavioral glue | netlist + **structural glue** | netlist + structural glue |
| `tb/*.v` (7 files) | — | *identical to `main`* | *identical to `main`* |
| `constraints/`, `sim/run_vivado_sim.tcl` | — | *identical* | *identical* |
| `sim/run_modelsim.do` | 58 lines | **+5** (compiles `primitives.v` first) | same as `Struct_mod` |
| `docs/structural-modelling-option3.md` | absent | **present** | present |

**The key insight:** the *testbenches never change*. All three branches are
drop-in replacements for one another, verified by the same unmodified test
suite. That is the whole point of the exercise — three modelling styles, one
specification.

The exact file-level diff sizes:

```
main       -> Struct_mod   10 files changed, 1042 insertions(+), 278 deletions(-)
Struct_mod -> Option3       2 files changed,  119 insertions(+), 277 deletions(-)
```

`Option3`'s single commit reverts **only** `rtl/bcd_converter.v` and
`rtl/fsm_controller.v` back to their `main` (behavioral) content — byte for byte,
apart from the removed "STRUCTURAL implementation" comment paragraphs.

---

## 2. System architecture (common to all branches)

```
                  +---------+
   (free-running) |  lfsr   |--- lfsr_value[7:0] ---+
                  +---------+                       |
                                                    v
 pmod_button_in -->[debounce]--> button_db ---> +----------------+
 btn_start      -->[debounce]--> start_db ----> | fsm_controller |
                                                +----------------+
                                                  |  |  |  |   |
   led_stimulus <---------------- led_stimulus ---+  |  |  |   |
   led_false_start <--------- false_start_flag ------+  |  |   |
                                                        |  |   |
              counter_start / counter_stop / counter_reset  |   |
                                    |                       |   |
                                    v                       |   |
                              +-----------+                 |   |
   btn_reset -->[2FF sync]--> |  counter  |-- ms_elapsed[9:0]+   |
                              +-----------+       |             |
                                                  v             |
                                        +-----------------+     |
                                        |  bcd_converter  |     |
                                        +-----------------+     |
                                          h[3:0] t[3:0] o[3:0]  |
                                                  v             |
                                        +--------------------+  |
                                        | seven_seg_driver   |  |
                                        +--------------------+  |
                                            an_int[2:0] seg[6:0]|
                                                  |             |
                                     display_enable gates an <--+
                                                  v
                                              an[2:0], seg[6:0]
```

### The trial sequence (FSM states)

| State | Code | Meaning | Outputs asserted |
|---|---|---|---|
| `IDLE` | `3'd0` | Waiting for the user to arm a trial | `counter_reset`, `lfsr_enable` |
| `RANDOM_WAIT` | `3'd1` | Unpredictable pre-stimulus delay | `lfsr_enable` |
| `STIMULUS` | `3'd2` | One clock: light the LED, kick the counter | `led_stimulus`, `counter_start` |
| `MEASURING` | `3'd3` | LED on, counter running, awaiting the press | `led_stimulus` (+ `counter_stop` on the edge) |
| `RESULT` | `3'd4` | Show the measured time for ~3 s | `display_enable` |
| `FALSE_START` | `3'd5` | The user pressed too early | `false_start_flag` |

Transitions:

```
IDLE --start_rise--> RANDOM_WAIT --button_rise--> FALSE_START --timeout--> IDLE
                          |
                   timer >= rand_delay
                          v
                      STIMULUS --(always)--> MEASURING --button_rise--> RESULT
                                                                          |
                                                      start_rise OR timeout
                                                                          v
                                                                        IDLE
```

### Timing constants at the 125 MHz PL clock

| Parameter | Default | Meaning |
|---|---|---|
| `CLK_HZ` | `125_000_000` | ZYBO PL clock (8 ns period) |
| `DEBOUNCE_CLKS` | `1_250_000` | 10 ms button stability window |
| `CLKS_PER_MS` | `125_000` | one millisecond tick |
| `REFRESH_CLKS` | `41_667` | ~333 µs per digit slot → ~1 kHz per digit |
| `MIN_WAIT_CLKS` | `125_000_000` | 1.0 s minimum pre-stimulus delay |
| `WAIT_SCALE` | `1_000_000` | 8 ms extra delay per LFSR unit (0..255 → up to +2.04 s) |
| `RESULT_HOLD_CLKS` | `375_000_000` | ~3 s result display |
| `FALSE_HOLD_CLKS` | `125_000_000` | ~1 s false-start indication |

Every one of these is a **module parameter**, which is what lets the testbenches
shrink them (e.g. `CLKS_PER_MS = 5`) so a full three-scenario system simulation
finishes in ~9 µs of simulated time instead of ~10 s.

### Conventions used everywhere

- **Reset is synchronous and active-high** in every module (`rst` / `reset`).
- **Buttons are rising-edge events**, not levels — holding a button never
  re-triggers.
- **Segment bus ordering** is `seg[6]=a, seg[5]=b, seg[4]=c, seg[3]=d, seg[2]=e,
  seg[1]=f, seg[0]=g`, active-high (`1` = lit) by default.
- **Digit index** is `an[0]=ones, an[1]=tens, an[2]=hundreds`, one-hot,
  active-high by default. Both polarities are parameterised
  (`SEG_ACTIVE_LOW`, `AN_ACTIVE_LOW`).

---

## 3. Branch `main` — the behavioral design

Seven synthesizable modules. Each is written in classic RTL style: `always`
blocks, `case` statements, arithmetic operators.

### 3.1 `rtl/lfsr.v`

**40 lines.** An 8-bit Fibonacci Linear Feedback Shift Register that produces the
pseudo-random pre-stimulus delay. It free-runs continuously; the FSM samples
whatever value it happens to hold at the instant the user arms a trial, which is
what makes the delay genuinely unpredictable to the user.

| Lines | What it does |
|---|---|
| 1–11 | Header comment. Documents the primitive polynomial **x⁸ + x⁶ + x⁵ + x⁴ + 1**, the tap positions, and the critical warning that all-zero is a lock-up state for any LFSR. |
| 13–15 | `module lfsr #(parameter [7:0] SEED = 8'hFF)` — the reset value. Typed as `[7:0]` (not `integer`) so it can be used directly as a register reset value. Must never be `0`. |
| 16–21 | Ports: `clk`, `rst` (synchronous active-high), `load` (synchronous load enable), `seed_in[7:0]` (external seed), `value[7:0]` (current state, an output `wire`). |
| 23 | `reg [7:0] state;` — the actual shift register. |
| 26 | `wire feedback = state[7] ^ state[5] ^ state[4] ^ state[3];` — the Fibonacci tap XOR. Bits `[7],[5],[4],[3]` correspond to polynomial powers 8, 6, 5, 4 (a bit index `n` is power `n+1`). |
| 28–36 | The single clocked process, a 3-way priority chain: |
| 29–30 | `if (rst) state <= SEED;` — reset always wins and always loads a guaranteed non-zero value. |
| 31–33 | `else if (load) state <= (seed_in == 8'h00) ? SEED : seed_in;` — an external load, but with a **zero-seed guard**: loading `0` would freeze the LFSR forever, so a zero request is silently replaced with `SEED`. This is defensive design, not dead code. |
| 34–35 | `else state <= {state[6:0], feedback};` — the normal operation: shift left by one, with the feedback bit entering the LSB. |
| 38 | `assign value = state;` — expose the register. |

**Behaviour:** period 255 (all values 1..255, never 0). At 125 MHz the register
completes a full cycle every 2.04 µs, so a human's reaction-time-scale
uncertainty in *when* they press "start" translates to a completely
uncorrelated captured value.

### 3.2 `rtl/debounce.v`

**68 lines.** Two-stage button conditioning: metastability hardening, then
mechanical-bounce filtering.

| Lines | What it does |
|---|---|
| 1–18 | Header. Explains both stages and states the key timing fact: end-to-end latency from a clean edge to `btn_out` changing is **`STABLE_COUNT + 2` clocks** (2 for the synchronizer). The testbench asserts exactly this number. |
| 20–22 | `parameter integer STABLE_COUNT = 1250000` — the stability window, ~10 ms at 125 MHz. Parameterised purely so simulation can use `20`. |
| 23–27 | Ports: `clk`, `rst`, `btn_in` (raw, asynchronous), `btn_out` (declared `reg` because it is assigned in an `always` block). |
| 30 | `localparam integer CW = (STABLE_COUNT <= 1) ? 1 : $clog2(STABLE_COUNT);` — counter width. The ternary guards against `$clog2(1) == 0`, which would produce an illegal zero-width vector. This defensive idiom recurs in every counter in the project. |
| 33–43 | **Stage 1 — the 2-flip-flop synchronizer.** `sync_0` samples the asynchronous `btn_in` (and may go metastable); `sync_1` samples `sync_0` a clock later, by which time any metastability has almost certainly resolved. Both clear on reset. |
| 44 | `wire btn_sync = sync_1;` — a readable alias for the synchronized level. |
| 47 | `reg [CW-1:0] count;` — the stability timer. |
| 48–66 | **Stage 2 — the stability counter**, a 4-way priority chain: |
| 49–52 | `if (rst)` — clear both the counter and the output. |
| 53–56 | `else if (btn_sync == btn_out)` — the synchronized input already agrees with the output, so **nothing is pending**; hold the counter at zero. This branch is what rejects bounces: every glitch back to the current level resets the timer. |
| 57–61 | `else if (count == STABLE_COUNT[CW-1:0] - 1'b1)` — the input has disagreed with the output for the full window, so **accept the new level** (`btn_out <= btn_sync`) and clear the counter. |
| 62–65 | `else count <= count + 1'b1;` — the new level is holding so far; keep timing it. |

**Why this shape matters:** the counter only advances while the input *differs*
from the output. A 5 ms bounce train made of pulses each shorter than 10 ms never
accumulates enough consecutive disagreeing clocks, so `btn_out` never moves. The
testbench proves this directly.

### 3.3 `rtl/counter.v`

**72 lines.** The stopwatch: divides 125 MHz down to 1 ms ticks and counts them.

| Lines | What it does |
|---|---|
| 1–16 | Header. Documents the `start`/`stop`/`rst` protocol and, importantly, that the `ms` output **saturates rather than wraps** — a missing or very slow response must not alias down to a small, plausible-looking time. |
| 18–21 | Parameters `CLKS_PER_MS = 125000` and `MS_WIDTH = 10` (range 0..1023). |
| 22–29 | Ports. `ms`, `done` and `running` are all `reg` outputs. `done` goes high when a measurement finishes and stays high until the next `start`; `running` is high only while actively counting. |
| 32 | `PW` — prescaler width, with the same `$clog2` zero-width guard as the debouncer. |
| 33 | `PRESCALE_MAX = CLKS_PER_MS - 1` — terminal count for the divider. |
| 35 | `reg [PW-1:0] prescale;` — the clock divider. |
| 38 | `MS_MAX = {MS_WIDTH{1'b1}}` — the all-ones saturation value (1023 at the default width). |
| 40–70 | One clocked process, a 4-way **priority** chain. The priority order is the whole design: |
| 41–46 | `if (rst)` — clear everything: `running`, `done`, `ms`, `prescale`. |
| 47–53 | `else if (start && !running)` — begin a fresh measurement. The `!running` qualifier makes `start` a **level-safe** trigger: re-asserting it mid-measurement does nothing. Clears `ms`, `prescale` and `done` in the same cycle. |
| 54–59 | `else if (stop && running)` — freeze. Sets `done`, clears `running`. Placing this **above** the tick logic is deliberate and is called out in the comment: the stopping edge can never sneak in one extra millisecond. |
| 60–69 | `else if (running)` — the normal counting cycle. When `prescale` hits `PRESCALE_MAX`, wrap it to zero and increment `ms` — but only `if (ms != MS_MAX)`, which is the saturation guard. Otherwise just increment `prescale`. |

**Resolution note:** the measured value is `floor(elapsed_clocks / CLKS_PER_MS)`.
A 249.9 ms reaction reads as 249 ms. That's a deliberate 1 ms quantisation, far
below human reaction-time variance (~±20 ms).

### 3.4 `rtl/bcd_converter.v`

**50 lines.** Purely combinational binary → 3-digit BCD, via the classic
**double-dabble** (shift-and-add-3) algorithm.

| Lines | What it does |
|---|---|
| 1–11 | Header. Notes the clamp: >999 cannot fit in three BCD digits, and the counter *can* saturate to 1023, so the input is clamped first to keep the display from showing garbage. |
| 13–20 | `parameter integer IN_WIDTH = 10`; input `bin`, outputs `hundreds`, `tens`, `ones` (all `reg [3:0]`, driven from an `always @*`). |
| 22 | `integer i;` — the loop variable. Because this lives in an `always @*` block that fully unrolls at elaboration, it is synthesizable. |
| 24 | `reg [IN_WIDTH+11:0] shift;` — the scratch register. Layout: the binary value occupies the low `IN_WIDTH` bits, and three 4-bit BCD nibbles (12 bits) sit above it. |
| 27 | `wire [IN_WIDTH-1:0] value = (bin > 10'd999) ? 10'd999 : bin;` — the clamp. |
| 29–43 | The combinational process: |
| 30–31 | Zero the scratch register, then load the clamped value into its low bits. |
| 33–43 | Loop `IN_WIDTH` (10) times. Each iteration: |
| 35–40 | Apply the **"add 3 if ≥ 5"** correction to each of the three BCD nibbles independently. `shift[IN_WIDTH+0 +: 4]` is the ones nibble, `+4` the tens, `+8` the hundreds. The `+:` indexed part-select keeps this parameter-safe. Each `+ 4'd3` is a 4-bit add whose carry-out is discarded — harmless, because a nibble here is never above 9, so 9+3 = 12 still fits. |
| 42 | `shift = shift << 1;` — shift the whole word left, moving one more binary bit up into the BCD region. |
| 45–47 | Extract the three finished nibbles into the outputs. |

**Why "add 3 if ≥ 5" works:** shifting left doubles a nibble. A BCD digit ≥ 5
would double past 9 and need a decimal carry. Pre-adding 3 (half of the 6-unit
gap between binary-16 and decimal-10 wrapping) makes the subsequent doubling
produce the correct carry into the next nibble automatically.

**Note on ordering:** the three corrections read and write disjoint bit ranges,
so applying them sequentially in the loop body is equivalent to applying them in
parallel. This is exactly why the `Struct_mod` version can implement them as
three independent gate-level cells.

### 3.5 `rtl/seven_seg_driver.v`

**103 lines.** Time-multiplexes three BCD digits onto one shared segment bus.

| Lines | What it does |
|---|---|
| 1–20 | Header. Works through the refresh arithmetic: `REFRESH_CLKS = 41667` clocks per digit slot ≈ 333 µs; a full 3-digit scan ≈ 1 ms, so each digit refreshes ~1000×/s, comfortably above the ~60 Hz flicker-fusion threshold. Also documents the segment bit ordering and the two polarity parameters. |
| 22–26 | Parameters: `NUM_DIGITS`, `REFRESH_CLKS`, `SEG_ACTIVE_LOW`, `AN_ACTIVE_LOW`. The polarity parameters make the same RTL work with common-anode and common-cathode display modules. |
| 27–35 | Ports: `clk`, `rst`, the three BCD digit inputs, and the `an` / `seg` outputs (both `reg`). |
| 37–38 | `RW` and `DW` — refresh-counter and digit-index widths, with the usual `$clog2` guard. |
| 41–42 | `refresh_cnt` (within-slot timer) and `digit_idx` (which digit is currently lit). |
| 44–59 | **Scan timing.** On reset, both clear. When `refresh_cnt` reaches `REFRESH_CLKS-1`, wrap it and advance `digit_idx` — wrapping that back to 0 when it reaches `NUM_DIGITS-1`. Otherwise just increment `refresh_cnt`. Note `digit_idx` only moves on a slot boundary, never every clock. |
| 62–70 | **Digit selection.** A combinational `case (digit_idx)` picks `ones` (index 0), `tens` (1), or `hundreds` (2) into `cur_bcd`. The `default: cur_bcd = 4'd0;` covers `NUM_DIGITS > 3` configurations and prevents an inferred latch. |
| 73–89 | **`seg_decode` function** — the BCD→7-segment lookup, written as a `case` returning a 7-bit pattern. Read the constants against `abcdefg`: `4'd0 → 7'b1111110` lights a,b,c,d,e,f and leaves g dark, which draws a zero. `default: 7'b0000000` blanks the display for hex A–F, so an out-of-range nibble shows nothing rather than a nonsense glyph. |
| 92–96 | **One-hot anode generation.** `an_onehot` is zeroed then a single bit set by `an_onehot[digit_idx] = 1'b1;` — a variable bit-select on the left-hand side, which synthesizes to a decoder. |
| 98–101 | **Polarity application.** `an` and `seg` are conditionally inverted based on `AN_ACTIVE_LOW` / `SEG_ACTIVE_LOW`. Because the parameters are compile-time constants, the ternaries collapse to either wires or inverters — no runtime multiplexer. |

### 3.6 `rtl/fsm_controller.v`

**158 lines.** The brain: a six-state Moore machine with a small datapath.

| Lines | What it does |
|---|---|
| 1–30 | Header. Enumerates all six states and every transition, gives the delay formula, and notes that both button inputs are treated as **rising-edge events** because they arrive already debounced. |
| 32–37 | Parameters: `MS_WIDTH`, `MIN_WAIT_CLKS`, `WAIT_SCALE`, `RESULT_HOLD_CLKS`, `FALSE_HOLD_CLKS`. |
| 39–53 | Ports. Inputs: `clk`, `reset`, `button` (debounced response), `lfsr_value[7:0]`, `ms_elapsed`, `start_button`. Seven `reg` outputs — the control signals for the rest of the system. |
| 56–61 | State encoding as `localparam [2:0]`, values 0–5. This exact encoding is **contractual**: both `fsm_controller_tb.v` and `top_tb.v` re-declare it and compare against `dut.state` hierarchically, and `run_vivado_sim.tcl` adds `state` to the waveform as an unsigned index. |
| 63 | `reg [2:0] state, next_state;` — the classic two-process split. |
| 64 | `reg [31:0] timer;` — cycles spent in the current state. 32 bits is generous but necessary: `RESULT_HOLD_CLKS` alone is 375 million. |
| 65 | `reg [31:0] rand_delay;` — the latched random-wait target. |
| 66 | `reg [MS_WIDTH-1:0] result_ms;` — the latched reaction time. Captured but never driven to an output (the display reads `ms_elapsed` directly, since the counter holds its value after `stop`). |
| 68–71 | **Edge detection.** `button_prev` / `start_prev` are one-cycle delays; `button_rise = button & ~button_prev` is a classic single-cycle rising-edge pulse. This is what makes holding a button harmless. |
| 74–87 | **Process 1 — next-state logic** (combinational). `next_state = state;` first, so every unlisted case holds — no latch, no missing branch. Then a `case`: |
| 77 | `IDLE`: `start_rise` → `RANDOM_WAIT`. |
| 78–79 | `RANDOM_WAIT`: `button_rise` → `FALSE_START` (checked **first**, so an early press always wins); otherwise `timer >= rand_delay` → `STIMULUS`. |
| 80 | `STIMULUS`: unconditionally → `MEASURING`. This state exists for exactly one clock, purely to emit a clean one-cycle `counter_start` pulse. |
| 81 | `MEASURING`: `button_rise` → `RESULT`. |
| 82–83 | `RESULT`: `start_rise` **or** the hold timeout → `IDLE`. The `start_rise` path lets an impatient user skip the 3 s display. |
| 84 | `FALSE_START`: hold timeout → `IDLE`. |
| 85 | `default: next_state = IDLE;` — recovery from any illegal encoding. |
| 90–119 | **Process 2 — the sequential block.** On `reset`, everything clears. Otherwise: |
| 100–101 | Update the edge-detection history registers. |
| 104–105 | `if (state == IDLE && next_state == RANDOM_WAIT) rand_delay <= MIN_WAIT_CLKS + lfsr_value * WAIT_SCALE;` — latch the random delay at exactly the moment a trial is armed. Note this is a **transition-triggered** latch (checking both current and next state), not a state-triggered one. |
| 108–109 | Likewise latch `result_ms` on the `MEASURING → RESULT` transition. |
| 112–115 | **Timer management:** `if (state != next_state) timer <= 0; else timer <= timer + 1;` — the timer restarts on *every* state change, so each state's timeout is measured from its own entry. This one line is why a single 32-bit timer can serve three different timeouts. |
| 117 | Commit the state. |
| 122–156 | **Process 3 — Moore outputs** (combinational). All seven outputs are defaulted to `0` at the top (lines 123–129), then a `case (state)` raises only the ones this state needs. Defaulting first guarantees no inferred latches and makes each state's output set readable at a glance. |
| 132–135 | `IDLE`: `counter_reset` (wipe the previous measurement) and `lfsr_enable`. |
| 136–138 | `RANDOM_WAIT`: `lfsr_enable` only. |
| 139–142 | `STIMULUS`: `led_stimulus` + `counter_start`. |
| 143–147 | `MEASURING`: `led_stimulus`, plus `counter_stop` **gated on `button_rise`**. This is the one place the machine is not strictly Moore — the output depends on an input, not just the state. It is deliberate: `counter_stop` must be valid on the *same* clock edge that captures the response, so the counter freezes on exactly the right cycle. The FSM testbench has a comment explaining that it must therefore sample `counter_stop` *before* the state-advancing edge. |
| 148–150 | `RESULT`: `display_enable`. |
| 151–153 | `FALSE_START`: `false_start_flag`. |

**The delay formula in practice** (defaults): `rand_delay = 125_000_000 +
lfsr_value × 1_000_000`, i.e. **1.0 s to 3.04 s**, in 8 ms steps.

### 3.7 `rtl/top.v`

**227 lines.** The integration netlist — six sub-module instances plus a little
glue. Structurally this file is already a netlist even on `main`; only the glue
is behavioral.

| Lines | What it does |
|---|---|
| 1–27 | Header. Lists every sub-module and traces the dataflow. Lines 21–26 carry an honest **design note**: the originally specified port list had no way to *start* a trial, which the FSM requires, so `btn_start` was added as a required input, and `led_false_start` was exposed so an early press is visible. Both are flagged for remapping in the `.xdc`. |
| 29–48 | System parameters, all forwarded to the appropriate sub-module. This is what lets `top_tb` shrink the entire system's timebase from one place. |
| 50–60 | Board-level ports: `clk`, `btn_reset`, `btn_start`, `pmod_button_in` in; `led_stimulus`, `led_false_start`, `seg[6:0]`, `an[NUM_DIGITS-1:0]` out. |
| 66–69 | **Reset synchronizer.** `rst_sync_ff <= {rst_sync_ff[0], btn_reset};` is a 2-bit shift register; `rst = rst_sync_ff[1]`. Note these flops have **no reset of their own** — that is correct and intentional, since they *produce* the reset. |
| 74–91 | Declarations for every inter-module net, grouped and commented. `counter_done` and `counter_running` are explicitly noted as unused at the top level. |
| 100–108 | **`u_lfsr`** — `.load(1'b0)` and `.seed_in(8'h00)` tie off the load path: the LFSR simply free-runs from `SEED = 8'hFF`. |
| 113–120 | **`u_debounce_btn`** — conditions the PMOD response button into `button_db`. |
| 125–132 | **`u_debounce_start`** — a second, identical instance for `btn_start`. Reusing one parameterised module for both buttons is the cleanest thing in the file. |
| 139–159 | **`u_fsm`** — receives both debounced buttons, `lfsr_value` and `ms_elapsed`; drives the seven control wires. |
| 167–178 | **`u_counter`** — note `.rst(rst \| w_counter_reset)`: the counter is held cleared both by the system reset **and** whenever the FSM is in `IDLE`. This is the "re-arm" mechanism that `top_tb` scenario 3 verifies. |
| 183–190 | **`u_bcd`** — converts `ms_elapsed` continuously. It is purely combinational, so it tracks the counter live; no enable needed. |
| 195–208 | **`u_display`** — the multiplexed driver, producing `an_int` / `seg_int`. |
| 213–214 | LED outputs wired straight from the FSM. |
| 217 | `assign seg = seg_int;` — segments pass through untouched. |
| 222–223 | `AN_BLANK` — the *inactive* anode pattern, which depends on polarity: all-zeros for active-high select, all-ones for active-low. |
| 225 | `assign an = w_display_enable ? an_int : AN_BLANK;` — **display blanking.** The anodes are forced inactive unless the FSM says a result is ready. Blanking the anodes rather than the segments is the right choice: it works regardless of segment polarity and genuinely turns the digits off. |

**One dangling signal worth knowing about:** the FSM produces `lfsr_enable`, but
`lfsr.v` has no enable port, so `w_lfsr_enable` is left unconnected. Lines 89 and
96–98 document this explicitly — the LFSR free-runs by design, which gives
*better* randomness than gating it would.

---

## 4. Branch `main` — the testbenches

Seven testbenches, one per RTL module. They are **identical on all three
branches** — that is what makes the three modelling styles comparable. Common
house style:

- `` `timescale 1ns / 1ps `` at the top.
- A free-running clock from `initial clk = 0; always #4 clk = ~clk;` (8 ns → 125 MHz).
- Stimulus driven on `negedge`, sampled on `posedge` + `#1`. Driving and
  sampling on opposite edges avoids every race with the DUT's own flops.
- An `errors` counter, and a final `ALL TESTS PASSED.` / `N TEST(S) FAILED.`
  banner that the batch scripts grep for.

### 4.1 `tb/lfsr_tb.v` (92 lines)

| Lines | What it does |
|---|---|
| 13 | `NCYCLES = 300` — enough to observe a full 255-cycle period plus margin. |
| 15–24 | Signal and bookkeeping declarations: `stuck_count`, `first_value`, `period`. |
| 27–33 | DUT instance with `SEED(8'hFF)`. |
| 36–37 | 100 MHz clock (`#5` half-period) — cosmetic here, the LFSR is clock-rate agnostic. |
| 43–51 | Initialise, hold reset for two rising edges, release on a `negedge`. |
| 56–74 | The main loop. Each cycle: sample after `#1`, print the value in hex and binary, and run two checks: |
| 62–65 | **Lock-up check** — flag any occurrence of `8'h00`. |
| 69–73 | **Period measurement** — record the first post-reset value, then note the cycle index at which it recurs. |
| 77–80 | Report the lock-up result. |
| 82–87 | Report the period, distinguishing three outcomes: exactly 255 (pass), some other value (a note — the polynomial is not maximal-length), or never observed. |

**Result:** `PASS: LFSR never stuck at 0x00 over 300 cycles.` and
`PASS: maximal-length sequence confirmed (period = 255).`

> Note: this TB prints two `PASS:` lines rather than the `ALL TESTS PASSED.`
> banner the other six use. Batch scripts grepping only for that banner will
> show no summary line for `lfsr_tb` — the checks still ran and passed.

### 4.2 `tb/bcd_converter_tb.v` (70 lines)

| Lines | What it does |
|---|---|
| 19–24 | DUT with `IN_WIDTH(10)`. |
| 26–36 | `task check(value, eh, et, eo)` — drive `bin`, wait `#1` for the combinational logic to settle, compare all three digits with `!==` (4-state compare, so `X` fails rather than silently matching), and log any mismatch. |
| 42–47 | **Exhaustive sweep of 0..999.** Expected digits are computed in the testbench with plain integer division (`v/100`, `(v/10)%10`, `v%10`) — an independent reference model, not a copy of the DUT's algorithm. This is proper verification practice. |
| 51–52 | **Clamp checks** — `1000` and `1023` (the 10-bit maximum) must both display `999`. |
| 55–59 | A handful of named spot values for a readable log. |
| 62–65 | Final banner. |

### 4.3 `tb/debounce_tb.v` (136 lines)

| Lines | What it does |
|---|---|
| 18–19 | `STABLE_COUNT = 20` (sim-only) and `EXPECT_LAT = STABLE_COUNT + 2` — the **exact** predicted latency, including the two synchronizer flops. |
| 43–55 | `task drive_and_expect(lvl, cyc, exp)` — hold `btn_in` at `lvl` for `cyc` clocks while asserting `btn_out` stays at `exp` the whole time. |
| 58–67 | `task measure_latency(lvl, target, n)` — set the input, then count clocks until the output reaches `target`. |
| 78 | **Phase 1** — idle low, output must stay low. |
| 83–89 | **Phase 2 — bouncy rising edge.** Five alternating 8-clock pulses. Since 8 < 20, `btn_out` must never move. Line 89 settles low so the counter is fully cleared before the clean edge. |
| 92–100 | **Phase 3 — clean rising edge.** Measure the latency and assert it equals exactly 22 clocks. Not "roughly" — exactly. |
| 103 | Hold high; the output must stay high. |
| 106–112 | **Phase 4 — bouncy falling edge**, the mirror of phase 2. |
| 115–123 | **Phase 5 — clean falling edge**, latency asserted exactly again. |

This is the most rigorous testbench in the suite: it pins the timing to the
clock, not to a tolerance band.

### 4.4 `tb/counter_tb.v` (131 lines)

| Lines | What it does |
|---|---|
| 20 | `CLKS_PER_MS = 10` — one simulated "millisecond" is 10 clocks. |
| 52–86 | `task run_and_check(ncycles)`: |
| 55 | `expected = ncycles / CLKS_PER_MS` — integer division, matching the DUT's floor behaviour. |
| 58–60 | Synchronous reset. |
| 63–65 | One-clock `start` pulse. |
| 68 | `repeat (ncycles) @(posedge clk);` — run for exactly N clocks. |
| 71–74 | One-clock `stop` pulse, then settle. |
| 76–84 | Check all three outputs at once: `ms` equals expected, `done` is high, `running` is low. |
| 95–99 | Five cases chosen to probe the boundaries: `50`→5 ms (exact multiple), `123`→12 ms (non-multiple, proves truncation), `10`→1 ms (exactly one tick), **`9`→0 ms (just under one tick — the off-by-one trap)**, `1000`→100 ms. |
| 102–120 | **Hold-after-stop test.** Run 30 clocks (3 ms), stop, idle 40 more clocks, then confirm `ms` is still 3 and `running` is still low. This proves the frozen value survives, which the display depends on. |

### 4.5 `tb/seven_seg_driver_tb.v` (143 lines)

| Lines | What it does |
|---|---|
| 17–18 | `NUM_DIGITS = 3`, `REFRESH_CLKS = 4` — a tiny slot so a full scan is 12 clocks. |
| 49–65 | `function exp_seg` — a reference copy of the segment encoding. (It mirrors the DUT's table, so it verifies the multiplexing and wiring rather than independently re-deriving the glyphs.) |
| 68–75 | `function ones_count` — counts set bits in the anode bus, used for the one-hot assertion. |
| 84–94 | **Test 1 — encoding.** Set all three digits to the same value `d` and check the segment bus shows `d`'s pattern, for `d = 0..9`. |
| 98–99 | **Test 2 setup** — three *distinct* digits (ones=4, tens=5, hundreds=6) and a reset pulse to restart the scan cleanly. |
| 102–131 | Watch across two full scans plus margin. Every clock, assert two things: |
| 106–110 | `ones_count(an) == 1` — **exactly one anode active**. A driver that lit two digits at once would produce a ghosted display; this catches it. |
| 112–130 | Determine which anode is active, then assert the segment bus matches *that position's* digit. This is the real multiplexing correctness check: right digit, right slot, every clock. |

### 4.6 `tb/fsm_controller_tb.v` (220 lines)

| Lines | What it does |
|---|---|
| 17–21 | Tiny timing: `MIN_WAIT_CLKS=5`, `WAIT_SCALE=2`, `RESULT_HOLD_CLKS=8`, `FALSE_HOLD_CLKS=6`. |
| 24–25 | The state encoding, **re-declared locally**. It must match the DUT — a hard interface contract also spelled out in `docs/structural-modelling-option3.md`. |
| 65–75 | `function sname` — maps a state code to a readable string for logging. |
| 77–88 | `task expect_state(s)` — asserts `dut.state !== s` fails. Note the **hierarchical reference** `dut.state`: this reaches inside the DUT, which is why every branch must keep a 3-bit net literally named `state`. |
| 91–104 | `task wait_for_state(s)` — spin until the DUT reaches `s`, with a 1000-cycle guard so a broken FSM produces a timeout message instead of hanging the simulation. |
| 107–120 | `pulse_start` / `pulse_button` — one-cycle rising-edge pulses. |
| 127 | `lfsr_value = 8'd3` → `rand_delay = 5 + 3×2 = 11` cycles. |
| 128 | `ms_elapsed = 10'd250` — a stand-in for the counter, since this TB tests the FSM in isolation. |
| 131–135 | Reset, confirm `IDLE`, confirm `counter_reset` is asserted. |
| 142–177 | **Normal path.** Start → `RANDOM_WAIT`; wait out the delay → `STIMULUS` (checking `led_stimulus` and `counter_start`); one clock → `MEASURING`; then the subtle part: |
| 164–167 | **`counter_stop` is checked before the state-advancing edge.** The comment (lines 160–163) explains why: `counter_stop` is combinational and only valid while still in `MEASURING` with `button_rise` high. Sampling it after the edge would find it already low and report a spurious failure. This is a real lesson about verifying Mealy-flavoured outputs. |
| 168–173 | Advance, release the button, confirm `RESULT` and `display_enable`. |
| 176–177 | Confirm the hold timeout returns to `IDLE`. |
| 184–197 | **False-start path.** Start, wait two cycles (well short of 11), press → must land in `FALSE_START` with `false_start_flag` set, then time out to `IDLE`. |
| 202–209 | **Third path:** exiting `RESULT` early via `start_button` rather than the timeout. |

### 4.7 `tb/top_tb.v` (305 lines)

The system-level testbench, and the most interesting file in the suite.

| Lines | What it does |
|---|---|
| 27–35 | Shrunk system timing: `DEBOUNCE_CLKS=4`, `CLKS_PER_MS=5`, `REFRESH_CLKS=4`, `MIN_WAIT_CLKS=40`, `RESULT_HOLD_CLKS=150`, `FALSE_HOLD_CLKS=25`. Note `MIN_WAIT_CLKS=40` is chosen to be **much larger than the debounce latency**, so a "press early" in scenario 2 is genuinely early. |
| 55–74 | DUT instance driven only through **real board pins** — `btn_reset`, `btn_start`, `pmod_button_in`, and the LED/display outputs. No internal pokes for stimulus. |
| 96–110 | `function seg_to_digit` — the **inverse** segment decoder. This is how the TB reads the display the way a human would. |
| 114–124 | **State-change monitor.** Every clock, if `dut.u_fsm.state` differs from the previous value, print the transition. `mon_en` suppresses the `X → IDLE` reset noise. This produces a readable trace of the whole run. |
| 127–132 | `task check(cond, msg)` — the assertion helper. |
| 135–147 | `wait_for_state`, with an 8000-cycle guard. |
| 150–166 | `press_start` / `press_button` — hold the raw pin high for `DEBOUNCE_CLKS + 4` clocks, release, then wait the same again. This models a **real physical press**, long enough to clear debouncing. |
| 170–189 | **`task read_display(value)` — the heart of the testbench.** It scans the multiplexed display for three full refresh cycles; on every clock it decodes `seg` and records the digit against whichever anode is active. Then `value = h*100 + t*10 + o`. It also warns if a digit slot was never sampled. This verifies the *entire* output chain — counter → BCD → 7-seg → multiplexer → blanking — end to end, through the actual pins. |
| 193–224 | **`task run_normal_trial(meas_wait, measured)`** — one complete trial: press start, confirm `RANDOM_WAIT` with the LED off, wait for `MEASURING` with the LED on, wait `meas_wait` clocks as the simulated "reaction", press, confirm `RESULT`, then read the display and check it two ways: |
| 216 | `measured === dut.ms_elapsed` — the display must agree with the counter. |
| 219–222 | The value must fall inside a plausible band computed from `meas_wait` plus debounce/start latency. A band rather than an exact number, because the button press has real debounce latency. |
| 241–251 | **Scenario 1 — normal trial.** Confirms reset lands in `IDLE`, the display is blanked in `IDLE`, runs a 60-clock trial, then confirms the `RESULT` hold expires back to `IDLE`. |
| 254–270 | **Scenario 2 — false start.** Press start, then press the response button immediately. Confirms `FALSE_START`, `led_false_start` high, `led_stimulus` low, then a clean return to `IDLE` with the LED cleared and the display blanked. |
| 273–295 | **Scenario 3 — back-to-back trials.** Runs trial A (30-clock wait) and trial B (75-clock wait). Between them (lines 283–285) it verifies the **re-arm**: `dut.ms_elapsed` is back to zero and the display is blank. The comment explains the 3-cycle wait — the counter clears via *synchronous* reset in `IDLE`, so the clear takes effect a couple of cycles after the state change. Line 293 then asserts `meas3 > meas2`, proving the two trials measured independently rather than latching a stale value. |
| 298–301 | Overall banner: `ALL SCENARIOS PASSED.` |

---

## 5. Branch `main` — scripts, constraints, docs

### 5.1 `sim/run_modelsim.do` (58 lines)

A ModelSim/QuestaSim batch script.

| Lines | What it does |
|---|---|
| 1–5 | Usage comment: `vsim -c -do run_modelsim.do` from the `sim/` directory. |
| 7–10 | `quit -sim`, delete any existing `work` library, then `vlib` / `vmap` a fresh one. Starting clean prevents stale-object confusion. |
| 12–52 | Seven identical blocks, one per module: `vlog` the RTL, `vlog` the TB, `vsim -c work.<tb>`, `run -all`. Order runs leaf modules first and `top_tb` last. |
| 54–58 | A commented template for adding further modules. |

> **Practical caveat:** each testbench ends with `$finish`, which in ModelSim
> terminates the whole batch session. In practice the later blocks may not run.
> `docs/structural-modelling-option3.md` §5 gives the robust alternative — compile
> everything once, then launch each testbench in its **own** `vsim` process:
> ```bash
> for tb in lfsr_tb counter_tb debounce_tb bcd_converter_tb \
>           seven_seg_driver_tb fsm_controller_tb top_tb; do
>   vsim -c -do "run -all; quit -f" work.$tb
> done
> ```
> That is the method used for the results in §8 of this document.

### 5.2 `sim/run_vivado_sim.tcl` (108 lines)

The Vivado (xsim) flow, and the file the `main` tip commit was written to fix.

| Lines | What it does |
|---|---|
| 1–17 | Header with three invocation modes: GUI (`vivado -source ...`), batch (`vivado -mode batch -source ...`), or from the Tcl console. |
| 20–27 | Configuration: project name, directory, **`part xc7z010clg400-1`** (ZYBO / Zynq-7010 — line 22 notes Zybo Z7-20 users need `xc7z020clg400-1`), source directories, `sim_top = top_tb`, and the waveform config path. |
| 30–36 | Re-open the project if it exists, otherwise create it. Makes the script idempotent. |
| 40 | `add_files -norecurse [glob $rtl_dir/*.v]` — a **glob**, which is why `Struct_mod` and `Option3` need no change here: `primitives.v` is picked up automatically. |
| 43 | Add `top_tb.v` to the `sim_1` fileset only, keeping it out of synthesis. |
| 46–48 | Set the simulation top and update the compile order. |
| 51 | `xsim.simulate.runtime = 0ns` — **don't auto-run on launch.** The script needs to set up the waveform first, then run explicitly, otherwise the early activity is not captured. |
| 54–63 | The important part. A long comment explains a real bug that was hit: this testbench uses hierarchical references (`dut.ms_elapsed`, `dut.u_fsm.state`), and those RTL net names **only exist in behavioral simulation**. A post-synthesis or post-implementation run optimises and renames them, producing `'ms_elapsed' is not declared under prefix 'dut'`. Line 63 therefore pins `launch_simulation -mode behavioral` explicitly rather than trusting the project default. |
| 67 | `log_wave -r /*` — log the entire hierarchy so nothing is missing from the waveform database. |
| 70–77 | Add the board-level signals to the wave view. |
| 80–82 | Add the three explicitly-requested internals: FSM `state`, `lfsr_value`, `ms_elapsed`. |
| 85–89 | Add further control-path internals for debugging: both debounced buttons, `counter_start`, `counter_stop`, `display_enable`. |
| 92 | `catch { set_property radix unsigned ... }` — display the state as 0–5. Wrapped in `catch` so a Vivado version that dislikes the call doesn't abort the script. |
| 94–99 | `run all` — runs until the testbench's own `$finish` (~9 µs), guaranteeing all three scenarios complete. The comment offers `run 20us` as an explicit floor if `$finish` is ever removed. |
| 102–108 | Save the `.wcfg` waveform configuration and print instructions for re-opening the `.wdb` later in batch mode. |

### 5.3 `constraints/zybo_top.xdc` (73 lines)

Pin constraints for the ZYBO.

| Lines | What it does |
|---|---|
| 1–24 | Header, and a prominent, repeated warning: **every `PACKAGE_PIN` is a placeholder** and must be verified against the official Digilent master XDC for the actual board revision. It notes that the original ZYBO and the Zybo Z7 (7010/7020) use different pins. It also documents that all PL I/O is 3.3 V → `LVCMOS33`, and gives the full port map. |
| 30 | `clk` → `L16` (sysclk). |
| 31 | `create_clock ... -period 8.000 -waveform {0 4.000}` — declares the 125 MHz clock. **This line is the real timing constraint**; without it the tools have nothing to close timing against. Unlike the pin numbers, the period is definitely correct. |
| 37–38 | `btn_reset` → `R18` (BTN0), `btn_start` → `P16` (BTN1). Active-high on ZYBO, matching the RTL. |
| 44–45 | `led_stimulus` → `M14` (LD0), `led_false_start` → `M15` (LD1). |
| 52 | `pmod_button_in` → `V15` (PMOD JC pin 1). |
| 63–69 | `seg[6:0]` → segments a..g across PMOD JD. Note the mapping is explicit and commented per line (`seg[6]` = a on JD9, down to `seg[0]` = g on JD1). |
| 71–73 | `an[0]` (ones) on JD10, `an[1]` (tens) and `an[2]` (hundreds) on PMOD JE — the segments consume all eight JD pins, so the remaining digit-selects spill onto the next header. |

Every single line carries a trailing `-- PLACEHOLDER, verify` comment. Take that
seriously before running implementation.

### 5.4 `.gitignore` (23 lines)

| Lines | What it does |
|---|---|
| 1–10 | ModelSim/Questa artefacts: the `work/` library, `transcript` files, `.wlf` waveform logs, `modelsim.ini`. |
| 12–23 | Vivado artefacts: `.jou` journals, `.log`, `.str`, `.Xil/`, `xsim.dir/`, `.pb`, `.wdb` waveform databases, and the `webtalk*` / `vivado*` files. |

Correctly scoped: it ignores generated output while keeping every source and
script. Note that `sim/vivado_sim/` (the project directory the Tcl script
creates) is covered only partially — the `.xpr` itself is not ignored.

### 5.5 `README.md`, `README_SIM.md`, and the directory READMEs

- **`README.md`** — course context (23ECE383 VLSI Design Laboratory, Team
  Latency, three members), a plain-language overview of what reaction time is and
  how the system measures it, six project objectives, the six system components,
  and the hardware/tools list.
- **`README_SIM.md`** — the most useful document in the repo for a reviewer. A
  status table (all seven modules **Passing**), a Simulation Tools section, and a
  detailed dated **Log** running 2026-08-08 → 2026-08-09, one entry per module.
  The log records not just what was added but what was *learned* — e.g. that
  `counter_stop` is a combinational pulse that must be sampled before the
  state-advancing edge, and that the Vivado TB must run behaviorally.
- **`rtl/README.md`** — describes the directory and lists planned modules.
  ⚠️ **Stale:** it still names `fsm.v` and `seven_seg.v`, whereas the actual files
  are `fsm_controller.v` and `seven_seg_driver.v`, and it does not mention
  `bcd_converter.v` or (on the later branches) `primitives.v`.
- **`tb/README.md`** — naming convention (`<module>_tb.v`) and a pointer to
  `README_SIM.md`. Same stale `fsm.v` example.
- **`docs/README.md`** — a three-line placeholder describing what belongs in
  `docs/`.

---

## 6. Branch `Struct_mod` — the full structural rewrite

> **Commit:** `7e3f03c` *Refactor RTL into structural primitive netlists*
> **Scope:** 10 files changed, +1042 / −278.

### 6.1 The idea and the house style

`Struct_mod` is **Option 1**: rebuild every RTL module as a *netlist* — wiring
together gate primitives and a small library of reusable blocks — instead of
describing behaviour procedurally. The rules, documented at the top of
`rtl/primitives.v` (lines 9–16):

1. **All logic** is realised with Verilog gate primitives (`and`, `or`, `xor`,
   `not`, `buf`, `xnor`) or by instantiating library blocks.
2. Continuous `assign` is used **only for pure net wiring** — aliases,
   concatenations, constant tie-offs — **never** for a logic or arithmetic
   operator.
3. **The single behavioural leaf is the D flip-flop** (`dffr`). A register is the
   natural atomic storage element, and modelling it behaviourally is standard
   practice even in strict structural design.

Everything else follows from those three rules.

### 6.2 `rtl/primitives.v` (257 lines) — new file

The component library. Nine modules, each small enough to verify by inspection.

#### `dffr` (lines 35–48) — D flip-flop, synchronous reset + clock enable

| Lines | What it does |
|---|---|
| 35–37 | `parameter RESET_VAL = 1'b0` — so registers can reset to non-zero (the LFSR needs this). |
| 38–43 | Ports: `clk`, `rst`, `en` (hold when low), `d`, `q`. |
| 44–47 | `if (rst) q <= RESET_VAL; else if (en) q <= d;` — **reset has priority over enable**, matching the behavioral modules' `if (rst) ... else if (...)` chains exactly. |

This is the only `always` block in the entire structural design.

#### `registerN` (lines 55–77) — N-bit register

| Lines | What it does |
|---|---|
| 56–57 | `WIDTH` and a `[WIDTH-1:0] RESET_VAL`. |
| 65–76 | A `generate for` loop instantiating one `dffr` per bit, each parameterised with `RESET_VAL[i]`. So a register's reset value is distributed bit-by-bit into the individual flops. |

#### `mux2` (lines 83–94) — 1-bit 2:1 multiplexer

Textbook gate-level AND-OR-invert form: `not(nsel, sel)`, `and(ta, a, nsel)`,
`and(tb, b, sel)`, `or(y, ta, tb)`. **Convention: `sel=0 → a`, `sel=1 → b`.**
Every mux instantiation in the design follows this, so read `.a()` as the
"else" input and `.b()` as the "then" input.

#### `mux2N` (lines 100–114) — N-bit 2:1 multiplexer

A `generate` array of `mux2`, sharing one `sel`.

#### `full_adder` (lines 120–133) — 1-bit full adder

Five gates: `xor(axb,a,b)`, `xor(sum,axb,cin)`, `and(t1,a,b)`,
`and(t2,axb,cin)`, `or(cout,t1,t2)`.

#### `adderN` (lines 139–163) — N-bit ripple-carry adder

| Lines | What it does |
|---|---|
| 148 | `wire [WIDTH:0] carry;` — one wider than the operands, holding the whole carry chain. |
| 149 | `buf (carry[0], cin);` — note: a `buf`, not an `assign`. Rule 2 in action. |
| 151–161 | A `generate` chain of `full_adder`s, each taking `carry[i]` and producing `carry[i+1]`. |
| 162 | `buf (cout, carry[WIDTH]);` |

**This one module is the workhorse.** Every increment in the design is an
`adderN` with `b = 0` and `cin = 1` (i.e. `x + 0 + 1`), and every `>=` comparison
is an `adderN` in disguise (see `geN`).

#### `eqN` (lines 170–190) — equality comparator

| Lines | What it does |
|---|---|
| 181–183 | Per-bit `xnor` → `biteq[i]` is 1 where the bits match. |
| 184 | `buf (chain[0], biteq[0]);` seeds the reduction. |
| 185–187 | An AND chain: `chain[i] = chain[i-1] & biteq[i]`. |
| 189 | `buf (eq, chain[WIDTH-1]);` — the final AND of all match bits. |

A linear AND chain rather than a balanced tree — simpler to read; synthesis will
rebalance it anyway.

#### `geN` (lines 197–219) — unsigned `a >= b`

The neatest trick in the library. Lines 207–211 invert `b`; lines 212–218 feed
`a + ~b + 1` (two's-complement `a − b`) into an `adderN`. The **carry-out is 1
exactly when `a >= b`**, so `ge` is wired straight to `.cout`. The `diff` sum is
declared and left unused — the comparison lives entirely in the carry.

#### `gtN` (lines 225–235) — unsigned `a > b`

Two lines: compute `ge_ba = (b >= a)`, then `not (gt, ge_ba)`. Since
`a > b ≡ ¬(b >= a)` over unsigned integers, one inverter suffices.

#### `onehot_decoder` (lines 243–257) — binary → one-hot

A `generate` loop where each output bit `k` is an `eqN` comparing `sel` against
the constant `k`. Exactly one line is high for `sel < OUT_WIDTH`; for an
out-of-range `sel`, **all** lines are low — a property the FSM relies on for
illegal-state recovery.

### 6.3 `rtl/lfsr.v` — structural (70 lines)

Same ports, same behaviour, rebuilt as a netlist.

| Lines | What it does |
|---|---|
| 11–14 | New comment paragraph declaring the structural approach. |
| 24 | `output wire [7:0] value` — was `wire` on `main` too, unchanged. |
| 27 | `wire [7:0] state;` — now a **wire**, driven by the register instance, not a `reg`. |
| 30–31 | `xor (feedback, state[7], state[5], state[4], state[3]);` — the same tap XOR, but as a 4-input gate primitive instead of the `^` operator. Verilog gate primitives accept arbitrary fan-in, which makes this a direct translation. |
| 34–35 | `assign shift_val = {state[6:0], feedback};` — **a legal `assign` under the house rules**, because concatenation is pure wiring, not a logic operator. |
| 38–39 | `eqN #(8) u_zero (.a(seed_in), .b(8'h00), .eq(seed_is_zero));` — the zero-seed test, formerly `seed_in == 8'h00`. |
| 42–48 | `mux2N u_seedmux` selects `load_val = seed_is_zero ? SEED : seed_in`. Remember the convention: `.a` is the sel=0 case (`seed_in`), `.b` is the sel=1 case (`SEED`). |
| 51–57 | `mux2N u_nextmux` selects `next_state = load ? load_val : shift_val`. |
| 60–66 | `registerN #(.WIDTH(8), .RESET_VAL(SEED))` with `en` tied to `1'b1` — always clocked. `RESET_VAL(SEED)` is what preserves the non-zero reset guarantee. |
| 68 | `assign value = state;` — pure wiring alias. |

Trace the three-way priority from `main`: reset is handled *inside* `registerN`
(highest), then `u_nextmux` picks load over shift. Identical priority, expressed
as structure rather than as an `if/else` chain.

### 6.4 `rtl/debounce.v` — structural (85 lines)

| Lines | What it does |
|---|---|
| 31 | `output wire btn_out` — changed from `reg` to `wire`, now driven by a `dffr`. **The port direction and name are unchanged**, which is what keeps the testbench working. |
| 37 | `localparam [CW-1:0] TERM = STABLE_COUNT[CW-1:0] - 1'b1;` — the terminal count precomputed as a sized constant, so the comparator has a clean constant operand. |
| 41–42 | The two synchronizer flops as explicit `dffr` instances. |
| 45 | `buf (btn_sync, sync_1);` — a buffer, not an `assign`. |
| 53 | `xnor (match, btn_sync, btn_out);` — 1-bit equality. This replaces `btn_sync == btn_out` in a single gate. |
| 54 | `eqN u_atwin (.a(count), .b(TERM), .eq(at_window));` — the window-elapsed test. |
| 59–60 | `or (clear_count, match, at_window);` — clear the counter when the level matches **or** the window has elapsed. This merges two separate `main` branches into one term. |
| 62–69 | `adderN` computes `count + 1` (as `count + 0 + 1`), then `mux2N` picks `clear_count ? 0 : count+1`. |
| 71–73 | The counter register, always enabled. |
| 77–79 | `not (not_match, match); and (out_en, at_window, not_match);` — the output flop's enable. |
| 81–83 | `dffr u_out (.en(out_en), .d(btn_sync), .q(btn_out));` — the output only updates when the window has elapsed *and* the level genuinely differs. |

**The elegant part:** `main` needed a 4-way `if/else if` priority chain. The
structural version reduces it to two boolean terms (`clear_count`, `out_en`) plus
the register's own reset priority. `match` having priority over `at_window` in
`main` is preserved by the `and` on line 79 — if the level already matches, the
output flop is disabled regardless of the counter.

### 6.5 `rtl/counter.v` — structural (130 lines)

The most instructive conversion, because it makes an implicit priority chain
explicit.

| Lines | What it does |
|---|---|
| 17–25 | A new comment block defining the three **mutually exclusive, priority-ordered events** that replace the `if/else if` chain: `c_start = start & ~running`; `c_stop = stop & running & ~c_start`; `c_run = running & ~c_start & ~c_stop`. |
| 36–38 | `ms`, `done`, `running` are now `wire` outputs. |
| 43 | `PRESCALE_MAX` typed as `[PW-1:0]` rather than `integer`. |
| 54–63 | The event derivation, gate by gate. Each `~` becomes a `not`, each `&` an `and`. Note the chain literally encodes the `main` priority: `c_stop` is qualified by `~c_start`, and `c_run` by both. |
| 69–71 | **`running`:** `d = c_start`, `en = c_start \| c_stop`. Elegant — the same signal that sets it (`c_start`) is also the data, so it becomes 1 on start and 0 on stop, and holds otherwise. |
| 77 | **`done`:** `d = c_stop`, sharing the same `run_en`. The inverse: 0 on start, 1 on stop. |
| 83–103 | **`prescale`:** `eqN` detects `PRESCALE_MAX`; `adderN` computes `+1`; `u_prun` picks `at_max_p ? 0 : +1`; `u_pmux` then forces 0 on `c_start`; enable is `c_start \| c_run`. Two chained muxes reproduce the nested `if` exactly. |
| 111–116 | **`ms` control:** `ms_is_max` (saturation test), inverted; `tick_pre = c_run & at_max_p`; `ms_tick = tick_pre & ms_not_max` — increment only on a prescaler rollover *and* only if not saturated; `ms_en = c_start \| ms_tick`. |
| 118–128 | The `ms` datapath: `adderN` for `+1`, `mux2N` to force 0 on `c_start`, `registerN` for storage. |

Read lines 111–116 against `main` lines 60–65 — the same three conditions, one as
nested `if`s, one as four gates.

### 6.6 `rtl/seven_seg_driver.v` — structural (170 lines)

| Lines | What it does |
|---|---|
| 21–26 | New structural comment. Note the honest caveat: *"Assumes `NUM_DIGITS >= 3`"*. |
| 40–41 | `an` and `seg` become `wire` outputs. |
| 46–47 | `R_MAX` and `D_MAX` as sized constants. |
| 53–64 | **Refresh prescaler.** `eqN` produces `slot_done` (high for one clock per slot); `adderN` + `mux2N` give `slot_done ? 0 : cnt+1`; the register is always enabled. |
| 69–81 | **Digit index.** Same pattern, except the register's **enable is `slot_done`** (line 80) — the index only advances on a slot boundary. On `main` this was expressed as a nested `if` inside the prescaler's rollover branch; here it is simply a clock enable, which is arguably clearer. |
| 86–89 | `onehot_decoder` converts `digit_idx` to `an_onehot`. This replaces `main`'s variable bit-select assignment (`an_onehot[digit_idx] = 1'b1`) with an explicit decoder. |
| 96–106 | **The input multiplexer, AND-OR style.** For each of the 4 BCD bits: AND each digit's bit with its own one-hot select, then OR the three results. Because `an_onehot` is genuinely one-hot, exactly one term survives. The comment on line 94 notes that slots ≥ 3 produce 0 — a blank digit — which is the graceful degradation for `NUM_DIGITS > 3`. |
| 111–112 | `seg7_decoder u_seg (.d(cur_bcd), .seg(seg_raw));` |
| 117–127 | **Polarity, as a compile-time `generate`-`if`.** For each output bit, instantiate either a `not` (active-low) or a `buf` (active-high). This is strictly better than `main`'s runtime ternary: the choice is resolved at elaboration, and it demonstrates the correct idiom for parameter-driven structure. |

#### `seg7_decoder` (lines 140–169) — gate-level sum-of-minterms

| Lines | What it does |
|---|---|
| 144–148 | Four inverters producing the complemented input literals `n3..n0`. |
| 150–160 | Ten 4-input ANDs producing minterms `m0..m9`, one per decimal digit. Each is commented with its binary code. For inputs 10–15, **every** minterm is 0. |
| 163–169 | Seven ORs, one per segment, each taking the minterms of the digits where that segment is lit. The comments name the digit sets, and they are worth checking against the `main` truth table: |

| Segment | Lit for digits | Cross-check against `main`'s table |
|---|---|---|
| `seg[6]` = a | 0,2,3,5,6,7,8,9 | dark for 1 (`0110000`) and 4 (`0110011`) ✓ |
| `seg[5]` = b | 0,1,2,3,4,7,8,9 | dark for 5 (`1011011`) and 6 (`1011111`) ✓ |
| `seg[4]` = c | all except 2 | 2 is `1101101`, bit 4 = 0 ✓ |
| `seg[3]` = d | 0,2,3,5,6,8,9 | dark for 1, 4, 7 ✓ |
| `seg[2]` = e | 0,2,6,8 | the four glyphs with a lower-left stroke ✓ |
| `seg[1]` = f | 0,4,5,6,8,9 | dark for 1,2,3,7 ✓ |
| `seg[0]` = g | 2,3,4,5,6,8,9 | dark for 0,1,7 — the three glyphs with no middle bar ✓ |

Because all-zero minterms give all-zero segments, the "blank for A–F" behaviour
of `main`'s `default` branch **falls out for free**, with no explicit default
needed.

### 6.7 `rtl/fsm_controller.v` — structural (261 lines)

The largest and most ambitious conversion.

| Lines | What it does |
|---|---|
| 31–37 | New structural comment. Note the critical line: *"the net `state` is kept for the testbench's hierarchical reference"* — the interface contract. |
| 54–60 | All seven outputs become `wire`. |
| 72–74 | The timing thresholds re-declared as `[31:0]` vectors so the comparators have sized constant operands. |
| 79–83 | **The state register:** `registerN #(.WIDTH(3), .RESET_VAL(IDLE))`, always enabled. The output net is named `state` — non-negotiable, since `fsm_controller_tb` and `top_tb` both reference `dut.state` / `dut.u_fsm.state`. |
| 86–87 | `onehot_decoder #(.SEL_WIDTH(3), .OUT_WIDTH(6)) u_sdec` produces `soh[5:0]`, where `soh[k]` is high iff `state == k`. **This one signal replaces every `case (state)` in the file.** |
| 92–98 | **Edge detection.** Two `dffr`s for the history, then `not` + `and` per signal — a literal gate translation of `button & ~button_prev`. |
| 103–108 | **Three 32-bit `geN` comparators**, one per timeout: `timer >= rand_delay`, `>= RESULT_HOLD_C`, `>= FALSE_HOLD_C`. Each is a 32-bit ripple-carry subtract internally — see the timing note in §9. |
| 114–115 | `ns_idle = start_rise ? RANDOM_WAIT : IDLE`. |
| 118–120 | `ns_rw` — **two chained muxes reproduce the `if/else if` priority.** The inner mux handles `tge_rand ? STIMULUS : RANDOM_WAIT`; the outer one overrides with `FALSE_START` when `button_rise`. Because the outer mux is applied last, `button_rise` wins — exactly matching `main`'s ordering, where the false-start check comes first. |
| 123–124 | `assign ns_stim = MEASURING;` — a constant tie-off, legal pure wiring. |
| 127–128 | `ns_meas = button_rise ? RESULT : MEASURING`. |
| 131–134 | `or (res_exit, start_rise, tge_result);` then `ns_result = res_exit ? IDLE : RESULT`. |
| 137–138 | `ns_false = tge_false ? IDLE : FALSE_START`. |
| 143–155 | **The next-state selection — a one-hot mux.** For each of the 3 state bits, AND each candidate's bit with its state's one-hot line, then OR all six. Since `soh` is one-hot, exactly one candidate passes. **And for an illegal state, `soh` is all-zero, so `next_state` becomes `3'b000 = IDLE`** — this reproduces `main`'s `default: next_state = IDLE;` as an emergent property rather than an explicit branch. |
| 160–174 | **The timer.** `eqN` compares `state` with `next_state`, inverted to give `state_changed`; `adderN` computes `+1`; `mux2N` picks `state_changed ? 0 : timer+1`. |
| 180–192 | **`rand_delay`.** `eqN` detects `next_state == RANDOM_WAIT`, ANDed with `soh[0]` (currently IDLE) to give `latch_rand` — the transition detector. Then `mul_const8` computes `lfsr_value × WAIT_SCALE`, `adderN` adds `MIN_WAIT_C`, and a `registerN` with `en = latch_rand` captures the result. |
| 198–204 | **`result_ms`** — same transition-detect pattern on `MEASURING → RESULT`. The comment notes it is captured for completeness but not driven to an output, matching `main`. |
| 210–216 | **The Moore outputs — seven single gates.** This is the payoff of the one-hot decode: |

```verilog
buf (counter_reset,    soh[0]);              // IDLE
or  (lfsr_enable,      soh[0], soh[1]);      // IDLE | RANDOM_WAIT
or  (led_stimulus,     soh[2], soh[3]);      // STIMULUS | MEASURING
buf (counter_start,    soh[2]);              // STIMULUS
and (counter_stop,     soh[3], button_rise); // MEASURING & response edge
buf (display_enable,   soh[4]);              // RESULT
buf (false_start_flag, soh[5]);              // FALSE_START
```

`main` needed a 35-line `case` with seven defaults to express this. Here the
output equations are directly readable — and line 214 makes the one non-Moore
output (`counter_stop`) unmistakably explicit.

#### `mul_const8` (lines 228–261) — shift-add constant multiplier

This module exists solely because `lfsr_value * WAIT_SCALE` uses the `*`
operator, which the house style forbids.

| Lines | What it does |
|---|---|
| 229–230 | `OUTW` (output width) and `K` (the compile-time constant multiplier). |
| 235–237 | `pp[0:7]` (partial products) and `acc[0:7]` (running sums) as unpacked arrays of nets. |
| 242–247 | **Partial products.** For each input bit `i`: `localparam KI = (K << i)`, then a `mux2N` selecting `a[i] ? KI : 0`. Because `K` is a constant, each shifted value is computed at elaboration — no barrel shifter needed. |
| 250–252 | Seed the sum chain: `acc[0] = pp[0] + 0`. |
| 253–257 | Accumulate: `acc[i] = acc[i-1] + pp[i]`, an `adderN` per stage. |
| 260 | `assign out = acc[7];` — pure wiring alias. |

Cost: eight 32-bit muxes and eight 32-bit ripple-carry adders. Functionally
correct, but far larger than what synthesis would infer from `*` — which is
precisely the trade-off `Option3` exists to avoid.

### 6.8 `rtl/top.v` — structural glue (unchanged instantiation, 6 edits)

The instance netlist was already structural on `main`. This commit converts the
remaining behavioral glue.

| Change | `main` | `Struct_mod` |
|---|---|---|
| **Reset synchronizer** | `reg [1:0] rst_sync_ff;` in an `always` block | Two `dffr` instances, `u_rst0` → `u_rst1`, each with **`.rst(1'b0)`** — they have no reset of their own, because they generate the reset. Faithful to `main`'s behaviour. |
| **LED outputs** | FSM drove `w_led_stimulus` / `w_false_start`, then `assign led_stimulus = w_led_stimulus;` | The FSM now drives the output ports **directly** (`.led_stimulus(led_stimulus)`), removing two wires and two `assign`s. |
| **Counter reset** | `.rst(rst \| w_counter_reset)` — an operator inside a port map | `or (counter_rst, rst, w_counter_reset);` then `.rst(counter_rst)`. |
| **Display blanking** | `assign an = w_display_enable ? an_int : AN_BLANK;` | `mux2N #(.WIDTH(NUM_DIGITS)) u_anblank (.a(AN_BLANK), .b(an_int), .sel(w_display_enable), .y(an));` — remember `.a` is the sel=0 case, so blanking is the default. |
| **Segment pass-through** | `assign seg = seg_int;` | Unchanged — a pure alias is legal under the house rules; only the comment gained "(alias)". |
| **Header comment** | — | Five new lines (18–22) explaining the structural glue. |

Every parameter, port and instance name is untouched — `u_fsm`, `ms_elapsed`,
`lfsr_value`, `button_db`, `start_db` all survive, so `top_tb` and
`run_vivado_sim.tcl` keep working.

### 6.9 `sim/run_modelsim.do` — +5 lines

One insertion right after `vmap work work` (lines 12–16):

```tcl
# --- Structural primitives library (needed by every RTL module) -------------
vlog ../rtl/primitives.v
```

This must come **first**, because every structural module instantiates blocks
from it and the `work` library persists across `vlog` calls.
`sim/run_vivado_sim.tcl` needs no change — its `glob $rtl_dir/*.v` picks up the
new file automatically.

### 6.10 `docs/structural-modelling-option3.md` — new file (163 lines)

The design document for the *next* branch, written on this one. Worth reading in
full; its structure:

| Section | Content |
|---|---|
| §1 Goal | A per-module table: which modules to convert and **why**. `bcd_converter` stays behavioral because the unrolled loop is "far more readable and less error-prone than a hand-wired stage chain"; `fsm_controller` stays behavioral because it needs a multiply and 32-bit timers, giving "much larger with no functional benefit". |
| §1 (cont.) | The **hard constraint**: never change a module's interface, and preserve the internal net names the testbenches reach into — `fsm_controller.state` (with its exact encoding), and `top`'s `u_fsm`, `ms_elapsed`, `lfsr_value`, `button_db`, `start_db`. |
| §2 The fast recipe | Because Option 1 already produced verified structural files, Option 3 is a **cherry-pick, not a rewrite**: five `git checkout Struct_mod -- <file>` commands onto a fresh branch off `main`. |
| §3 Alternative | How to write the four structural modules from scratch, with a per-module cheat-sheet, if you prefer not to cherry-pick. |
| §4 Simulation | The one-line `run_modelsim.do` change. |
| §5 Verification | The full ModelSim command sequence, **including the note that `$finish` exits the batch session so each testbench needs its own process**, plus four explicit acceptance criteria. |
| §6 Trade-off | Pro: smaller, more readable diff, awkward logic stays clear. Con: it is a *mixed* style, so it does not satisfy a strict "everything must be structural" requirement — that is what `Struct_mod` is for. |

---

## 7. Branch `Option3` — the practical mixed style

> **Commit:** `ca867aa` *Refactor FSM and BCD logic to behavioral RTL*
> **Scope:** 2 files changed, +119 / −277.

`Option3` executes the plan written in
`docs/structural-modelling-option3.md`. It keeps the structural `lfsr`,
`debounce`, `counter`, `seven_seg_driver`, `top` and `primitives.v` from
`Struct_mod`, and returns `bcd_converter.v` and `fsm_controller.v` to their
`main` behavioral form.

### 7.1 What changed, precisely

**`rtl/bcd_converter.v`** — 105 lines → 50 lines.

| Removed (from `Struct_mod`) | Restored (from `main`) |
|---|---|
| `gtN` + `mux2N` clamp | `wire value = (bin > 10'd999) ? 10'd999 : bin;` |
| `wire [SW-1:0] stage [0:IN_WIDTH]` chain | `reg [IN_WIDTH+11:0] shift;` |
| `generate` loop of 10 stages, 30 `dabble_cell` instances | `always @*` with a 10-iteration `for` loop |
| The entire `dabble_cell` module (lines 89–105) | inline `if (... >= 4'd5) ... + 4'd3;` |
| `output wire` digits | `output reg` digits |

**`rtl/fsm_controller.v`** — 261 lines → 158 lines.

| Removed (from `Struct_mod`) | Restored (from `main`) |
|---|---|
| `registerN` state + `onehot_decoder` | `reg [2:0] state, next_state;` |
| Six per-source `mux2N` candidates + the one-hot next-state mux | one `always @*` with `case (state)` |
| Three 32-bit `geN` comparators | `timer >= rand_delay` etc. |
| `mul_const8` (the whole module, 34 lines) | `lfsr_value * WAIT_SCALE` |
| `dffr`-based edge detectors | `reg button_prev; wire button_rise = button & ~button_prev;` |
| Seven single-gate Moore outputs | the defaults-plus-`case` output block |
| `output wire` × 7 | `output reg` × 7 |

The restored files are **byte-identical** to `main`'s, except that the
"STRUCTURAL implementation" comment paragraphs are gone (8 lines from
`bcd_converter.v`'s header, 8 from `fsm_controller.v`'s).

### 7.2 Why this is the sensible engineering choice

The two modules `Option3` reverts are exactly the two where structural style
costs the most and buys the least:

- **`bcd_converter`** — the structural version needs a 10-stage `generate` chain
  with 30 `dabble_cell` instances and careful `+:` part-select bookkeeping across
  a `wire [SW-1:0] stage [0:IN_WIDTH]` array. The behavioral version is one
  10-iteration loop. Both synthesize to the same combinational cone. The
  structural version is *twice the code and far easier to get wrong*.
- **`fsm_controller`** — the structural version has to build a shift-add
  multiplier (`mul_const8`: eight 32-bit muxes plus eight 32-bit ripple-carry
  adders) just to express `lfsr_value * WAIT_SCALE`, which any synthesis tool
  maps to a DSP slice or a compact constant multiplier from the `*` operator
  alone. It also spends three 32-bit `geN` comparators — 96 full adders — on
  timeouts that a behavioral `>=` handles at zero source cost.

Meanwhile the four modules `Option3` keeps structural are genuinely clean as
netlists: shift registers, synchronizers, prescalers, one-hot decoders, and a
sum-of-minterms segment decoder. That is exactly the kind of logic structural
modelling is *for*.

### 7.3 What this means if you are reading `Option3`'s source

`Option3` is a **mixed-style** design, so when you open a file, check which
camp it is in:

| File | Style on `Option3` | Read the walkthrough at |
|---|---|---|
| `rtl/primitives.v` | structural library | [§6.2](#62-rtlprimitivesv-257-lines--new-file) |
| `rtl/lfsr.v` | structural | [§6.3](#63-rtllfsrv--structural-70-lines) |
| `rtl/debounce.v` | structural | [§6.4](#64-rtldebouncev--structural-85-lines) |
| `rtl/counter.v` | structural | [§6.5](#65-rtlcounterv--structural-130-lines) |
| `rtl/seven_seg_driver.v` | structural | [§6.6](#66-rtlseven_seg_driverv--structural-170-lines) |
| `rtl/bcd_converter.v` | **behavioral** | [§3.4](#34-rtlbcd_converterv) |
| `rtl/fsm_controller.v` | **behavioral** | [§3.6](#36-rtlfsm_controllerv) |
| `rtl/top.v` | netlist + structural glue | [§3.7](#37-rtltopv) and [§6.8](#68-rtltopv--structural-glue-unchanged-instantiation-6-edits) |

The two behavioral modules do **not** depend on `primitives.v`; the four
structural ones do. Because every interface is unchanged, `top.v` wires all six
together without knowing or caring which style each uses. That interoperability
is the practical argument for the whole approach.

---

## 8. Verification results

All three branches were compiled and simulated in **ModelSim Intel FPGA Starter
Edition 20.1** while preparing this document. Each branch's `rtl/*.v` and
`tb/*.v` were compiled into a fresh `work` library, then each testbench was run
in its own `vsim` process (`vsim -c -do "run -all; quit -f" work.<tb>`) so that
`$finish` in one testbench does not terminate the others.

**Compilation:** all three branches — **0 errors, 0 warnings**.

**Simulation:**

| Testbench | `main` | `Struct_mod` | `Option3` |
|---|---|---|---|
| `lfsr_tb` | ✅ no lock-up, period = 255 | ✅ | ✅ |
| `counter_tb` | ✅ ALL TESTS PASSED | ✅ | ✅ |
| `debounce_tb` | ✅ ALL TESTS PASSED | ✅ | ✅ |
| `bcd_converter_tb` | ✅ ALL TESTS PASSED | ✅ | ✅ |
| `seven_seg_driver_tb` | ✅ ALL TESTS PASSED | ✅ | ✅ |
| `fsm_controller_tb` | ✅ ALL TESTS PASSED | ✅ | ✅ |
| `top_tb` | ✅ ALL SCENARIOS PASSED | ✅ | ✅ |

Every run reported `Errors: 0, Warnings: 0`. `lfsr_tb` prints two `PASS:` lines
instead of the common banner (see §4.1), which is why a grep for
`ALL TESTS PASSED` shows no summary line for it.

This satisfies all four acceptance criteria in
`docs/structural-modelling-option3.md` §5, including the absence of any
`'<net>' is not declared under prefix 'dut'` error — confirming that both
refactors preserved the hierarchical net names the testbenches depend on.

---

## 9. Observations, gotchas and known rough edges

### Design contracts you must not break

1. **`fsm_controller` must expose a 3-bit net literally named `state`**, with the
   encoding `IDLE=0 … FALSE_START=5`. Both `fsm_controller_tb` and `top_tb`
   reference it hierarchically, and `run_vivado_sim.tcl` adds it to the waveform.
2. **`top` must keep the instance name `u_fsm` and the nets `ms_elapsed`,
   `lfsr_value`, `button_db`, `start_db`.** Same reason.
3. **Behavioral simulation only.** The testbenches' hierarchical references do
   not survive synthesis. Post-synthesis or post-implementation runs fail with
   `'ms_elapsed' is not declared under prefix 'dut'`. `run_vivado_sim.tcl` pins
   `launch_simulation -mode behavioral` for exactly this reason.

### Things that look like bugs but aren't

- **`w_lfsr_enable` is unconnected in `top.v`.** The FSM generates an LFSR enable,
  but `lfsr.v` has no enable port. Leaving the LFSR free-running is *better* for
  randomness, and `top.v` lines 89 and 96–98 document the decision.
- **`result_ms` in `fsm_controller` is latched but never output.** Deliberate —
  the counter holds its value after `stop`, so the display reads `ms_elapsed`
  directly. `result_ms` exists for completeness and future use.
- **`counter_stop` is not a pure Moore output.** It depends on `button_rise`, not
  just the state, so it can pulse on the exact clock edge that captures the
  response. Both the RTL comment and the FSM testbench comment call this out.
- **`geN` ignores its `diff` output.** The comparison result lives entirely in the
  carry-out; the sum is genuinely unused.
- **`dabble_cell` discards its adder's carry-out.** Nibbles never exceed 9 there,
  so `9 + 3 = 12` always fits in 4 bits.
- **The reset synchronizer's flops have no reset.** Correct — they *produce* the
  reset. Both `main` and `Struct_mod` implement this the same way.

### Real rough edges

- **`rtl/README.md` and `tb/README.md` are stale on all three branches.** They
  name planned files `fsm.v` and `seven_seg.v`; the actual files are
  `fsm_controller.v` and `seven_seg_driver.v`. Neither mentions
  `bcd_converter.v`, and neither mentions `primitives.v` on the branches that
  have it.
- **`constraints/zybo_top.xdc` pins are placeholders.** Every line says so. The
  `create_clock` period (8 ns) is trustworthy; the `PACKAGE_PIN` values must be
  checked against the official Digilent master XDC for your board revision. The
  original ZYBO and the Zybo Z7 differ.
- **`sim/run_modelsim.do` runs only the first testbench in a batch session**,
  because `$finish` ends the `vsim` process. Use the per-testbench loop from
  `docs/structural-modelling-option3.md` §5 (reproduced in §5.1 above).
- **`Struct_mod`'s 32-bit ripple-carry comparators are a timing risk.** The FSM
  instantiates three `geN #(32)`, each a 32-stage ripple-carry chain, plus a
  32-bit `adderN` for the timer and eight more inside `mul_const8`. At 125 MHz
  (8 ns) synthesis will likely restructure them, but a hand-built ripple chain is
  the classic way to fail timing closure. `Option3` sidesteps this entirely by
  letting the tools infer the comparators and the multiplier.
- **`seven_seg_driver`'s structural version assumes `NUM_DIGITS >= 3`** (three
  hard-wired digit inputs into the AND/OR mux). Documented at line 26, but it is
  a real constraint the behavioral version shared implicitly.
- **`.gitignore` does not cover `sim/vivado_sim/`**, the project directory
  `run_vivado_sim.tcl` creates. Generated `.log`/`.jou`/`.wdb` files inside it are
  ignored by extension, but the `.xpr` and project subdirectories are not.

### The one-line summary of each branch

- **`main`** — a clean, well-commented, conventional behavioral RTL design.
  Read this first; it is the specification the other two must match.
- **`Struct_mod`** — the same design rebuilt as a gate-and-block netlist, to
  demonstrate that structural modelling can express the whole system. Intellectually
  complete; a 32-bit multiplier and three 32-bit comparators built from ripple-carry
  adders is the price.
- **`Option3`** — the engineering answer: structural where structure is natural
  (shift registers, synchronizers, counters, decoders), behavioral where it isn't
  (double-dabble, multiply, 32-bit datapath). Smallest diff, most readable result,
  same verified behaviour.

---

*Generated from commit `ca867aa` (`Option3`), with `Struct_mod` at `7e3f03c` and
`main` at `e2088df`.*
