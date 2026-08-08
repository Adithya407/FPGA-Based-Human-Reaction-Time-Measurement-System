// -----------------------------------------------------------------------------
// top.v -- top-level integration for the FPGA reaction-time measurement system
//          (Digilent ZYBO, Zynq-7000, 125 MHz PL clock)
//
// Ties together:
//   lfsr              -> pseudo-random pre-stimulus delay source
//   debounce (x2)     -> clean the response button and the start button
//   fsm_controller    -> sequences the whole trial and drives control signals
//   counter           -> measures elapsed reaction time in milliseconds
//   bcd_converter     -> binary ms -> 3 decimal digits
//   seven_seg_driver  -> multiplexes the digits onto the PMOD 7-seg display
//
// Dataflow / control:
//   pmod_button_in --[debounce]--> button ---> FSM
//   btn_start      --[debounce]--> start ----> FSM
//   FSM.counter_start/stop/reset -> counter ; counter.ms -> FSM & BCD
//   FSM.led_stimulus -> onboard/stimulus LED
//   FSM.display_enable gates the 7-seg anodes (blank until a result is ready)
//   BCD digits -> seven_seg_driver -> seg[] / an[]
//
// NOTE on the port list: the requested ports (clk, btn_reset, pmod_button_in,
// led_stimulus, seg/an) do not include a way to *start* a trial, which the FSM
// requires. `btn_start` is therefore added as a required input. `led_false_start`
// is also exposed so an early press is visible on an onboard LED. Both are
// clearly marked below; remove/remap them in the .xdc as your board wiring
// dictates.
// -----------------------------------------------------------------------------

module top #(
    // System / timing parameters (defaults target the 125 MHz PL clock).
    parameter integer CLK_HZ           = 125_000_000,
    parameter integer MS_WIDTH         = 10,          // ms output width (0..1023)
    parameter integer NUM_DIGITS       = 3,           // 7-seg digits (h,t,o)

    parameter integer DEBOUNCE_CLKS    = 1_250_000,   // ~10 ms @ 125 MHz
    parameter integer CLKS_PER_MS      = 125_000,     // 125 MHz -> 1 ms tick
    parameter integer REFRESH_CLKS     = 41_667,      // ~1 kHz/digit refresh

    // FSM timing (see fsm_controller.v). Defaults: ~1 s base random delay,
    // up to ~+2 s from the LFSR, ~3 s result display, ~1 s false-start hold.
    parameter integer MIN_WAIT_CLKS    = 125_000_000,
    parameter integer WAIT_SCALE       = 1_000_000,
    parameter integer RESULT_HOLD_CLKS = 375_000_000,
    parameter integer FALSE_HOLD_CLKS  = 125_000_000,

    // Display electrical polarity -- set per the PMOD SSD wiring.
    parameter         SEG_ACTIVE_LOW   = 1'b0,
    parameter         AN_ACTIVE_LOW    = 1'b0
) (
    input  wire                  clk,             // 125 MHz PL clock
    input  wire                  btn_reset,       // active-high reset (push-button)
    input  wire                  btn_start,       // ADDED: start-a-trial push-button
    input  wire                  pmod_button_in,  // raw PMOD response button

    output wire                  led_stimulus,    // stimulus LED
    output wire                  led_false_start, // ADDED: false-start indicator LED

    output wire [6:0]            seg,             // 7-seg segments a..g (matches driver)
    output wire [NUM_DIGITS-1:0] an              // 7-seg digit-select   (matches driver)
);

    // -------------------------------------------------------------------------
    // Reset synchronizer: bring the (bouncy/async) reset button into the clock
    // domain. Active-high system reset used by every sub-module.
    // -------------------------------------------------------------------------
    reg [1:0] rst_sync_ff;
    always @(posedge clk)
        rst_sync_ff <= {rst_sync_ff[0], btn_reset};
    wire rst = rst_sync_ff[1];

    // -------------------------------------------------------------------------
    // Inter-module nets
    // -------------------------------------------------------------------------
    wire [7:0]          lfsr_value;      // LFSR state -> FSM (random delay seed)
    wire                button_db;       // debounced response button -> FSM
    wire                start_db;        // debounced start button    -> FSM
    wire [MS_WIDTH-1:0] ms_elapsed;      // counter -> FSM & BCD
    wire                counter_done;    // counter status (unused at top)
    wire                counter_running; // counter status (unused at top)
    wire [3:0]          bcd_hundreds, bcd_tens, bcd_ones;
    wire [NUM_DIGITS-1:0] an_int;        // pre-blanking anodes from the driver
    wire [6:0]          seg_int;         // segment bus from the driver

    // FSM control/status outputs
    wire w_led_stimulus;
    wire w_counter_start;
    wire w_counter_stop;
    wire w_counter_reset;
    wire w_lfsr_enable;      // available; the LFSR free-runs (no enable port)
    wire w_false_start;
    wire w_display_enable;

    // -------------------------------------------------------------------------
    // LFSR: free-running pseudo-random source. Reset loads the non-zero SEED;
    // no external load. The FSM captures `lfsr_value` when a trial starts, so
    // the effective delay depends on the (unpredictable) start timing.
    // (w_lfsr_enable is provided by the FSM but this LFSR has no enable input;
    //  free-running gives continuous randomization -- left unconnected here.)
    // -------------------------------------------------------------------------
    lfsr #(
        .SEED (8'hFF)
    ) u_lfsr (
        .clk     (clk),
        .rst     (rst),
        .load    (1'b0),          // never externally loaded
        .seed_in (8'h00),         // unused when load = 0
        .value   (lfsr_value)
    );

    // -------------------------------------------------------------------------
    // Debounce #1: PMOD response button -> clean `button_db` for the FSM.
    // -------------------------------------------------------------------------
    debounce #(
        .STABLE_COUNT (DEBOUNCE_CLKS)
    ) u_debounce_btn (
        .clk     (clk),
        .rst     (rst),
        .btn_in  (pmod_button_in),
        .btn_out (button_db)
    );

    // -------------------------------------------------------------------------
    // Debounce #2: start-trial button -> clean `start_db` for the FSM.
    // -------------------------------------------------------------------------
    debounce #(
        .STABLE_COUNT (DEBOUNCE_CLKS)
    ) u_debounce_start (
        .clk     (clk),
        .rst     (rst),
        .btn_in  (btn_start),
        .btn_out (start_db)
    );

    // -------------------------------------------------------------------------
    // FSM controller: sequences the trial and drives all control signals.
    //   inputs : debounced buttons, LFSR value, elapsed ms
    //   outputs: LED, counter start/stop/reset, false-start & display flags
    // -------------------------------------------------------------------------
    fsm_controller #(
        .MS_WIDTH         (MS_WIDTH),
        .MIN_WAIT_CLKS    (MIN_WAIT_CLKS),
        .WAIT_SCALE       (WAIT_SCALE),
        .RESULT_HOLD_CLKS (RESULT_HOLD_CLKS),
        .FALSE_HOLD_CLKS  (FALSE_HOLD_CLKS)
    ) u_fsm (
        .clk              (clk),
        .reset            (rst),
        .button           (button_db),      // <- debounce #1
        .lfsr_value       (lfsr_value),     // <- LFSR
        .ms_elapsed       (ms_elapsed),     // <- counter
        .start_button     (start_db),       // <- debounce #2
        .led_stimulus     (w_led_stimulus),
        .counter_start    (w_counter_start),
        .counter_stop     (w_counter_stop),
        .counter_reset    (w_counter_reset),
        .lfsr_enable      (w_lfsr_enable),
        .false_start_flag (w_false_start),
        .display_enable   (w_display_enable)
    );

    // -------------------------------------------------------------------------
    // Counter: elapsed reaction-time in ms.
    //   rst  = system reset OR the FSM's counter_reset (held clear in IDLE)
    //   start/stop = FSM pulses (start in STIMULUS, stop on the response press)
    //   ms   -> FSM (ms_elapsed) and BCD converter
    // -------------------------------------------------------------------------
    counter #(
        .CLKS_PER_MS (CLKS_PER_MS),
        .MS_WIDTH    (MS_WIDTH)
    ) u_counter (
        .clk     (clk),
        .rst     (rst | w_counter_reset),
        .start   (w_counter_start),
        .stop    (w_counter_stop),
        .ms      (ms_elapsed),
        .done    (counter_done),
        .running (counter_running)
    );

    // -------------------------------------------------------------------------
    // BCD converter: binary ms -> three decimal digits for the display.
    // -------------------------------------------------------------------------
    bcd_converter #(
        .IN_WIDTH (MS_WIDTH)
    ) u_bcd (
        .bin      (ms_elapsed),
        .hundreds (bcd_hundreds),
        .tens     (bcd_tens),
        .ones     (bcd_ones)
    );

    // -------------------------------------------------------------------------
    // Seven-segment driver: multiplex the three BCD digits.
    // -------------------------------------------------------------------------
    seven_seg_driver #(
        .NUM_DIGITS     (NUM_DIGITS),
        .REFRESH_CLKS   (REFRESH_CLKS),
        .SEG_ACTIVE_LOW (SEG_ACTIVE_LOW),
        .AN_ACTIVE_LOW  (AN_ACTIVE_LOW)
    ) u_display (
        .clk      (clk),
        .rst      (rst),
        .hundreds (bcd_hundreds),
        .tens     (bcd_tens),
        .ones     (bcd_ones),
        .an       (an_int),
        .seg      (seg_int)
    );

    // -------------------------------------------------------------------------
    // Output wiring
    // -------------------------------------------------------------------------
    assign led_stimulus    = w_led_stimulus;
    assign led_false_start = w_false_start;

    // Segments pass through untouched.
    assign seg = seg_int;

    // Blank the display (drive all anodes inactive) unless the FSM says a
    // result is ready. Inactive anode level depends on AN_ACTIVE_LOW.
    //   active-high select: inactive = 0 ; active-low select: inactive = 1
    localparam [NUM_DIGITS-1:0] AN_BLANK =
        AN_ACTIVE_LOW ? {NUM_DIGITS{1'b1}} : {NUM_DIGITS{1'b0}};

    assign an = w_display_enable ? an_int : AN_BLANK;

endmodule
