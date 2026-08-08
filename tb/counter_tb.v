// -----------------------------------------------------------------------------
// counter_tb.v -- testbench for rtl/counter.v
//
// Overrides CLKS_PER_MS with a small value (10) so 1 ms == 10 clock cycles,
// keeping the simulation fast. For each test case the sequence is:
//
//   reset -> pulse start -> run for N clock cycles -> pulse stop -> check
//
// With a start captured on edge S and N running edges afterwards, the counter
// ticks once every CLKS_PER_MS cycles, so the expected result is
//   expected_ms = N / CLKS_PER_MS   (integer division).
// The stopping edge has priority over the tick logic, so it never adds an
// extra millisecond.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module counter_tb;

    localparam integer CLKS_PER_MS = 10;   // 1 ms == 10 clocks (sim only)
    localparam integer MS_WIDTH    = 10;

    reg                     clk;
    reg                     rst;
    reg                     start;
    reg                     stop;
    wire [MS_WIDTH-1:0]     ms;
    wire                    done;
    wire                    running;

    integer                 errors;

    // Device under test
    counter #(
        .CLKS_PER_MS (CLKS_PER_MS),
        .MS_WIDTH    (MS_WIDTH)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .start   (start),
        .stop    (stop),
        .ms      (ms),
        .done    (done),
        .running (running)
    );

    // 125 MHz clock (8 ns period) -- period value is cosmetic for this test.
    initial clk = 1'b0;
    always #4 clk = ~clk;

    // Run one measurement of `ncycles` clocks and check the elapsed count.
    task run_and_check(input integer ncycles);
        integer expected;
        begin
            expected = ncycles / CLKS_PER_MS;

            // Synchronous reset.
            @(negedge clk); rst = 1'b1; start = 1'b0; stop = 1'b0;
            @(posedge clk);
            @(negedge clk); rst = 1'b0;

            // Pulse start for one clock (captured on the next posedge = edge S).
            @(negedge clk); start = 1'b1;
            @(posedge clk);
            @(negedge clk); start = 1'b0;

            // Let it run for exactly `ncycles` clocks.
            repeat (ncycles) @(posedge clk);

            // Pulse stop for one clock.
            @(negedge clk); stop = 1'b1;
            @(posedge clk);
            @(negedge clk); stop = 1'b0;
            #1;

            if (ms === expected[MS_WIDTH-1:0] && done === 1'b1 && running === 1'b0) begin
                $display("PASS: %0d clocks -> ms=%0d (expected %0d), done=%b, running=%b",
                         ncycles, ms, expected, done, running);
            end
            else begin
                errors = errors + 1;
                $display("FAIL: %0d clocks -> ms=%0d (expected %0d), done=%b, running=%b",
                         ncycles, ms, expected, done, running);
            end
        end
    endtask

    initial begin
        errors = 0;
        rst    = 1'b1;
        start  = 1'b0;
        stop   = 1'b0;

        // A spread of run lengths: exact multiples and non-multiples of a ms.
        run_and_check(50);    // -> 5 ms
        run_and_check(123);   // -> 12 ms
        run_and_check(10);    // -> 1 ms  (single tick boundary)
        run_and_check(9);     // -> 0 ms  (just under one tick)
        run_and_check(1000);  // -> 100 ms

        // Confirm the count holds after stop: run, stop, idle a while, recheck.
        @(negedge clk); rst = 1'b1;
        @(posedge clk);
        @(negedge clk); rst = 1'b0;
        @(negedge clk); start = 1'b1;
        @(posedge clk);
        @(negedge clk); start = 1'b0;
        repeat (30) @(posedge clk);        // 3 ms
        @(negedge clk); stop = 1'b1;
        @(posedge clk);
        @(negedge clk); stop = 1'b0;
        repeat (40) @(posedge clk);        // idle; count must not advance
        #1;
        if (ms === 10'd3 && running === 1'b0) begin
            $display("PASS: count held at %0d ms while stopped (running=%b).", ms, running);
        end
        else begin
            errors = errors + 1;
            $display("FAIL: count changed after stop: ms=%0d, running=%b.", ms, running);
        end

        $display("------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED.");
        else
            $display("%0d TEST(S) FAILED.", errors);

        $finish;
    end

endmodule
