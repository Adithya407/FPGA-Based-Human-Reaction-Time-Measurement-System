# Code Guide: Structural RTL and Testbenches (`Struct_mod` branch)

This document explains **every Verilog file on the `Struct_mod` branch**: what
each module is for, the concept behind it, a block-by-block walkthrough of the
RTL, and how its testbench verifies it.

> **Scope:** this guide describes the `Struct_mod` branch only. Here the RTL is
> written in a **structural** style: modules are netlists of gates and small
> building blocks. On `main` the same modules are written behaviourally (with
> `always` blocks and operators such as `+`, `==` and `case`). The ports and
> behaviour are the same, so the same testbenches run unchanged on both
> branches.

---

## Contents

1. [System overview](#1-system-overview)
2. [The structural modelling style](#2-the-structural-modelling-style)
3. [`primitives.v`: the building-block library](#3-primitivesv--the-building-block-library)
4. [`lfsr.v`: pseudo-random number generator](#4-lfsrv--pseudo-random-number-generator)
5. [`debounce.v`: button synchronizer and debouncer](#5-debouncev--button-synchronizer-and-debouncer)
6. [`counter.v`: millisecond reaction timer](#6-counterv--millisecond-reaction-timer)
7. [`bcd_converter.v`: binary to decimal digits](#7-bcd_converterv--binary-to-decimal-digits)
8. [`seven_seg_driver.v`: multiplexed display driver](#8-seven_seg_driverv--multiplexed-display-driver)
9. [`fsm_controller.v`: the control state machine](#9-fsm_controllerv--the-control-state-machine)
10. [`top.v`: system integration](#10-topv--system-integration)
11. [Running the simulations](#11-running-the-simulations)
12. [Verified results](#12-verified-results)

---

## 1. System overview

The system measures how long a person takes to press a button after an LED
lights up:

1. The user presses **start**.
2. The board waits a **random** 1–3 s delay, so the user can't anticipate the
   stimulus.
3. The **stimulus LED** turns on and a millisecond timer starts.
4. The user presses the **response button**. The timer stops.
5. The elapsed time in ms is shown on a **3-digit seven-segment display**.
6. Pressing the response button *before* the LED lights up is a **false start**.
   The false-start LED flashes and the trial is discarded.

### Module hierarchy

```
top
├── dffr ×2            reset synchronizer
├── lfsr               random value source
├── debounce ×2        response button + start button
├── fsm_controller     sequences the trial
│   └── mul_const8     lfsr_value × WAIT_SCALE
├── counter            elapsed milliseconds
├── bcd_converter      binary ms → hundreds/tens/ones
│   └── dabble_cell ×30
├── seven_seg_driver   multiplex digits onto the display
│   └── seg7_decoder
└── mux2N              blank the display unless a result is ready

Every module above is built from the blocks in primitives.v
(dffr, registerN, mux2/mux2N, full_adder, adderN, eqN, geN, gtN, onehot_decoder).
```

### Dataflow

```
 btn_start ──[debounce]──► start_db ─┐
 pmod_button_in ─[debounce]─► button_db ─┤
                                     ▼
                  lfsr ──► lfsr_value ──► fsm_controller ──► led_stimulus, led_false_start
                                     ▲        │ counter_start / stop / reset
                                     │        ▼
                         ms_elapsed ─┴──── counter
                                              │ ms_elapsed
                                              ▼
                                       bcd_converter ──► seven_seg_driver ──► seg[6:0], an[2:0]
                                                                      ▲
                                    fsm.display_enable ── blanking mux ┘
```

### File map

| RTL file | Testbench | Purpose |
|---|---|---|
| [rtl/primitives.v](rtl/primitives.v) | (tested through every other TB) | Gate-level building blocks |
| [rtl/lfsr.v](rtl/lfsr.v) | [tb/lfsr_tb.v](tb/lfsr_tb.v) | 8-bit pseudo-random sequence |
| [rtl/debounce.v](rtl/debounce.v) | [tb/debounce_tb.v](tb/debounce_tb.v) | Clean, synchronized button signal |
| [rtl/counter.v](rtl/counter.v) | [tb/counter_tb.v](tb/counter_tb.v) | Counts elapsed milliseconds |
| [rtl/bcd_converter.v](rtl/bcd_converter.v) | [tb/bcd_converter_tb.v](tb/bcd_converter_tb.v) | Binary → 3 BCD digits |
| [rtl/seven_seg_driver.v](rtl/seven_seg_driver.v) | [tb/seven_seg_driver_tb.v](tb/seven_seg_driver_tb.v) | Drives the 7-segment display |
| [rtl/fsm_controller.v](rtl/fsm_controller.v) | [tb/fsm_controller_tb.v](tb/fsm_controller_tb.v) | Trial sequencing |
| [rtl/top.v](rtl/top.v) | [tb/top_tb.v](tb/top_tb.v) | Full system |

---

## 2. The structural modelling style

**Behavioural** Verilog describes *what* a circuit does (`count <= count + 1;`).
**Structural** Verilog describes *what the circuit is made of*: gates and
sub-modules wired together. On this branch, every module follows three rules.
These are stated at the top of [rtl/primitives.v](rtl/primitives.v):

1. **All logic is built from gate primitives** (`and`, `or`, `xor`, `not`,
   `buf`, `xnor`) or by instantiating the blocks in `primitives.v`.
2. **`assign` is used only for wiring**: renaming a net, concatenating bits
   (`{a, b}`), or tying a net to a constant. It is never used with a logic
   operator.
3. **The only behavioural code is the D flip-flop (`dffr`).** A flip-flop is the
   basic storage element, and describing it with one `always @(posedge clk)` is
   standard practice even in fully structural designs.

As a result, a `+` becomes an `adderN` (a chain of full adders), an `==` becomes
an `eqN` (XNOR gates and an AND chain), an `if/else` becomes a `mux2N`, and a
`case` on the state becomes a one-hot decoder plus AND/OR gates.

Two idioms appear in almost every module, so they are explained once here:

**Counter idiom** (count up, wrap to 0 at a terminal value):

```
          ┌──────── eqN(count, MAX) ──► at_max ─┐
count ────┤                                     │ sel
          └── adderN(count + 1) ──► mux2N(a=count+1, b=0) ──► registerN ──► count
```

**Priority / enable idiom:** a register has an `en` input. When `en` is low, the
register keeps its value. Each register's `en` and `d` are built from gate logic
so that it updates only on the events that should change it.

---

## 3. `primitives.v`: the building-block library

**File:** [rtl/primitives.v](rtl/primitives.v)

### Concept

This is the "parts bin" for the whole design. Each block is a small, standard
digital circuit you would draw in a logic-design course. The larger modules
instantiate these blocks instead of using Verilog operators.

### Blocks

#### `dffr`: D flip-flop with synchronous reset and enable

```verilog
always @(posedge clk) begin
    if (rst)     q <= RESET_VAL;
    else if (en) q <= d;
end
```

- On each rising clock edge: if `rst` is 1, load `RESET_VAL`. Otherwise, if
  `en` is 1, load `d`. Otherwise keep `q`.
- `RESET_VAL` is a parameter, so a flop can reset to 1. The LFSR needs this,
  because its register must never reset to all zeros.
- This is the **only behavioural block** in the design.

#### `registerN`: N-bit register

A `generate` loop creates `WIDTH` copies of `dffr`, one per bit. Bit `i` resets
to `RESET_VAL[i]`, so the whole register can reset to any constant (for
example `8'hFF`). All bits share `clk`, `rst` and `en`.

#### `mux2` / `mux2N`: 2-to-1 multiplexer

```
y = (a AND NOT sel) OR (b AND sel)
```

Built from one `not`, two `and` gates and one `or`. When `sel = 0` the output
is `a`; when `sel = 1` it is `b`. `mux2N` repeats `mux2` for each bit of a bus,
with all bits sharing the same `sel`. This is the structural replacement for
`y = sel ? b : a`.

#### `full_adder`: 1-bit full adder

```
sum  = a XOR b XOR cin
cout = (a AND b) OR ((a XOR b) AND cin)
```

The standard two-XOR, two-AND, one-OR full adder.

#### `adderN`: N-bit ripple-carry adder

A chain of `full_adder`s. The carry-out of bit `i` feeds the carry-in of bit
`i+1`. `carry[0] = cin` and `cout = carry[WIDTH]`. The design uses it in two
ways:

- **Increment:** `a = x`, `b = 0`, `cin = 1` gives `x + 1`. Every counter uses this.
- **Subtract or compare:** see `geN` below.

#### `eqN`: equality comparator (`a == b`)

1. `xnor` each bit pair: `biteq[i] = 1` when `a[i] == b[i]`.
2. AND all `biteq` bits together with a chain of `and` gates.

The output is 1 only if every bit matches.

#### `geN`: unsigned "greater than or equal" (`a >= b`)

Uses two's-complement subtraction: `a − b = a + (~b) + 1`.

1. Invert every bit of `b` with `not` gates.
2. Feed `a`, `~b` and `cin = 1` into an `adderN`.
3. The **carry-out** is the answer. For unsigned numbers, the subtraction
   produces a carry-out exactly when `a >= b` (no borrow). The difference
   itself is not used.

#### `gtN`: unsigned "greater than" (`a > b`)

`a > b` is the same as `NOT (b >= a)`. So `gtN` is a `geN` with its inputs
swapped, followed by a `not` gate.

#### `onehot_decoder`: binary to one-hot

For each output `k`, an `eqN` compares `sel` with the constant `k`. Exactly one
output line is high: the one whose index equals `sel`. The FSM uses it to decode
its state number, and the display driver uses it to choose which digit is lit.

### How it is verified

There is no dedicated testbench for `primitives.v`. Every other module is built
from these blocks, so every other testbench exercises them. For example,
`bcd_converter_tb` checks all 1000 values of a circuit made almost entirely of
`adderN`, `gtN` and `mux2N`. If any primitive were wrong, the module tests would
fail.

---

## 4. `lfsr.v`: pseudo-random number generator

**Files:** [rtl/lfsr.v](rtl/lfsr.v) · [tb/lfsr_tb.v](tb/lfsr_tb.v)

### Concept: how an LFSR uses a polynomial to make "random" numbers

A **Linear Feedback Shift Register (LFSR)** is a shift register whose new input
bit is the **XOR of some of its own bits** (called *taps*). Each clock cycle it
shifts by one position, and the XOR result enters at the empty end. The register
steps through a long, scrambled-looking sequence of values, and the circuit
costs only a few flip-flops and one XOR gate.

**Which bits are tapped is defined by a feedback polynomial.** This design uses

```
P(x) = x^8 + x^6 + x^5 + x^4 + 1
```

How to read it:

- The **degree (8)** is the register length: 8 flip-flops.
- Each term `x^k` (other than the `+1`) marks a tap at stage `k`. Stages are
  numbered 1–8 while Verilog bits are numbered 0–7, so stage `k` is bit `k−1`:

  | Term | Stage | Register bit |
  |---|---|---|
  | x⁸ | 8 | `state[7]` (the MSB, oldest bit) |
  | x⁶ | 6 | `state[5]` |
  | x⁵ | 5 | `state[4]` |
  | x⁴ | 4 | `state[3]` |
  | 1  | 0 | the input: the feedback enters at `state[0]` |

- So the feedback bit is `fb = state[7] ⊕ state[5] ⊕ state[4] ⊕ state[3]`, and
  each clock: `state ← {state[6:0], fb}` (shift left, `fb` into the LSB). This
  arrangement, with taps XORed and fed back to one end, is the **Fibonacci**
  form of an LFSR.

**Why this polynomial?** It is a **primitive polynomial** over GF(2), the
arithmetic of single bits where addition is XOR. Mathematically, an n-bit LFSR
whose feedback polynomial is primitive visits **every non-zero n-bit value
exactly once** before repeating. That is a *maximal-length* sequence with
period **2ⁿ − 1**. For n = 8 the period is **255**. A non-primitive polynomial
would split the 255 states into several shorter cycles.

**Why "pseudo"-random?** The sequence is fully deterministic: the same start
value always gives the same sequence. It still *looks* random: about half the
bits are 1, there are no short repeats, and consecutive values are hard to
predict by eye.

**The all-zero lock-up state.** If every bit is 0, the XOR of the taps is 0, so
the next state is 0 again, forever. That is why the 256th value (0x00) is not in
the cycle, and why the register must **reset to a non-zero seed** (`8'hFF`).

**Worked example** (seed = 0xFF), matching the testbench printout:

| Step | State (bin) | Hex | Taps b7 b5 b4 b3 | fb = XOR |
|---|---|---|---|---|
| reset | 1111 1111 | FF | 1 1 1 1 | 0 |
| 1 | 1111 1110 | FE | 1 1 1 1 | 0 |
| 2 | 1111 1100 | FC | 1 1 1 1 | 0 |
| 3 | 1111 1000 | F8 | 1 1 1 1 | 0 |
| 4 | 1111 0000 | F0 | 1 1 1 0 | 1 |
| 5 | 1110 0001 | E1 | 1 1 0 0 | 0 |
| 6 | 1100 0010 | C2 | 1 0 0 0 | 1 |
| 7 | 1000 0101 | 85 | … | … |

Each new state is the previous state shifted left, with that row's `fb` entering
at the right.

**How it makes the delay random in this system.** The LFSR **runs freely at
125 MHz**, stepping 125 million times per second. The FSM samples
`lfsr_value` at the instant the user presses start. A human cannot time a press
to within 8 ns, so the sampled value is effectively unpredictable even though
the sequence itself is fixed.

### Block-by-block walkthrough

| Block | Code | What it does |
|---|---|---|
| Parameter `SEED` | `parameter [7:0] SEED = 8'hFF` | Non-zero reset value. It must never be 0, or the LFSR locks up. |
| Ports | `clk, rst, load, seed_in, value` | `load` + `seed_in` let you load your own start value. `top` ties `load` to 0. |
| **Feedback XOR** | `xor (feedback, state[7], state[5], state[4], state[3]);` | A single 4-input XOR gate that implements the polynomial taps. |
| **Shift wiring** | `assign shift_val = {state[6:0], feedback};` | The left shift. It is pure wiring: bits move one place up and `feedback` fills bit 0. |
| **Zero-seed guard** | `eqN u_zero (seed_in == 8'h00)` | Detects an illegal all-zero external seed. |
| **Seed mux** | `mux2N u_seedmux` | `load_val = seed_is_zero ? SEED : seed_in`. A zero seed is replaced with `SEED`, so the LFSR can never be loaded into the lock-up state. |
| **Next-state mux** | `mux2N u_nextmux` | `next_state = load ? load_val : shift_val`. Load takes priority over shifting. |
| **State register** | `registerN #(.WIDTH(8), .RESET_VAL(SEED)) u_state` | 8 `dffr` flops, always enabled, resetting to `SEED`. |
| Output | `assign value = state;` | Exposes the current state. |

### How `lfsr_tb.v` verifies it

**Setup:** the testbench instantiates `lfsr` with `SEED = 8'hFF`, drives a
100 MHz clock, holds `rst` for two edges, and keeps `load = 0`.

**Procedure:** it runs **300 clock cycles** (more than one full period of 255).
On each cycle it waits 1 ns after the edge so the output has settled, then:

1. **Prints** the cycle number and the value in hex and binary, giving a
   readable trace of the sequence.
2. **Lock-up check:** if `value == 8'h00`, it increments `stuck_count` and
   prints an error. A correct LFSR must never reach 0.
3. **Period measurement:** it remembers the first value after reset
   (`first_value`, which is 0xFE) and records the cycle number `i` at which that
   value **first reappears**. That number is the sequence period.

**Pass criteria:**

- `stuck_count == 0` → `PASS: LFSR never stuck at 0x00 over 300 cycles.`
- `period == 255` → `PASS: maximal-length sequence confirmed (period = 255).`

A period of exactly 255 proves two things: the taps implement a *primitive*
polynomial, and the state passes through all 255 non-zero values. A wrong tap
would give a shorter period, and the testbench would print a `NOTE` with the
measured value instead.

---

## 5. `debounce.v`: button synchronizer and debouncer

**Files:** [rtl/debounce.v](rtl/debounce.v) · [tb/debounce_tb.v](tb/debounce_tb.v)

### Concept

A mechanical push-button has two problems for digital logic:

1. **Contact bounce.** When pressed or released, the metal contacts bounce for a
   few milliseconds. The signal toggles 0/1 many times before settling. Without
   filtering, one press could look like ten presses.
2. **Metastability.** The button is not synchronized to the FPGA clock. If its
   edge arrives too close to a clock edge, the first flip-flop that samples it
   can briefly enter an in-between (metastable) state. A chain of flip-flops
   gives that state time to resolve before the rest of the logic uses it.

The module solves both in two stages:

- **Stage 1, synchronizer:** two flip-flops in series. The second one's output is
  safe to use inside the 125 MHz clock domain.
- **Stage 2, stability counter:** the output changes only after the synchronized
  input has held a **new** level for `STABLE_COUNT` consecutive clocks. Any
  bounce back to the old level restarts the count. The default `1,250,000`
  clocks equals **10 ms** at 125 MHz, which is longer than typical bounce.

Total delay from a clean edge to `btn_out` changing = **`STABLE_COUNT + 2`
clocks** (2 for the synchronizer).

### Block-by-block walkthrough

| Block | Code | What it does |
|---|---|---|
| Width calculation | `CW = $clog2(STABLE_COUNT)` | Number of counter bits needed to count `0 … STABLE_COUNT−1`. |
| Terminal count | `TERM = STABLE_COUNT − 1` | The count value at which the window has elapsed. |
| **Synchronizer** | `dffr u_sync0`, `dffr u_sync1` | `btn_in → sync_0 → sync_1`. Two flops in series; `btn_sync = sync_1`. |
| **Match detector** | `xnor (match, btn_sync, btn_out);` | `match = 1` when the input already equals the output, so nothing is pending. |
| **Window detector** | `eqN u_atwin (count == TERM)` | `at_window = 1` when the new level has been held long enough. |
| **Count clear** | `or (clear_count, match, at_window);` | Reset the count when the input matches the output (a bounce back, or idle) or when the window has just elapsed. |
| **Incrementer** | `adderN u_inc` | `count_plus1 = count + 1`. |
| **Count mux** | `mux2N u_cntmux` | `count_next = clear_count ? 0 : count + 1`. |
| **Count register** | `registerN u_count` | Holds the stability count. |
| **Output enable** | `not` + `and (out_en, at_window, not_match)` | Update the output only when the window has elapsed **and** the levels still differ. |
| **Output flop** | `dffr u_out (.en(out_en), .d(btn_sync))` | When enabled, `btn_out` takes the new stable level. Otherwise it holds. |

**Behaviour, step by step:** while the button is steady, `match = 1`, so the
count stays at 0. When the input changes, `match` drops to 0 and the count
starts climbing. If the input bounces back before the count reaches `TERM`,
`match` returns to 1 and the count clears. If the input holds until
`count == TERM`, `out_en` pulses for one clock and `btn_out` takes the new level.
Then `match` becomes 1 again.

### How `debounce_tb.v` verifies it

**Setup:** the testbench overrides `STABLE_COUNT = 20`, so the window is 20
clocks instead of 1.25 million and simulation is fast. The expected latency is
`EXPECT_LAT = 20 + 2 = 22` clocks. The clock is 125 MHz.

**Helper tasks:**

- `drive_and_expect(lvl, cyc, exp)` sets `btn_in = lvl` for `cyc` clocks and
  checks **on every clock** that `btn_out` is still `exp`.
- `measure_latency(lvl, target, n)` sets `btn_in = lvl` and counts clocks until
  `btn_out` reaches `target`.

**Test phases:**

| Phase | Stimulus | Check |
|---|---|---|
| 1. Idle | input low for 5 clocks | output stays low |
| 2. Bouncy press | 1 / 0 / 1 / 0 / 1 / 0 pulses, **8 clocks each** (shorter than the 20-clock window) | output stays **low** the whole time, so the bounces are rejected |
| 3. Clean press | input held high | output goes high after **exactly 22 clocks** |
| 3b. Hold | input high for 10 clocks | output stays high |
| 4. Bouncy release | 0 / 1 / 0 / 1 / 0 / 1 pulses, 8 clocks each | output stays **high** |
| 5. Clean release | input held low | output goes low after **exactly 22 clocks** |
| 5b. Hold | input low for 10 clocks | output stays low |

Every mismatch increments `errors`. The run ends with `ALL TESTS PASSED.` or a
failure count. Checking the latency to the exact clock confirms both the
2-flop synchronizer and the `TERM` comparison.

---

## 6. `counter.v`: millisecond reaction timer

**Files:** [rtl/counter.v](rtl/counter.v) · [tb/counter_tb.v](tb/counter_tb.v)

### Concept

To measure milliseconds from a 125 MHz clock, the clock is **divided down**:

- A **prescaler** counts `0 … 124,999`. That is 125,000 clocks = 1 ms at
  125 MHz.
- Each time the prescaler wraps, the **ms counter** increments by one.

`start` clears both counters and begins counting. `stop` freezes them and raises
`done`. The ms output is 10 bits wide (0–1023) and **saturates** at 1023
instead of wrapping to 0. Without saturation, a very slow response could alias
to a small, wrong time.

In structural form there is no `if/else` chain, so priorities are written as
explicit, **mutually exclusive events**:

```
c_start = start & ~running                  begin a new measurement
c_stop  = stop  &  running & ~c_start       freeze the count
c_run   = running & ~c_start & ~c_stop      ordinary counting cycle
```

At most one of these is true in any clock cycle. `rst` overrides all of them
through the flip-flop resets.

### Block-by-block walkthrough

| Block | Code | What it does |
|---|---|---|
| Parameters | `CLKS_PER_MS = 125000`, `MS_WIDTH = 10` | Prescaler length and output width. Testbenches shrink `CLKS_PER_MS`. |
| Constants | `PW`, `PRESCALE_MAX = CLKS_PER_MS−1`, `MS_MAX = all 1s` | Prescaler width, its wrap value, and the saturation value. |
| **Event logic** | `not`/`and` gates → `c_start`, `c_stop`, `c_run` | Decodes the three priority-ordered events above. |
| **`running` flop** | `dffr u_running (.en(c_start\|c_stop), .d(c_start))` | On start, load 1. On stop, load 0 (because `c_start = 0`). Otherwise hold. |
| **`done` flop** | `dffr u_done (.en(c_start\|c_stop), .d(c_stop))` | The opposite: start clears it, stop sets it. |
| **Prescaler wrap** | `eqN u_pmax` → `at_max_p` | True on the last clock of each millisecond. |
| **Prescaler next value** | `adderN u_pinc` → `mux2N u_prun` → `mux2N u_pmux` | Running: `at_max_p ? 0 : prescale+1`. On start, force 0. |
| **Prescaler register** | `registerN u_prescale (.en(c_start\|c_run))` | Changes only when starting or running, so it freezes after stop. |
| **Saturation check** | `eqN u_msmax` → `ms_is_max` → `not` | `ms_not_max` blocks increments once ms reaches 1023. |
| **ms tick** | `and(tick_pre, c_run, at_max_p)`; `and(ms_tick, tick_pre, ms_not_max)` | One pulse per millisecond while running, unless saturated. |
| **ms next value** | `adderN u_msinc` → `mux2N u_msmux` | `ms_next = c_start ? 0 : ms+1`. |
| **ms register** | `registerN u_ms (.en(c_start\|ms_tick))` | Clears on start, increments on each tick, otherwise holds. |

Because `c_stop` blocks `c_run`, the clock edge that stops the counter can never
also add a millisecond.

### How `counter_tb.v` verifies it

**Setup:** `CLKS_PER_MS = 10`, so 1 "ms" = 10 clocks. The ideal result for
running `N` clocks is therefore `N / 10`, rounded down.

**Helper task `run_and_check(ncycles)`:**

1. Synchronous reset.
2. Pulse `start` for one clock.
3. Wait exactly `ncycles` clocks.
4. Pulse `stop` for one clock.
5. Check: `ms == ncycles/10`, `done == 1`, `running == 0`.

**Test cases:**

| `ncycles` | Expected ms | Why this case |
|---|---|---|
| 50 | 5 | exact multiple |
| 123 | 12 | not a multiple; the remainder must be dropped |
| 10 | 1 | exactly one tick boundary |
| 9 | 0 | one clock short of a tick, an off-by-one check |
| 1000 | 100 | long run |

**Hold test:** after a 30-clock (3 ms) run and a stop, the testbench waits 40
more clocks and checks that `ms` is still `3` and `running` is `0`. This proves
the counter really freezes after a stop.

---

## 7. `bcd_converter.v`: binary to decimal digits

**Files:** [rtl/bcd_converter.v](rtl/bcd_converter.v) · [tb/bcd_converter_tb.v](tb/bcd_converter_tb.v)

### Concept: the double-dabble algorithm

The counter outputs a **binary** number, for example `0b0000101010` (42). The
display needs **decimal digits**: `0`, `4`, `2`. Each decimal digit is stored as
a 4-bit **BCD** (binary-coded decimal) nibble.

Dividing by 10 in hardware is expensive. **Double dabble** (shift-and-add-3)
converts using only shifts and small additions:

1. Start with the BCD nibbles all zero and the binary number to their right.
2. Repeat once per input bit:
   - **Correct:** for each BCD nibble, if its value is **≥ 5, add 3**.
   - **Shift** the whole vector left by one bit.
3. After all bits have been shifted in, the nibbles hold the decimal digits.

**Why add 3?** A shift doubles a nibble. If a nibble is ≥ 5, doubling gives
≥ 10, which is not a valid BCD digit, and the carry into the next digit would be
lost. Adding 3 *before* the shift adds 6 *after* it. Adding 6 is exactly the
BCD correction that turns `10…15` into a proper carry plus `0…5`.

**Worked example: 42** (`0000101010`, input bits enter MSB first):

| Step | Bit shifted in | Correction applied | Tens | Ones |
|---|---|---|---|---|
| 1–4 | 0, 0, 0, 0 | none | 0000 | 0000 |
| 5 | 1 | none | 0000 | 0001 |
| 6 | 0 | none | 0000 | 0010 |
| 7 | 1 | none | 0000 | 0101 (5) |
| 8 | 0 | ones = 5 ≥ 5 → 5+3 = 8 (1000) | 0001 | 0000 |
| 9 | 1 | none | 0010 | 0001 |
| 10 | 0 | none | **0100 (4)** | **0010 (2)** |

The result is `4 2`. ✔

Ten bits can hold up to 1023, but three BCD digits can only show 999. So the
input is first **clamped to 999**. If the counter saturates at 1023, the display
shows `999` rather than garbage.

### Block-by-block walkthrough

| Block | Code | What it does |
|---|---|---|
| Constants | `SW = IN_WIDTH + 12`, `MAX999 = 999` | Width of the scratch vector (input bits + three 4-bit nibbles). |
| **Clamp comparator** | `gtN u_clampcmp (bin > 999)` | Detects out-of-range input. |
| **Clamp mux** | `mux2N u_clampmux` | `value = gt999 ? 999 : bin`. |
| **Stage 0** | `assign stage[0] = {12'b0, value};` | Initial vector: three zero nibbles above the binary value. |
| **Stage chain** (`generate`, `IN_WIDTH` stages) | `ddstage[i]` | Each stage is one *correct + shift* step of the algorithm, so the loop is unrolled into pure combinational hardware. |
| – binary pass-through | `assign corr[IN_WIDTH-1:0] = cur[IN_WIDTH-1:0];` | The not-yet-shifted binary bits are not corrected. |
| – three correction cells | `dabble_cell c_ones / c_tens / c_huns` | Apply "add 3 if ≥ 5" to each nibble. |
| – shift | `assign stage[i+1] = {corr[SW-2:0], 1'b0};` | Shift left by one bit. This is pure wiring, with no gates. |
| **Digit extraction** | `assign ones/tens/hundreds = result[…]` | Picks the three nibbles out of the final stage. |

#### Sub-module `dabble_cell`

- **"≥ 5" detector, from gates:** for a 4-bit value,
  `ge5 = in[3] | (in[2] & (in[1] | in[0]))`. In words: the value is 8 or more,
  **or** it is 4–7 with at least one low bit set, which covers 5, 6 and 7.
- **Conditional +3:** a 4-bit `adderN` adds `{0, 0, ge5, ge5}`. That is
  `0011` = 3 when `ge5 = 1` and `0000` = 0 otherwise. A nibble entering a cell
  is never more than 9, so `in + 3 ≤ 12` always fits in 4 bits and the carry-out
  is ignored.

With `IN_WIDTH = 10` there are 10 stages × 3 cells = **30 `dabble_cell`s**.

### How `bcd_converter_tb.v` verifies it

The module is purely combinational: there is no clock. The testbench sets the
input, waits 1 ns for the gates to settle, and compares the outputs.

1. **Exhaustive test:** for **every** value `v` from 0 to 999, the expected
   digits are computed with ordinary integer arithmetic (`v/100`, `(v/10)%10`,
   `v%10`) and compared with the hardware output. All 1000 possible results are
   checked, so the test proves the converter correct for its entire valid range.
2. **Clamp test:** `1000 → 9 9 9` and `1023 → 9 9 9`.
3. **Spot checks** (kept for a readable log): `0, 7, 42, 305, 999`.

Any mismatch prints `FAIL: bin=… -> … (expected …)`. Otherwise the run ends
with `ALL TESTS PASSED.`

---

## 8. `seven_seg_driver.v`: multiplexed display driver

**Files:** [rtl/seven_seg_driver.v](rtl/seven_seg_driver.v) · [tb/seven_seg_driver_tb.v](tb/seven_seg_driver_tb.v)

### Concept

**Seven-segment encoding.** Each digit is drawn with seven LED segments named
`a`–`g`:

```
  aaa
 f   b
 f   b
  ggg
 e   c
 e   c
  ddd
```

In this design `seg[6]=a, seg[5]=b, seg[4]=c, seg[3]=d, seg[2]=e, seg[1]=f,
seg[0]=g`, and `1` lights a segment (by default).

**Time multiplexing.** All three digits share the same 7 segment wires. Each
digit has its own enable line, the **anode** `an[k]`. The driver:

1. Enables only digit 0 (ones) and puts the ones pattern on `seg`.
2. Then digit 1 (tens) with the tens pattern.
3. Then digit 2 (hundreds) with the hundreds pattern.
4. Repeats.

Each digit gets a ~333 µs slot (`41,667 clocks × 8 ns`), and a full scan takes
~1 ms. Every digit is therefore refreshed ~1000 times per second, far faster
than the eye can see flicker (~60 Hz), so all three digits appear lit at once.
This needs 7 + 3 = 10 pins instead of 7 × 3 = 21.

### Block-by-block walkthrough

| Block | Code | What it does |
|---|---|---|
| Parameters | `NUM_DIGITS=3, REFRESH_CLKS=41667, SEG_ACTIVE_LOW, AN_ACTIVE_LOW` | Digit count, slot length, and output polarity (to suit common-anode or common-cathode displays). |
| **Refresh prescaler** | `eqN u_rmax` + `adderN u_rinc` + `mux2N u_rmux` + `registerN u_refresh` | Counts `0 … REFRESH_CLKS−1` and wraps. `slot_done` is high for one clock at the end of each slot. |
| **Digit index** | `eqN u_dmax` + `adderN u_dinc` + `mux2N u_dmux` + `registerN u_digit (.en(slot_done))` | Steps `0 → 1 → 2 → 0`, once per slot. |
| **One-hot decoder** | `onehot_decoder u_dec` | Turns `digit_idx` into `an_onehot` = `001`, `010`, `100`. |
| **Digit select mux** | per bit: `and(mo, ones[b], an_onehot[0])` … `or(cur_bcd[b], mo, mt, mh)` | An AND-OR multiplexer: each digit's bits are masked by its select line, and the results are ORed. Only the active digit gets through. |
| **BCD → 7-segment** | `seg7_decoder u_seg` | Converts the selected digit to its segment pattern. |
| **Polarity** | `generate if (AN_ACTIVE_LOW) not … else buf …` | Inverts the anodes and/or segments at compile time if the hardware is active-low. |

#### Sub-module `seg7_decoder`: sum of minterms

1. `not` gates make the inverted inputs `n3 n2 n1 n0`.
2. Ten 4-input `and` gates make **minterms** `m0 … m9`. `m5`, for example, is
   high only when the input is `0101`.
3. Each segment is the `or` of the minterms for the digits in which that segment
   is lit. For example, segment `e` is lit only for 0, 2, 6 and 8, so
   `seg[2] = m0 | m2 | m6 | m8`.

Inputs 10–15 match no minterm, so every segment is off (blank).

| Digit | a b c d e f g | `seg` |
|---|---|---|
| 0 | 1 1 1 1 1 1 0 | `1111110` |
| 1 | 0 1 1 0 0 0 0 | `0110000` |
| 2 | 1 1 0 1 1 0 1 | `1101101` |
| 3 | 1 1 1 1 0 0 1 | `1111001` |
| 4 | 0 1 1 0 0 1 1 | `0110011` |
| 5 | 1 0 1 1 0 1 1 | `1011011` |
| 6 | 1 0 1 1 1 1 1 | `1011111` |
| 7 | 1 1 1 0 0 0 0 | `1110000` |
| 8 | 1 1 1 1 1 1 1 | `1111111` |
| 9 | 1 1 1 1 0 1 1 | `1111011` |

### How `seven_seg_driver_tb.v` verifies it

**Setup:** `REFRESH_CLKS = 4`, so the scan advances every 4 clocks.

**Reference model:** a function `exp_seg(v)` holds the correct pattern for each
digit, written as a plain `case` table: the table above. A second function,
`ones_count(an)`, counts how many anodes are on.

**Test 1, segment encoding (0–9):** all three inputs are set to the same digit
`d`. Whichever anode is active, `seg` must equal `exp_seg(d)`. All ten digits
are checked, and a `PASS: digit d -> seg=…` line is printed for each.

**Test 2, multiplexing:** the digits are made distinct: `hundreds=6, tens=5,
ones=4`. The scan is restarted, then the testbench watches **every clock for two
full scans** (2 × 3 × 4 + 4 clocks) and checks:

- **exactly one anode is active** (`ones_count(an) == 1`), so the select is
  one-hot;
- when `an[0]` is active, `seg` shows **4**; when `an[1]` is active, **5**; when
  `an[2]` is active, **6**. Each slot shows its own digit.

Together these tests check the decoder, the digit-select mux, the one-hot
decoder and the refresh counters.

---

## 9. `fsm_controller.v`: the control state machine

**Files:** [rtl/fsm_controller.v](rtl/fsm_controller.v) · [tb/fsm_controller_tb.v](tb/fsm_controller_tb.v)

### Concept

A **Finite State Machine (FSM)** is the "brain" of the system. It is always in
exactly one **state**. Each clock it chooses the **next state** from its inputs
(button presses, timer values), and its **outputs** depend on the current state.

```
                start                 delay elapsed
     ┌──────┐ ───────► ┌─────────────┐ ───────────► ┌──────────┐
 ┌──►│ IDLE │          │ RANDOM_WAIT │              │ STIMULUS │
 │   └──────┘          └─────────────┘              └──────────┘
 │      ▲  ▲                 │ button (too early)         │ (always, 1 clock)
 │      │  │                 ▼                            ▼
 │      │  │          ┌─────────────┐              ┌───────────┐
 │      │  └──────────│ FALSE_START │              │ MEASURING │
 │      │  hold time  └─────────────┘              └───────────┘
 │      │                                                │ button
 │      │  hold time or start   ┌────────┐                ▼
 │      └───────────────────────│ RESULT │◄───────────────┘
 │                              └────────┘
```

| # | State | Meaning | Exits to |
|---|---|---|---|
| 0 | `IDLE` | Waiting. Counter held in reset. | `RANDOM_WAIT` on a start press |
| 1 | `RANDOM_WAIT` | Random pre-stimulus delay. | `FALSE_START` on an early press; `STIMULUS` when `timer ≥ rand_delay` |
| 2 | `STIMULUS` | LED on, pulse `counter_start`. Lasts one clock. | `MEASURING` |
| 3 | `MEASURING` | LED on, counter running. | `RESULT` on the response press (`counter_stop` pulses) |
| 4 | `RESULT` | Display enabled. | `IDLE` after `RESULT_HOLD_CLKS` (~3 s) or on a start press |
| 5 | `FALSE_START` | False-start LED on. | `IDLE` after `FALSE_HOLD_CLKS` (~1 s) |

**Random delay:**

```
rand_delay = MIN_WAIT_CLKS + lfsr_value × WAIT_SCALE   (in clock cycles)
           = 125,000,000   + lfsr_value × 1,000,000
           = 1 s           + lfsr_value × 8 ms          → about 1.0 s … 3.04 s
```

**Edge detection:** the buttons are treated as **rising-edge events**
(`button & ~button_prev`). Holding a button down counts as one press, not one
press per clock.

### Block-by-block walkthrough

| Block | Code | What it does |
|---|---|---|
| State encoding | `localparam IDLE=0 … FALSE_START=5` | 3-bit binary state numbers. |
| **State register** | `registerN #(3) u_state` | Holds `state`. It resets to `IDLE`. The net is named `state` so the testbenches can read it as `dut.state`. |
| **State decoder** | `onehot_decoder u_sdec` → `soh[5:0]` | `soh[k] = 1` when the FSM is in state `k`. This replaces `case (state)`. |
| **Edge detectors** | `dffr u_bprev/u_sprev` + `not`/`and` | `button_rise = button & ~button_prev`, and the same for `start_rise`. |
| **Timer comparators** | three `geN #(32)` | `tge_rand = timer ≥ rand_delay`, `tge_result = timer ≥ RESULT_HOLD`, `tge_false = timer ≥ FALSE_HOLD`. |
| **Per-state next-state candidates** | `mux2N` chains | Each state computes "where would I go from here":<br>`ns_idle = start_rise ? RANDOM_WAIT : IDLE`<br>`ns_rw = button_rise ? FALSE_START : (tge_rand ? STIMULUS : RANDOM_WAIT)`. Checking the button first gives the early press priority.<br>`ns_stim = MEASURING`<br>`ns_meas = button_rise ? RESULT : MEASURING`<br>`ns_result = (start_rise \| tge_result) ? IDLE : RESULT`<br>`ns_false = tge_false ? IDLE : FALSE_START` |
| **Next-state select** | `generate nsmux`: 6 `and` + 1 `or` per bit | AND-OR multiplexer: each candidate is masked by its `soh[k]` and the results are ORed, so only the current state's candidate passes. An invalid state (6 or 7) gives `000` = `IDLE`, which makes the FSM self-recovering. |
| **Timer** | `eqN u_st_eq` + `not` → `state_changed`; `adderN u_tinc`; `mux2N u_tmux`; `registerN #(32) u_timer` | The timer counts clocks spent in the current state and **clears whenever the state changes**, so every state starts timing from 0. |
| **Random-delay latch** | `eqN u_nrw` + `and(latch_rand, soh[0], next_is_rw)` | Captures `rand_delay` only on the IDLE → RANDOM_WAIT transition, freezing the LFSR value from that moment. |
| **Multiplier** | `mul_const8 u_mul` | `prod = lfsr_value × WAIT_SCALE` (see below). |
| **Delay adder** | `adderN u_radd` | `rand_val = prod + MIN_WAIT`. |
| **Result latch** | `registerN u_result (.en(latch_res))` | Captures `ms_elapsed` on MEASURING → RESULT. It is kept for completeness and is not connected to an output. |
| **Outputs** | `buf`/`or`/`and` on `soh[]` | `counter_reset = IDLE`<br>`lfsr_enable = IDLE \| RANDOM_WAIT`<br>`led_stimulus = STIMULUS \| MEASURING`<br>`counter_start = STIMULUS`<br>`counter_stop = MEASURING & button_rise`. This one also depends on an input, which stops the counter on the same clock as the press.<br>`display_enable = RESULT`<br>`false_start_flag = FALSE_START` |

#### Sub-module `mul_const8`: shift-and-add multiplier

Multiplies an 8-bit value `a` by a constant `K`, the way long multiplication
works in binary:

```
a × K = a[0]·(K<<0) + a[1]·(K<<1) + … + a[7]·(K<<7)
```

- **Partial products:** for each bit `i`, a `mux2N` outputs `K << i` if
  `a[i] = 1`, otherwise 0. `K << i` is a compile-time constant.
- **Sum chain:** seven `adderN`s add the eight partial products one after
  another.

### How `fsm_controller_tb.v` verifies it

**Setup:** tiny timing values make the test fast. `MIN_WAIT=5`,
`WAIT_SCALE=2`, `RESULT_HOLD=8`, `FALSE_HOLD=6`. The testbench drives
`lfsr_value = 3` directly, so `rand_delay = 5 + 3×2 = 11` clocks. It also sets
`ms_elapsed = 250`, standing in for the counter.

**Techniques:**

- **White-box state checking:** the testbench reads the FSM's internal state
  with a **hierarchical reference**, `dut.state`. That is why the RTL keeps a
  net with exactly that name.
- `expect_state(s)` asserts the current state and prints `PASS: in <state>` or
  `FAIL`.
- `wait_for_state(s)` waits until state `s` is reached, with a 1000-clock
  **timeout guard** so a stuck FSM fails instead of hanging the simulation.
- `pulse_start` / `pulse_button` drive one-clock pulses.
- `sname()` turns state numbers into readable names in the log.

**Scenarios:**

1. **Normal path:** after reset, `IDLE` with `counter_reset = 1`. Start →
   `RANDOM_WAIT`. Wait out the delay → `STIMULUS`, with `led_stimulus` and
   `counter_start` both high. One clock later → `MEASURING`, LED still on.
   Press → `counter_stop` is checked high *during the press*, before the clock
   edge, because it is combinational. Then → `RESULT` with `display_enable = 1`,
   and finally the hold time → `IDLE`.
2. **False start:** start → `RANDOM_WAIT` → press after only 2 clocks (well
   before 11) → `FALSE_START` with `false_start_flag = 1` → after the hold →
   `IDLE`.
3. **Leaving RESULT with the start button:** run a trial to `RESULT`, then
   press start → back to `IDLE` immediately, without waiting for the hold time.

Every transition and output in the state table above is checked at least once.

---

## 10. `top.v`: system integration

**Files:** [rtl/top.v](rtl/top.v) · [tb/top_tb.v](tb/top_tb.v)

### Concept

`top` connects all the modules and maps them to the ZYBO board pins defined in
[constraints/zybo_top.xdc](constraints/zybo_top.xdc). It contains almost no
logic of its own, only "glue". All timing values are parameters, so the
testbench can shrink every delay while testing the same top-level design.

### Block-by-block walkthrough

| Block | Code | What it does |
|---|---|---|
| Parameters | `DEBOUNCE_CLKS, CLKS_PER_MS, REFRESH_CLKS, MIN_WAIT_CLKS, …` | Real-hardware defaults for 125 MHz. They are passed down to each sub-module. |
| Ports | `clk, btn_reset, btn_start, pmod_button_in` → `led_stimulus, led_false_start, seg, an` | `btn_start` and `led_false_start` were added beyond the original spec. The FSM needs a way to start a trial, and the false-start indicator should be visible. |
| **Reset synchronizer** | `dffr u_rst0`, `dffr u_rst1` (their own `rst` tied to 0) | Two flops bring the asynchronous reset button into the clock domain. The output `rst` resets every sub-module. |
| **LFSR** | `lfsr u_lfsr (.load(0), .seed_in(0))` | Runs freely from reset. The FSM's `lfsr_enable` output is not connected, because a free-running LFSR randomizes continuously. |
| **Debouncers** | `debounce u_debounce_btn`, `u_debounce_start` | One per button. |
| **FSM** | `fsm_controller u_fsm` | Receives the debounced buttons, the LFSR value and the elapsed ms. Drives the LEDs and the counter controls. |
| **Counter reset** | `or (counter_rst, rst, w_counter_reset)` | The counter is cleared by a system reset **or** whenever the FSM is in `IDLE`. |
| **Counter** | `counter u_counter` | Started and stopped by the FSM. `ms_elapsed` goes to the FSM and the BCD converter. |
| **BCD** | `bcd_converter u_bcd` | `ms_elapsed` → three digits. |
| **Display driver** | `seven_seg_driver u_display` | Outputs `an_int` and `seg_int`. |
| **Display blanking** | `mux2N u_anblank` | `an = display_enable ? an_int : AN_BLANK`. All digits are switched off unless the FSM is in `RESULT`. `AN_BLANK` is all 0s or all 1s depending on `AN_ACTIVE_LOW`. |

### How `top_tb.v` verifies it

This is an **end-to-end, black-box** test. It drives only the real board inputs
(`btn_reset`, `btn_start`, `pmod_button_in`) and reads only the real board
outputs (`led_*`, `seg`, `an`). It also reads `dut.u_fsm.state` and
`dut.ms_elapsed` for logging and cross-checks.

**Shrunk timing:** `DEBOUNCE_CLKS=4`, `CLKS_PER_MS=5` (1 "ms" = 5 clocks),
`REFRESH_CLKS=4`, `MIN_WAIT_CLKS=40`, `WAIT_SCALE=1`, `RESULT_HOLD=150`,
`FALSE_HOLD=25`.

**Helpers:**

- **State monitor:** an `always` block prints a line on every FSM state change,
  for example `[540000] STATE RANDOM_WAIT -> STIMULUS`.
- `press_start` / `press_button` hold the raw button high for
  `DEBOUNCE_CLKS + 4` clocks, long enough to pass the debouncer like a real
  press, then release it.
- **`read_display(value)` reads the display the way a person would.** It
  watches the multiplexed outputs for three full scans. Whenever `an[k]` is
  active, it decodes `seg` back to a digit with `seg_to_digit()`, the inverse of
  the segment table. It then rebuilds `hundreds×100 + tens×10 + ones`. This
  checks the whole display path (BCD → mux → decoder → blanking), not just an
  internal register.
- `run_normal_trial(meas_wait, measured)` runs start → wait for `MEASURING` →
  wait `meas_wait` clocks → press → read the display.

**Scenarios:**

| Scenario | What happens | Checks |
|---|---|---|
| **1. Normal trial** | start, react after 60 clocks | `IDLE` after reset; display blank in `IDLE`; LED off in `RANDOM_WAIT`, on in `MEASURING`, off in `RESULT`; **displayed value == counter's `ms_elapsed`**; the value falls in a plausible range given the wait plus debounce latency; `RESULT` times out back to `IDLE` |
| **2. False start** | start, then press immediately | → `FALSE_START`; false-start LED on; stimulus LED off; → `IDLE` after the hold; false-start LED cleared; display blank |
| **3. Back-to-back trials** | trial A (wait 30), then trial B (wait 75) | between trials the counter is cleared to 0 and the display is blank (re-armed correctly); trial B measures **more** than trial A |

Each scenario prints `SCENARIO n: PASS/FAIL`, and the run ends with
`ALL SCENARIOS PASSED.` or a count of failed assertions.

---

## 11. Running the simulations

### ModelSim (all 7 testbenches in one batch)

From the `sim/` directory:

```bash
vsim -c -do run_modelsim.do
```

[sim/run_modelsim.do](sim/run_modelsim.do) compiles `rtl/primitives.v`
**first**, because every other module depends on it. It then compiles and runs
each RTL/testbench pair in turn.

### Vivado (xsim)

From the `sim/` directory:

```bash
vivado -mode batch -source run_vivado_sim.tcl
```

[sim/run_vivado_sim.tcl](sim/run_vivado_sim.tcl) adds `rtl/*.v`, including
`primitives.v`, as design sources and `tb/top_tb.v` as the simulation top.

To set this up by hand in the Vivado GUI:

- **Design Sources:** all 8 files in `rtl/`. On this branch that **includes
  `primitives.v`**; without it every module fails to elaborate.
- **Simulation Sources:** the testbench you want to run, right-clicked →
  **Set as Top**.
- Constraints are not needed for behavioural simulation.

---

## 12. Verified results

Results from running `sim/run_modelsim.do` on this branch with ModelSim
(Intel FPGA Starter Edition 20.1). All compiles finished with 0 errors and 0
warnings.

| Testbench | Result |
|---|---|
| `lfsr_tb` | Never reached 0x00 over 300 cycles; **period = 255** (maximal length). Sequence starts `FE FC F8 F0 E1 C2 85 0B …` |
| `counter_tb` | 50→5, 123→12, 10→1, 9→0, 1000→100 ms; held at 3 ms after stop. **ALL TESTS PASSED** |
| `debounce_tb` | Bounces rejected; rising and falling latency **22 clocks** (expected 22). **ALL TESTS PASSED** |
| `bcd_converter_tb` | All values 0..999 plus clamp cases. **ALL TESTS PASSED** |
| `seven_seg_driver_tb` | Digits 0–9 encode correctly; one-hot scan with correct digit in each slot. **ALL TESTS PASSED** |
| `fsm_controller_tb` | Normal path, false start, and leaving RESULT with start. **ALL TESTS PASSED** |
| `top_tb` | Scenario 1 measured 13 ms; Scenario 2 false start OK; Scenario 3 trial A = 7 ms, trial B = 16 ms. **ALL SCENARIOS PASSED** |
