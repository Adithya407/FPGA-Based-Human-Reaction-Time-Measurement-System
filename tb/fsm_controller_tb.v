// -----------------------------------------------------------------------------
// fsm_controller_tb.v -- testbench for rtl/fsm_controller.v
//
// Uses small timing parameters so states advance quickly. Exercises:
//   1. Normal path:  IDLE -> RANDOM_WAIT -> STIMULUS -> MEASURING -> RESULT -> IDLE
//   2. False start:  IDLE -> RANDOM_WAIT -> FALSE_START -> IDLE
//
// State transitions are checked with assertions against the DUT's internal
// state (hierarchical reference). Key output signals are checked per state.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module fsm_controller_tb;

    // Small timing so the sim is quick. rand_delay = 5 + lfsr_value*2.
    localparam integer MS_WIDTH         = 10;
    localparam integer MIN_WAIT_CLKS    = 5;
    localparam integer WAIT_SCALE       = 2;
    localparam integer RESULT_HOLD_CLKS = 8;
    localparam integer FALSE_HOLD_CLKS  = 6;

    // State encoding (must match the DUT).
    localparam [2:0] IDLE=3'd0, RANDOM_WAIT=3'd1, STIMULUS=3'd2,
                     MEASURING=3'd3, RESULT=3'd4, FALSE_START=3'd5;

    reg                clk, reset;
    reg                button, start_button;
    reg  [7:0]         lfsr_value;
    reg  [MS_WIDTH-1:0] ms_elapsed;

    wire led_stimulus, counter_start, counter_stop, counter_reset;
    wire lfsr_enable, false_start_flag, display_enable;

    integer errors;
    integer guard;

    fsm_controller #(
        .MS_WIDTH         (MS_WIDTH),
        .MIN_WAIT_CLKS    (MIN_WAIT_CLKS),
        .WAIT_SCALE       (WAIT_SCALE),
        .RESULT_HOLD_CLKS (RESULT_HOLD_CLKS),
        .FALSE_HOLD_CLKS  (FALSE_HOLD_CLKS)
    ) dut (
        .clk              (clk),
        .reset            (reset),
        .button           (button),
        .lfsr_value       (lfsr_value),
        .ms_elapsed       (ms_elapsed),
        .start_button     (start_button),
        .led_stimulus     (led_stimulus),
        .counter_start    (counter_start),
        .counter_stop     (counter_stop),
        .counter_reset    (counter_reset),
        .lfsr_enable      (lfsr_enable),
        .false_start_flag (false_start_flag),
        .display_enable   (display_enable)
    );

    // 125 MHz clock
    initial clk = 1'b0;
    always #4 clk = ~clk;

    // Human-readable state name.
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

    task expect_state(input [2:0] s);
        begin
            if (dut.state !== s) begin
                errors = errors + 1;
                $display("FAIL: state=%0s, expected %0s  @%0t",
                         sname(dut.state), sname(s), $time);
            end
            else begin
                $display("PASS: in %0s  @%0t", sname(s), $time);
            end
        end
    endtask

    // Wait (with a guard) until the DUT reaches state s.
    task wait_for_state(input [2:0] s);
        begin
            guard = 0;
            while (dut.state !== s && guard < 1000) begin
                @(posedge clk); #1;
                guard = guard + 1;
            end
            if (guard >= 1000) begin
                errors = errors + 1;
                $display("FAIL: timed out waiting for %0s (stuck in %0s) @%0t",
                         sname(s), sname(dut.state), $time);
            end
        end
    endtask

    // One-cycle rising-edge pulse on start_button.
    task pulse_start;
        begin
            @(negedge clk); start_button = 1'b1;
            @(negedge clk); start_button = 1'b0;
        end
    endtask

    // One-cycle rising-edge pulse on button.
    task pulse_button;
        begin
            @(negedge clk); button = 1'b1;
            @(negedge clk); button = 1'b0;
        end
    endtask

    initial begin
        errors       = 0;
        reset        = 1'b1;
        button       = 1'b0;
        start_button = 1'b0;
        lfsr_value   = 8'd3;      // rand_delay = 5 + 3*2 = 11 cycles
        ms_elapsed   = 10'd250;   // pretend the counter measured 250 ms

        // Reset
        @(negedge clk); @(negedge clk); reset = 1'b0; #1;
        expect_state(IDLE);
        if (counter_reset !== 1'b1) begin
            errors = errors + 1; $display("FAIL: counter_reset not asserted in IDLE");
        end

        // =================================================================
        //  NORMAL PATH
        // =================================================================
        $display("--- NORMAL PATH ---");

        pulse_start; #1;
        expect_state(RANDOM_WAIT);

        // Wait out the random delay -> STIMULUS (no early press).
        wait_for_state(STIMULUS);
        expect_state(STIMULUS);
        if (led_stimulus !== 1'b1 || counter_start !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: STIMULUS should assert led_stimulus & counter_start");
        end

        // STIMULUS -> MEASURING immediately.
        @(posedge clk); #1;
        expect_state(MEASURING);
        if (led_stimulus !== 1'b1) begin
            errors = errors + 1; $display("FAIL: led_stimulus should stay high in MEASURING");
        end

        // Respond: button press -> RESULT, counter_stop pulses on the press.
        // counter_stop is combinational and valid at the capturing posedge
        // (while still in MEASURING with button_rise), so check it before the
        // edge that advances the state.
        @(negedge clk); button = 1'b1; #1;
        if (counter_stop !== 1'b1) begin
            errors = errors + 1; $display("FAIL: counter_stop not pulsed on response press");
        end
        @(posedge clk);                    // counter samples stop; state -> RESULT
        @(negedge clk); button = 1'b0; #1;
        expect_state(RESULT);
        if (display_enable !== 1'b1) begin
            errors = errors + 1; $display("FAIL: display_enable not asserted in RESULT");
        end

        // RESULT -> IDLE after the hold time.
        wait_for_state(IDLE);
        expect_state(IDLE);

        // =================================================================
        //  FALSE-START PATH
        // =================================================================
        $display("--- FALSE-START PATH ---");

        pulse_start; #1;
        expect_state(RANDOM_WAIT);

        // Press the button early (well before the 11-cycle delay).
        @(posedge clk); @(posedge clk);   // a couple cycles into the wait
        pulse_button; #1;
        expect_state(FALSE_START);
        if (false_start_flag !== 1'b1) begin
            errors = errors + 1; $display("FAIL: false_start_flag not asserted");
        end

        // FALSE_START -> IDLE after the hold time.
        wait_for_state(IDLE);
        expect_state(IDLE);

        // =================================================================
        //  RESULT -> IDLE via start_button (not just timeout)
        // =================================================================
        $display("--- RESULT EXIT VIA START_BUTTON ---");
        pulse_start; #1; expect_state(RANDOM_WAIT);
        wait_for_state(STIMULUS);
        @(posedge clk); #1; expect_state(MEASURING);
        pulse_button; #1; expect_state(RESULT);
        // Press start during RESULT -> should return to IDLE promptly.
        pulse_start; #1;
        expect_state(IDLE);

        $display("------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED.");
        else
            $display("%0d TEST(S) FAILED.", errors);

        $finish;
    end

endmodule
