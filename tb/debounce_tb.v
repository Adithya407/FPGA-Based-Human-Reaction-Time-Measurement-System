// -----------------------------------------------------------------------------
// debounce_tb.v -- testbench for rtl/debounce.v
//
// Overrides STABLE_COUNT with a small value so the stability window is short
// enough for fast simulation. Checks:
//
//   1. A bouncy input (rapid high/low pulses, each shorter than the window)
//      never disturbs the output.
//   2. Once the input holds a new level, the output changes exactly
//      STABLE_COUNT + 2 clocks later (2 for the synchronizer).
//   3. The same holds for the falling edge.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module debounce_tb;

    localparam integer STABLE_COUNT = 20;              // short window (sim only)
    localparam integer EXPECT_LAT   = STABLE_COUNT + 2; // sync latency + window

    reg  clk;
    reg  rst;
    reg  btn_in;
    wire btn_out;

    integer errors;
    integer k;
    integer lat;

    // Device under test
    debounce #(.STABLE_COUNT(STABLE_COUNT)) dut (
        .clk     (clk),
        .rst     (rst),
        .btn_in  (btn_in),
        .btn_out (btn_out)
    );

    // 125 MHz clock (8 ns period)
    initial clk = 1'b0;
    always #4 clk = ~clk;

    // Drive btn_in to `lvl` for `cyc` clocks, asserting btn_out stays `exp`.
    task drive_and_expect(input lvl, input integer cyc, input exp);
        begin
            @(negedge clk); btn_in = lvl;
            for (k = 0; k < cyc; k = k + 1) begin
                @(posedge clk); #1;
                if (btn_out !== exp) begin
                    errors = errors + 1;
                    $display("FAIL: btn_out=%b (expected %b) while in=%b, %0t",
                             btn_out, exp, lvl, $time);
                end
            end
        end
    endtask

    // Set btn_in to `lvl`, then count clocks until btn_out reaches `target`.
    task measure_latency(input lvl, input target, output integer n);
        begin
            @(negedge clk); btn_in = lvl;
            n = 0;
            while (btn_out !== target) begin
                @(posedge clk); #1;
                n = n + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst    = 1'b1;
        btn_in = 1'b0;

        // Synchronous reset.
        @(negedge clk); @(negedge clk); rst = 1'b0;

        // ---- Phase 1: idle low -------------------------------------------
        drive_and_expect(1'b0, 5, 1'b0);

        // ---- Phase 2: bouncy rising edge ---------------------------------
        // Pulses (8 clocks each) are shorter than the 20-clock window, so the
        // output must stay low the whole time.
        drive_and_expect(1'b1, 8, 1'b0);
        drive_and_expect(1'b0, 8, 1'b0);
        drive_and_expect(1'b1, 8, 1'b0);
        drive_and_expect(1'b0, 8, 1'b0);
        drive_and_expect(1'b1, 8, 1'b0);
        // Settle low so the counter is fully reset before the clean edge.
        drive_and_expect(1'b0, 8, 1'b0);

        // ---- Phase 3: clean stable high ----------------------------------
        measure_latency(1'b1, 1'b1, lat);
        if (lat == EXPECT_LAT)
            $display("PASS: rising edge -> btn_out high after %0d clocks (expected %0d).",
                     lat, EXPECT_LAT);
        else begin
            errors = errors + 1;
            $display("FAIL: rising edge latency %0d clocks (expected %0d).",
                     lat, EXPECT_LAT);
        end

        // Hold high a while; output must stay high.
        drive_and_expect(1'b1, 10, 1'b1);

        // ---- Phase 4: bouncy falling edge --------------------------------
        drive_and_expect(1'b0, 8, 1'b1);
        drive_and_expect(1'b1, 8, 1'b1);
        drive_and_expect(1'b0, 8, 1'b1);
        drive_and_expect(1'b1, 8, 1'b1);
        drive_and_expect(1'b0, 8, 1'b1);
        // Settle high before the clean falling edge.
        drive_and_expect(1'b1, 8, 1'b1);

        // ---- Phase 5: clean stable low -----------------------------------
        measure_latency(1'b0, 1'b0, lat);
        if (lat == EXPECT_LAT)
            $display("PASS: falling edge -> btn_out low after %0d clocks (expected %0d).",
                     lat, EXPECT_LAT);
        else begin
            errors = errors + 1;
            $display("FAIL: falling edge latency %0d clocks (expected %0d).",
                     lat, EXPECT_LAT);
        end

        drive_and_expect(1'b0, 10, 1'b0);

        $display("------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED.");
        else
            $display("%0d TEST(S) FAILED.", errors);

        $finish;
    end

endmodule
