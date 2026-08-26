# Option 3 — Practical (mixed) structural modelling

This is an **alternative** to the full structural conversion that lives on the
`Struct_mod` branch. Follow this document on a **new branch** to produce a
*mixed* design: convert only the modules that are clean to express as a netlist,
and deliberately leave the heavy-arithmetic modules behavioral.

> `Struct_mod` = **Option 1** (every RTL module rebuilt from building blocks).
> This document = **Option 3** (practical subset structural, the rest behavioral).

---

## 1. Goal

| Module | Option 3 style | Why |
|---|---|---|
| `lfsr.v` | **Structural** | 8-bit shift register + one XOR + two muxes — trivial as a netlist. |
| `debounce.v` | **Structural** | 2-FF synchronizer + a counter with equality tests. |
| `counter.v` | **Structural** | Prescaler + saturating ms counter; only needs adders/comparators/muxes. |
| `seven_seg_driver.v` | **Structural** | Two wrap counters + a one-hot decoder + a gate-level BCD→7-seg decoder. |
| `bcd_converter.v` | **Behavioral (leave as-is)** | Unrolled 10-iteration double-dabble; the behavioral `for`/`if` form is far more readable and less error-prone than a hand-wired stage chain. |
| `fsm_controller.v` | **Behavioral (leave as-is)** | Contains `lfsr_value * WAIT_SCALE` (a multiply) and 32-bit timers/comparators; a structural version needs a shift-add multiplier and is much larger with no functional benefit. |
| `top.v` | **Structural netlist** (already is) | Pure module instantiation; keep it as a netlist. Its tiny glue (reset sync, display-blank) may stay behavioral or use primitives — either is fine. |

**Hard constraint — do not change any module's interface.** Keep every port
name, direction, width, and parameter, and keep these *internal* net names,
because the testbenches and `sim/run_vivado_sim.tcl` reach into them
hierarchically:

- `fsm_controller`: a 3-bit net named **`state`** with encoding
  `IDLE=0, RANDOM_WAIT=1, STIMULUS=2, MEASURING=3, RESULT=4, FALSE_START=5`.
- `top`: instance **`u_fsm`**, and nets **`ms_elapsed`**, **`lfsr_value`**,
  **`button_db`**, **`start_db`**.

---

## 2. The fast recipe (recommended)

Because Option 1 already produced verified structural versions of the four
"practical" modules plus the `primitives.v` library, Option 3 is mostly a
**file cherry-pick**, not a rewrite.

```bash
# Start from the original all-behavioral code.
git checkout main
git checkout -b Struct_mod_practical

# Bring in the shared building-block library and the four structural modules
# from the full-structural branch.
git checkout Struct_mod -- rtl/primitives.v
git checkout Struct_mod -- rtl/lfsr.v
git checkout Struct_mod -- rtl/debounce.v
git checkout Struct_mod -- rtl/counter.v
git checkout Struct_mod -- rtl/seven_seg_driver.v

# Leave rtl/bcd_converter.v and rtl/fsm_controller.v as the ORIGINAL behavioral
# versions (do nothing — they are already behavioral on main).
#
# rtl/top.v: keep the original (behavioral glue) for a minimal diff, OR take the
# structural-glue version with:  git checkout Struct_mod -- rtl/top.v
# Both pass; the original keeps the diff smaller.
```

Then make the ModelSim script compile the library first (see §4), and verify
(see §5). That's it — no module rewriting required.

> The four structural files instantiate blocks from `primitives.v`; the two
> behavioral files (`bcd_converter`, `fsm_controller`) do not depend on it. They
> all share the same interfaces, so `top` wires them together unchanged.

---

## 3. Alternative: convert from scratch

If you would rather write the four structural modules yourself instead of
cherry-picking, use the `Struct_mod` versions as the reference implementation
and keep to this house style (documented at the top of `rtl/primitives.v`):

- Realize **all logic** with gate primitives (`and/or/xor/not/buf/xnor`) or by
  instantiating library blocks (`dffr`, `registerN`, `adderN`, `mux2N`, `eqN`,
  `geN`, `gtN`, `onehot_decoder`).
- Use continuous `assign` **only** for pure wiring — net aliases,
  concatenations, constant tie-offs — never for a logic/arithmetic operator.
- The one behavioral leaf is the flip-flop (`dffr`); build every register from
  it via `registerN`.

Per-module cheat-sheet:

- **lfsr** — `feedback = xor(state[7],state[5],state[4],state[3])`; next value
  is `load ? (seed==0 ? SEED : seed) : {state[6:0],feedback}` via two `mux2N`
  and one `eqN`; state is a `registerN #(8, SEED)`.
- **debounce** — two `dffr` for the synchronizer; a `registerN` counter cleared
  when the level matches the output (`xnor`) or the window elapses (`eqN` vs
  `STABLE_COUNT-1`); output `dffr` whose enable is `at_window & ~match`.
- **counter** — derive the three priority events
  `c_start=start&~running`, `c_stop=stop&running&~c_start`,
  `c_run=running&~c_start&~c_stop`, then drive `running`/`done`/`prescale`/`ms`
  registers (adders + `eqN` for the prescaler wrap and the ms saturation).
- **seven_seg_driver** — refresh prescaler and digit-index `registerN`s with
  `eqN`-based wrap; `onehot_decoder` drives both the anodes and an AND/OR input
  mux; a gate-level sum-of-minterms `seg7_decoder`; output polarity by a
  `generate`-`if` of `buf`/`not`.

---

## 4. Simulation script change

`sim/run_modelsim.do` must compile the library **before** any structural module
(the `work` library persists across the `vlog` calls). Add this right after
`vmap work work`:

```tcl
# --- Structural primitives library (needed by the structural modules) --------
vlog ../rtl/primitives.v
```

`sim/run_vivado_sim.tcl` needs **no change** — it already adds every RTL file
with `glob $rtl_dir/*.v`, so `primitives.v` is picked up automatically.

---

## 5. Verification (must pass, unchanged testbenches)

ModelSim (`$finish` exits the batch session, so run each testbench in its own
process). From `sim/`:

```bash
export PATH="/c/intelFPGA/20.1/modelsim_ase/win32aloem:$PATH"
rm -rf work && vlib work && vmap work work
vlog -work work ../rtl/primitives.v ../rtl/lfsr.v ../rtl/counter.v \
  ../rtl/debounce.v ../rtl/bcd_converter.v ../rtl/seven_seg_driver.v \
  ../rtl/fsm_controller.v ../rtl/top.v ../tb/*.v
for tb in lfsr_tb counter_tb debounce_tb bcd_converter_tb \
          seven_seg_driver_tb fsm_controller_tb top_tb; do
  echo "----- $tb -----"
  vsim -c -do "run -all; quit -f" work.$tb 2>&1 \
    | grep -iE "ALL TESTS|ALL SCENARIOS|TEST\(S\) FAILED|ASSERTION|FAIL:"
done
```

Vivado (xsim), from `sim/`:

```bash
vivado -mode batch -source run_vivado_sim.tcl
```

**Acceptance criteria**

- Every module testbench prints `ALL TESTS PASSED.`
- `top_tb` prints `ALL SCENARIOS PASSED.`
- Zero compile errors/warnings.
- No `'<net>' is not declared under prefix 'dut'` errors (means an internal net
  name from §1 was renamed — restore it).

---

## 6. Trade-off vs Option 1

- **Pro:** smaller, more readable diff; the genuinely awkward logic (double-
  dabble, multiply, 32-bit FSM datapath) stays in its clear behavioral form.
- **Con:** it is a *mixed* modelling style, so it does not satisfy a strict
  "everything must be structural" requirement — that is what `Struct_mod`
  (Option 1) is for.
