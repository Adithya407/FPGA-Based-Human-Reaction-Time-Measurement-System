// -----------------------------------------------------------------------------
// fsm_controller.v -- top-level control FSM for the reaction-time system
//
// States:
//   IDLE        - waiting for the user to start a trial; counter held in reset,
//                 LFSR left running so its captured value is unpredictable.
//   RANDOM_WAIT - random pre-stimulus delay (derived from lfsr_value). A button
//                 press here is an anticipation / false start.
//   STIMULUS    - light the LED and kick off the ms counter (one cycle).
//   MEASURING   - LED on, counter running, waiting for the response press.
//   RESULT      - response captured; enable the display for a few seconds.
//   FALSE_START - flag an early press; hold briefly, then reset.
//
// Transitions:
//   IDLE        -> RANDOM_WAIT   on start_button
//   RANDOM_WAIT -> FALSE_START   if button pressed before the stimulus
//   RANDOM_WAIT -> STIMULUS      after the lfsr-determined delay elapses
//   STIMULUS    -> MEASURING     immediately (start counting)
//   MEASURING   -> RESULT        on button press (stop counting, latch value)
//   RESULT      -> IDLE          after RESULT_HOLD_CLKS, or on start_button
//   FALSE_START -> IDLE          after FALSE_HOLD_CLKS
//
// The random delay is  rand_delay = MIN_WAIT_CLKS + lfsr_value * WAIT_SCALE
// clock cycles. All timing constants are parameters so the testbench can use
// small values; defaults target the 125 MHz system clock.
//
// button and start_button are treated as rising-edge events (the button input
// is expected to come from the debouncer), so holding a button does not
// produce repeated triggers.
//
// STRUCTURAL implementation. The current state lives in a 3-bit `registerN`
// (the net `state` is kept for the testbench's hierarchical reference). It is
// decoded one-hot; the next state is a per-source 2:1 mux network selected by
// that one-hot; the timer/rand_delay/result_ms are `registerN`s fed by
// adder/comparator/mux blocks; and the Moore outputs are gate primitives off
// the one-hot state. The lfsr_value * WAIT_SCALE product uses the structural
// shift-add multiplier `mul_const8`. See primitives.v for the building blocks.
// -----------------------------------------------------------------------------

module fsm_controller #(
    parameter integer MS_WIDTH        = 10,
    parameter integer MIN_WAIT_CLKS   = 125_000_000,  // 1.0 s base delay @125MHz
    parameter integer WAIT_SCALE      = 1_000_000,    // clocks per lfsr unit
    parameter integer RESULT_HOLD_CLKS= 375_000_000,  // ~3 s result display
    parameter integer FALSE_HOLD_CLKS = 125_000_000   // ~1 s false-start hold
) (
    input  wire                clk,
    input  wire                reset,          // synchronous, active-high
    input  wire                button,         // debounced response button
    input  wire [7:0]          lfsr_value,     // pseudo-random value
    input  wire [MS_WIDTH-1:0] ms_elapsed,     // elapsed time from counter
    input  wire                start_button,   // begin a trial

    output wire                led_stimulus,
    output wire                counter_start,
    output wire                counter_stop,
    output wire                counter_reset,
    output wire                lfsr_enable,
    output wire                false_start_flag,
    output wire                display_enable
);

    // State encoding
    localparam [2:0] IDLE        = 3'd0,
                     RANDOM_WAIT = 3'd1,
                     STIMULUS    = 3'd2,
                     MEASURING   = 3'd3,
                     RESULT      = 3'd4,
                     FALSE_START = 3'd5;

    // Timing constants as 32-bit vectors (for the comparators / adders).
    localparam [31:0] MIN_WAIT_C    = MIN_WAIT_CLKS;
    localparam [31:0] RESULT_HOLD_C = RESULT_HOLD_CLKS;
    localparam [31:0] FALSE_HOLD_C  = FALSE_HOLD_CLKS;

    // ------------------------------------------------------------------------
    // State register (net `state` is referenced hierarchically by the TB).
    // ------------------------------------------------------------------------
    wire [2:0] state;
    wire [2:0] next_state;
    registerN #(.WIDTH(3), .RESET_VAL(IDLE)) u_state (
        .clk(clk), .rst(reset), .en(1'b1), .d(next_state), .q(state)
    );

    // One-hot decode of the current state: soh[0]=IDLE .. soh[5]=FALSE_START.
    wire [5:0] soh;
    onehot_decoder #(.SEL_WIDTH(3), .OUT_WIDTH(6)) u_sdec (.sel(state), .onehot(soh));

    // ------------------------------------------------------------------------
    // Rising-edge detection on the (debounced) inputs.
    // ------------------------------------------------------------------------
    wire button_prev, start_prev;
    dffr #(1'b0) u_bprev (.clk(clk), .rst(reset), .en(1'b1), .d(button),       .q(button_prev));
    dffr #(1'b0) u_sprev (.clk(clk), .rst(reset), .en(1'b1), .d(start_button), .q(start_prev));

    wire nbp, nsp, button_rise, start_rise;
    not (nbp, button_prev);  and (button_rise, button,       nbp);
    not (nsp, start_prev);   and (start_rise,  start_button, nsp);

    // ------------------------------------------------------------------------
    // Timer comparisons ( timer >= threshold ).
    // ------------------------------------------------------------------------
    wire [31:0] timer;
    wire [31:0] rand_delay;
    wire        tge_rand, tge_result, tge_false;
    geN #(.WIDTH(32)) u_ge_rand   (.a(timer), .b(rand_delay),    .ge(tge_rand));
    geN #(.WIDTH(32)) u_ge_result (.a(timer), .b(RESULT_HOLD_C), .ge(tge_result));
    geN #(.WIDTH(32)) u_ge_false  (.a(timer), .b(FALSE_HOLD_C),  .ge(tge_false));

    // ------------------------------------------------------------------------
    // Per-source next-state candidates.
    // ------------------------------------------------------------------------
    // IDLE       : start_rise ? RANDOM_WAIT : IDLE
    wire [2:0] ns_idle;
    mux2N #(3) u_ns_idle (.a(IDLE), .b(RANDOM_WAIT), .sel(start_rise), .y(ns_idle));

    // RANDOM_WAIT: button_rise ? FALSE_START : (tge_rand ? STIMULUS : RANDOM_WAIT)
    wire [2:0] ns_rw_inner, ns_rw;
    mux2N #(3) u_ns_rw_i (.a(RANDOM_WAIT), .b(STIMULUS),    .sel(tge_rand),    .y(ns_rw_inner));
    mux2N #(3) u_ns_rw   (.a(ns_rw_inner), .b(FALSE_START), .sel(button_rise), .y(ns_rw));

    // STIMULUS   : always -> MEASURING
    wire [2:0] ns_stim;
    assign ns_stim = MEASURING;   // pure wiring (constant)

    // MEASURING  : button_rise ? RESULT : MEASURING
    wire [2:0] ns_meas;
    mux2N #(3) u_ns_meas (.a(MEASURING), .b(RESULT), .sel(button_rise), .y(ns_meas));

    // RESULT     : (start_rise | tge_result) ? IDLE : RESULT
    wire res_exit;
    or (res_exit, start_rise, tge_result);
    wire [2:0] ns_result;
    mux2N #(3) u_ns_res (.a(RESULT), .b(IDLE), .sel(res_exit), .y(ns_result));

    // FALSE_START: tge_false ? IDLE : FALSE_START
    wire [2:0] ns_false;
    mux2N #(3) u_ns_false (.a(FALSE_START), .b(IDLE), .sel(tge_false), .y(ns_false));

    // ------------------------------------------------------------------------
    // Next-state select: one-hot mux over the candidates (invalid state -> 0).
    // ------------------------------------------------------------------------
    genvar gb;
    generate
        for (gb = 0; gb < 3; gb = gb + 1) begin : nsmux
            wire t0, t1, t2, t3, t4, t5;
            and (t0, ns_idle[gb],   soh[0]);
            and (t1, ns_rw[gb],     soh[1]);
            and (t2, ns_stim[gb],   soh[2]);
            and (t3, ns_meas[gb],   soh[3]);
            and (t4, ns_result[gb], soh[4]);
            and (t5, ns_false[gb],  soh[5]);
            or  (next_state[gb], t0, t1, t2, t3, t4, t5);
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Timer: cleared on any state change, otherwise counts up.
    // ------------------------------------------------------------------------
    wire state_eq, state_changed;
    eqN #(3) u_st_eq (.a(state), .b(next_state), .eq(state_eq));
    not (state_changed, state_eq);

    wire [31:0] timer_p1, timer_next;
    wire        timer_co;
    adderN #(.WIDTH(32)) u_tinc (
        .a(timer), .b(32'd0), .cin(1'b1), .sum(timer_p1), .cout(timer_co)
    );
    mux2N #(.WIDTH(32)) u_tmux (
        .a(timer_p1), .b(32'd0), .sel(state_changed), .y(timer_next)
    );
    registerN #(.WIDTH(32), .RESET_VAL(32'd0)) u_timer (
        .clk(clk), .rst(reset), .en(1'b1), .d(timer_next), .q(timer)
    );

    // ------------------------------------------------------------------------
    // rand_delay: latched on IDLE -> RANDOM_WAIT.
    //   rand_delay = MIN_WAIT_CLKS + lfsr_value * WAIT_SCALE
    // ------------------------------------------------------------------------
    wire next_is_rw, latch_rand;
    eqN #(3) u_nrw (.a(next_state), .b(RANDOM_WAIT), .eq(next_is_rw));
    and (latch_rand, soh[0], next_is_rw);

    wire [31:0] prod, rand_val;
    wire        rand_co;
    mul_const8 #(.OUTW(32), .K(WAIT_SCALE)) u_mul (.a(lfsr_value), .out(prod));
    adderN #(.WIDTH(32)) u_radd (
        .a(prod), .b(MIN_WAIT_C), .cin(1'b0), .sum(rand_val), .cout(rand_co)
    );
    registerN #(.WIDTH(32), .RESET_VAL(32'd0)) u_rand (
        .clk(clk), .rst(reset), .en(latch_rand), .d(rand_val), .q(rand_delay)
    );

    // ------------------------------------------------------------------------
    // result_ms: latched on MEASURING -> RESULT (mirrors the original design;
    // captured for completeness but not driven onto an output).
    // ------------------------------------------------------------------------
    wire [MS_WIDTH-1:0] result_ms;
    wire next_is_result, latch_res;
    eqN #(3) u_nres (.a(next_state), .b(RESULT), .eq(next_is_result));
    and (latch_res, soh[3], next_is_result);
    registerN #(.WIDTH(MS_WIDTH), .RESET_VAL({MS_WIDTH{1'b0}})) u_result (
        .clk(clk), .rst(reset), .en(latch_res), .d(ms_elapsed), .q(result_ms)
    );

    // ------------------------------------------------------------------------
    // Moore outputs (functions of the one-hot state; counter_stop also gated
    // by the response edge while MEASURING).
    // ------------------------------------------------------------------------
    buf (counter_reset,    soh[0]);                 // IDLE
    or  (lfsr_enable,      soh[0], soh[1]);         // IDLE | RANDOM_WAIT
    or  (led_stimulus,     soh[2], soh[3]);         // STIMULUS | MEASURING
    buf (counter_start,    soh[2]);                 // STIMULUS
    and (counter_stop,     soh[3], button_rise);    // MEASURING & response edge
    buf (display_enable,   soh[4]);                 // RESULT
    buf (false_start_flag, soh[5]);                 // FALSE_START

endmodule


// -----------------------------------------------------------------------------
// mul_const8 -- structural unsigned multiply of an 8-bit value by a compile-
//               time constant K.  out = a * K  (low OUTW bits).
//
// Shift-add: partial product i is (K << i) when a[i]=1, else 0 (a 2:1 mux
// against zero). The eight partial products are summed by a chain of adderN.
// -----------------------------------------------------------------------------
module mul_const8 #(
    parameter integer OUTW = 32,
    parameter integer K    = 1
) (
    input  wire [7:0]      a,
    output wire [OUTW-1:0] out
);
    wire [OUTW-1:0] pp  [0:7];   // partial products
    wire [OUTW-1:0] acc [0:7];   // running sums
    wire [7:0]      co;

    genvar i;
    generate
        // Partial products: pp[i] = a[i] ? (K << i) : 0.
        for (i = 0; i < 8; i = i + 1) begin : ppg
            localparam [OUTW-1:0] KI = (K << i);
            mux2N #(.WIDTH(OUTW)) sel (
                .a ({OUTW{1'b0}}), .b (KI), .sel (a[i]), .y (pp[i])
            );
        end

        // Sum chain: acc[0] = pp[0]; acc[i] = acc[i-1] + pp[i].
        adderN #(.WIDTH(OUTW)) a0 (
            .a(pp[0]), .b({OUTW{1'b0}}), .cin(1'b0), .sum(acc[0]), .cout(co[0])
        );
        for (i = 1; i < 8; i = i + 1) begin : sumg
            adderN #(.WIDTH(OUTW)) ad (
                .a(acc[i-1]), .b(pp[i]), .cin(1'b0), .sum(acc[i]), .cout(co[i])
            );
        end
    endgenerate

    assign out = acc[7];   // pure wiring (whole-word alias)
endmodule
