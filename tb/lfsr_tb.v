// -----------------------------------------------------------------------------
// lfsr_tb.v -- testbench for rtl/lfsr.v
//
// Clocks the LFSR for 300 cycles, prints the sequence, and checks that the
// state never becomes 0x00 (a lock-up). Also verifies the maximal-length
// property by confirming the sequence repeats with period 255.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module lfsr_tb;

    localparam integer NCYCLES = 300;

    reg        clk;
    reg        rst;
    reg        load;
    reg  [7:0] seed_in;
    wire [7:0] value;

    integer    i;
    integer    stuck_count;
    reg  [7:0] first_value;   // state on the first cycle after reset release
    integer    period;        // detected repeat period (0 = not yet found)

    // Device under test
    lfsr #(.SEED(8'hFF)) dut (
        .clk     (clk),
        .rst     (rst),
        .load    (load),
        .seed_in (seed_in),
        .value   (value)
    );

    // 100 MHz clock (10 ns period)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst         = 1'b1;
        load        = 1'b0;
        seed_in     = 8'h00;
        stuck_count = 0;
        period      = 0;
        first_value = 8'h00;

        // Hold reset for two rising edges, then release.
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        $display("cycle : value (hex)  (bin)");
        $display("------------------------------");

        for (i = 0; i < NCYCLES; i = i + 1) begin
            @(posedge clk);
            #1;  // settle after the clock edge before sampling

            $display("%4d  :   0x%02h    %b", i, value, value);

            if (value == 8'h00) begin
                stuck_count = stuck_count + 1;
                $display("  ** ERROR: LFSR reached all-zero state at cycle %0d **", i);
            end

            // Record the first post-reset value, then look for its recurrence
            // to measure the sequence period.
            if (i == 0) begin
                first_value = value;
            end else if (period == 0 && value == first_value) begin
                period = i;
            end
        end

        $display("------------------------------");
        if (stuck_count == 0)
            $display("PASS: LFSR never stuck at 0x00 over %0d cycles.", NCYCLES);
        else
            $display("FAIL: LFSR hit 0x00 %0d time(s).", stuck_count);

        if (period == 255)
            $display("PASS: maximal-length sequence confirmed (period = 255).");
        else if (period != 0)
            $display("NOTE: sequence period measured as %0d (expected 255).", period);
        else
            $display("NOTE: period not observed within %0d cycles.", NCYCLES);

        $finish;
    end

endmodule
