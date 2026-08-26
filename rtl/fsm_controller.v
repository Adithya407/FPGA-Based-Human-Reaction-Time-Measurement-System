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

    output reg                 led_stimulus,
    output reg                 counter_start,
    output reg                 counter_stop,
    output reg                 counter_reset,
    output reg                 lfsr_enable,
    output reg                 false_start_flag,
    output reg                 display_enable
);

    // State encoding
    localparam [2:0] IDLE        = 3'd0,
                     RANDOM_WAIT = 3'd1,
                     STIMULUS    = 3'd2,
                     MEASURING   = 3'd3,
                     RESULT      = 3'd4,
                     FALSE_START = 3'd5;

    reg [2:0]  state, next_state;
    reg [31:0] timer;        // cycles spent in the current state
    reg [31:0] rand_delay;   // latched random-wait target
    reg [MS_WIDTH-1:0] result_ms;  // latched reaction time

    // Edge detection for the (debounced) inputs
    reg        button_prev, start_prev;
    wire       button_rise = button       & ~button_prev;
    wire       start_rise  = start_button & ~start_prev;

    // --- Next-state logic ---------------------------------------------------
    always @* begin
        next_state = state;
        case (state)
            IDLE:        if (start_rise)                  next_state = RANDOM_WAIT;
            RANDOM_WAIT: if (button_rise)                 next_state = FALSE_START;
                         else if (timer >= rand_delay)    next_state = STIMULUS;
            STIMULUS:                                     next_state = MEASURING;
            MEASURING:   if (button_rise)                 next_state = RESULT;
            RESULT:      if (start_rise ||
                             timer >= RESULT_HOLD_CLKS)   next_state = IDLE;
            FALSE_START: if (timer >= FALSE_HOLD_CLKS)    next_state = IDLE;
            default:                                      next_state = IDLE;
        endcase
    end

    // --- State / datapath registers -----------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state       <= IDLE;
            timer       <= 32'd0;
            rand_delay  <= 32'd0;
            result_ms   <= {MS_WIDTH{1'b0}};
            button_prev <= 1'b0;
            start_prev  <= 1'b0;
        end
        else begin
            button_prev <= button;
            start_prev  <= start_button;

            // Latch a fresh random delay when a trial begins.
            if (state == IDLE && next_state == RANDOM_WAIT)
                rand_delay <= MIN_WAIT_CLKS + lfsr_value * WAIT_SCALE;

            // Latch the reaction time when the response is captured.
            if (state == MEASURING && next_state == RESULT)
                result_ms <= ms_elapsed;

            // Restart the timer on every state change; otherwise count up.
            if (state != next_state)
                timer <= 32'd0;
            else
                timer <= timer + 32'd1;

            state <= next_state;
        end
    end

    // --- Moore outputs ------------------------------------------------------
    always @* begin
        led_stimulus     = 1'b0;
        counter_start    = 1'b0;
        counter_stop     = 1'b0;
        counter_reset    = 1'b0;
        lfsr_enable      = 1'b0;
        false_start_flag = 1'b0;
        display_enable   = 1'b0;

        case (state)
            IDLE: begin
                counter_reset = 1'b1;   // clear any previous measurement
                lfsr_enable   = 1'b1;   // keep the LFSR shifting
            end
            RANDOM_WAIT: begin
                lfsr_enable = 1'b1;
            end
            STIMULUS: begin
                led_stimulus  = 1'b1;
                counter_start = 1'b1;   // one-cycle kick -> counter begins
            end
            MEASURING: begin
                led_stimulus = 1'b1;
                if (button_rise)
                    counter_stop = 1'b1;  // freeze/latch on the response press
            end
            RESULT: begin
                display_enable = 1'b1;
            end
            FALSE_START: begin
                false_start_flag = 1'b1;
            end
            default: ;
        endcase
    end

endmodule
