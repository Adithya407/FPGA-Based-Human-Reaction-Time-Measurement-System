// -----------------------------------------------------------------------------
// top_tb.v -- comprehensive top-level testbench for rtl/top.v
//
// Drives the raw board inputs (buttons held long enough to clear debounce) and
// exercises the full integrated system through three scenarios:
//
//   Scenario 1  Normal trial: start -> random delay -> led_stimulus -> wait a
//               fixed number of cycles -> press -> reach RESULT and read back a
//               plausible ms value from the multiplexed display outputs.
//   Scenario 2  False start: press during RANDOM_WAIT -> FALSE_START -> clean
//               reset back to IDLE.
//   Scenario 3  Two back-to-back trials: confirm the system returns to IDLE,
//               clears the previous result, and re-arms for the next trial.
//
// State transitions and measured values are printed with $display; every
// scenario ends with a PASS/FAIL summary based on assertion counts.
//
// The displayed value is reconstructed the "real" way: by watching which anode
// is active and decoding the segment bus, then combining the three digits.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module top_tb;

    // ---- Shrunk timing so the sim runs quickly -----------------------------
    localparam integer MS_WIDTH         = 10;
    localparam integer NUM_DIGITS       = 3;
    localparam integer DEBOUNCE_CLKS    = 4;
    localparam integer CLKS_PER_MS      = 5;    // 5 clocks = 1 "ms" in sim
    localparam integer REFRESH_CLKS     = 4;
    localparam integer MIN_WAIT_CLKS    = 40;   // >> debounce latency
    localparam integer WAIT_SCALE       = 1;
    localparam integer RESULT_HOLD_CLKS = 150;  // long enough to scan display
    localparam integer FALSE_HOLD_CLKS  = 25;

    // FSM state encoding (must match fsm_controller.v).
    localparam [2:0] IDLE=3'd0, RANDOM_WAIT=3'd1, STIMULUS=3'd2,
                     MEASURING=3'd3, RESULT=3'd4, FALSE_START=3'd5;

    reg                    clk;
    reg                    btn_reset;
    reg                    btn_start;
    reg                    pmod_button_in;
    wire                   led_stimulus;
    wire                   led_false_start;
    wire [6:0]             seg;
    wire [NUM_DIGITS-1:0]  an;

    integer errors;        // total across all scenarios
    integer scn_errors;    // snapshot for per-scenario summary
    integer guard;

    // ---- DUT ---------------------------------------------------------------
    top #(
        .MS_WIDTH         (MS_WIDTH),
        .NUM_DIGITS       (NUM_DIGITS),
        .DEBOUNCE_CLKS    (DEBOUNCE_CLKS),
        .CLKS_PER_MS      (CLKS_PER_MS),
        .REFRESH_CLKS     (REFRESH_CLKS),
        .MIN_WAIT_CLKS    (MIN_WAIT_CLKS),
        .WAIT_SCALE       (WAIT_SCALE),
        .RESULT_HOLD_CLKS (RESULT_HOLD_CLKS),
        .FALSE_HOLD_CLKS  (FALSE_HOLD_CLKS)
    ) dut (
        .clk             (clk),
        .btn_reset       (btn_reset),
        .btn_start       (btn_start),
        .pmod_button_in  (pmod_button_in),
        .led_stimulus    (led_stimulus),
        .led_false_start (led_false_start),
        .seg             (seg),
        .an              (an)
    );

    // 125 MHz clock (8 ns period)
    initial clk = 1'b0;
    always #4 clk = ~clk;

    // ---- Helpers -----------------------------------------------------------

    // Readable state names for logging.
    function [8*12-1:0] sname(input [2:0] s);
        case (s)
            IDLE:        sname = "IDLE";
            RANDOM_WAIT: sname = "RANDOM_WAIT";
            STIMULUS:    sname = "STIMULUS";
            MEASURING:   sname = "MEASURING";
            RESULT:      sname = "RESULT";
            FALSE_START: sname = "FALSE_START";
            default:     sname = "??";
        endcase
    endfunction

    // Reverse the active-high 7-seg encoding back to a digit (15 = unknown).
    function integer seg_to_digit(input [6:0] s);
        case (s)
            7'b1111110: seg_to_digit = 0;
            7'b0110000: seg_to_digit = 1;
            7'b1101101: seg_to_digit = 2;
            7'b1111001: seg_to_digit = 3;
            7'b0110011: seg_to_digit = 4;
            7'b1011011: seg_to_digit = 5;
            7'b1011111: seg_to_digit = 6;
            7'b1110000: seg_to_digit = 7;
            7'b1111111: seg_to_digit = 8;
            7'b1111011: seg_to_digit = 9;
            default:    seg_to_digit = 15;
        endcase
    endfunction

    // Print every FSM state change as it happens (enabled after reset settles,
    // so the X->IDLE reset noise is not logged).
    reg [2:0] prev_state;
    reg       mon_en;
    initial begin prev_state = 3'd7; mon_en = 1'b0; end
    always @(posedge clk) begin
        if (dut.u_fsm.state !== prev_state) begin
            if (mon_en)
                $display("  [%0t] STATE %0s -> %0s", $time,
                         sname(prev_state), sname(dut.u_fsm.state));
            prev_state <= dut.u_fsm.state;
        end
    end

    // Assertion helper.
    task check(input cond, input [8*48-1:0] msg);
        begin
            if (cond) $display("  PASS: %0s", msg);
            else begin errors = errors + 1; $display("  FAIL: %0s", msg); end
        end
    endtask

    // Wait (guarded) until the FSM reaches state s.
    task wait_for_state(input [2:0] s);
        begin
            guard = 0;
            while (dut.u_fsm.state !== s && guard < 8000) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            if (guard >= 8000) begin
                errors = errors + 1;
                $display("  FAIL: timed out waiting for %0s (in %0s) @%0t",
                         sname(s), sname(dut.u_fsm.state), $time);
            end
        end
    endtask

    // Hold a button high long enough to debounce and register the edge.
    task press_start;
        begin
            @(negedge clk); btn_start = 1'b1;
            repeat (DEBOUNCE_CLKS + 4) @(posedge clk);
            @(negedge clk); btn_start = 1'b0;
            repeat (DEBOUNCE_CLKS + 4) @(posedge clk);
        end
    endtask

    task press_button;
        begin
            @(negedge clk); pmod_button_in = 1'b1;
            repeat (DEBOUNCE_CLKS + 4) @(posedge clk);
            @(negedge clk); pmod_button_in = 1'b0;
            repeat (DEBOUNCE_CLKS + 4) @(posedge clk);
        end
    endtask

    // Scan the multiplexed display over a few full refresh cycles and rebuild
    // the 3-digit value from the segment/anode outputs.
    task read_display(output integer value);
        integer i, h, t, o;
        reg got_h, got_t, got_o;
        integer d;
        begin
            h = 0; t = 0; o = 0;
            got_h = 1'b0; got_t = 1'b0; got_o = 1'b0;
            for (i = 0; i < NUM_DIGITS*REFRESH_CLKS*3; i = i + 1) begin
                @(posedge clk); #1;
                d = seg_to_digit(seg);
                if (an[0]) begin o = d; got_o = 1'b1; end
                if (an[1]) begin t = d; got_t = 1'b1; end
                if (an[2]) begin h = d; got_h = 1'b1; end
            end
            if (!got_h || !got_t || !got_o)
                $display("  WARN: not all digits sampled (h=%b t=%b o=%b)",
                         got_h, got_t, got_o);
            value = h*100 + t*10 + o;
        end
    endtask

    // Run one full normal trial: start -> wait -> stimulus -> (meas_wait) ->
    // press -> RESULT. Returns the value read from the display.
    task run_normal_trial(input integer meas_wait, output integer measured);
        integer lo, hi;
        begin
            press_start;
            check(dut.u_fsm.state === RANDOM_WAIT, "start -> RANDOM_WAIT");
            check(led_stimulus === 1'b0, "stimulus LED off in RANDOM_WAIT");

            wait_for_state(STIMULUS);
            wait_for_state(MEASURING);
            check(led_stimulus === 1'b1, "stimulus LED on in MEASURING");

            // Fixed "reaction time" before pressing.
            repeat (meas_wait) @(posedge clk);
            press_button;

            check(dut.u_fsm.state === RESULT, "response -> RESULT");
            check(led_stimulus === 1'b0, "stimulus LED off in RESULT");

            read_display(measured);
            $display("  MEASURED (display) = %0d ms ; counter ms_elapsed = %0d",
                     measured, dut.ms_elapsed);

            // Display must match the counter feeding the BCD converter.
            check(measured === dut.ms_elapsed, "display value == counter ms");

            // Plausible band given the fixed wait + debounce/start latency.
            lo = (meas_wait / CLKS_PER_MS);
            if (lo > 1) lo = lo - 1; else lo = 0;
            hi = (meas_wait + DEBOUNCE_CLKS + 8) / CLKS_PER_MS + 1;
            check(measured >= lo && measured <= hi, "measured ms is plausible");
        end
    endtask

    // ---- Stimulus ----------------------------------------------------------
    integer meas1, meas2, meas3;

    initial begin
        errors         = 0;
        btn_reset      = 1'b1;
        btn_start      = 1'b0;
        pmod_button_in = 1'b0;

        repeat (4) @(posedge clk);
        @(negedge clk); btn_reset = 1'b0;
        repeat (4) @(posedge clk); #1;
        mon_en = 1'b1;   // start logging state transitions

        // =================================================================
        $display("\n==== SCENARIO 1: NORMAL TRIAL ====");
        scn_errors = errors;
        check(dut.u_fsm.state === IDLE, "reset -> IDLE");
        check(an === {NUM_DIGITS{1'b0}}, "display blanked in IDLE");

        run_normal_trial(60, meas1);

        // Let the RESULT hold expire back to IDLE.
        wait_for_state(IDLE);
        check(dut.u_fsm.state === IDLE, "RESULT hold -> IDLE");
        if (scn_errors == errors) $display("SCENARIO 1: PASS"); else $display("SCENARIO 1: FAIL");

        // =================================================================
        $display("\n==== SCENARIO 2: FALSE START ====");
        scn_errors = errors;

        press_start;
        check(dut.u_fsm.state === RANDOM_WAIT, "start -> RANDOM_WAIT");

        // Press early, well before MIN_WAIT_CLKS elapses.
        press_button;
        check(dut.u_fsm.state === FALSE_START, "early press -> FALSE_START");
        check(led_false_start === 1'b1, "false-start LED asserted");
        check(led_stimulus === 1'b0, "stimulus LED off in FALSE_START");

        wait_for_state(IDLE);
        check(dut.u_fsm.state === IDLE, "FALSE_START -> IDLE (clean reset)");
        check(led_false_start === 1'b0, "false-start LED cleared in IDLE");
        check(an === {NUM_DIGITS{1'b0}}, "display blanked after false start");
        if (scn_errors == errors) $display("SCENARIO 2: PASS"); else $display("SCENARIO 2: FAIL");

        // =================================================================
        $display("\n==== SCENARIO 3: BACK-TO-BACK TRIALS ====");
        scn_errors = errors;

        // Trial A
        $display("  -- trial A --");
        run_normal_trial(30, meas2);
        wait_for_state(IDLE);
        check(dut.u_fsm.state === IDLE, "trial A -> IDLE");
        // Re-arm checks: previous result cleared, display blank. The counter
        // clears via synchronous reset in IDLE, so allow a couple of cycles.
        repeat (3) @(posedge clk); #1;
        check(dut.ms_elapsed === {MS_WIDTH{1'b0}}, "counter cleared for re-arm");
        check(an === {NUM_DIGITS{1'b0}}, "display blanked between trials");

        // Trial B (different reaction time) should measure independently.
        $display("  -- trial B --");
        run_normal_trial(75, meas3);
        wait_for_state(IDLE);
        check(dut.u_fsm.state === IDLE, "trial B -> IDLE");

        check(meas3 > meas2, "trial B (longer wait) measured > trial A");
        $display("  trial A = %0d ms, trial B = %0d ms", meas2, meas3);
        if (scn_errors == errors) $display("SCENARIO 3: PASS"); else $display("SCENARIO 3: FAIL");

        // =================================================================
        $display("\n==============================");
        if (errors == 0) $display("ALL SCENARIOS PASSED.");
        else             $display("%0d ASSERTION(S) FAILED.", errors);

        $finish;
    end

endmodule
