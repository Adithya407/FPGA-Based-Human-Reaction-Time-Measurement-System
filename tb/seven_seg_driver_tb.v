// -----------------------------------------------------------------------------
// seven_seg_driver_tb.v -- testbench for rtl/seven_seg_driver.v
//
// Uses a tiny REFRESH_CLKS so the digit scan cycles quickly. Checks:
//
//   1. Segment encoding for digits 0..9: with all three digits set to the same
//      value, the segment bus must show that digit's pattern.
//   2. Multiplexing: with three distinct digits, whenever a given anode is
//      active the segment bus must match that position's digit, and exactly one
//      anode is active at a time (one-hot).
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module seven_seg_driver_tb;

    localparam integer NUM_DIGITS   = 3;
    localparam integer REFRESH_CLKS = 4;   // short slot for fast sim

    reg                   clk;
    reg                   rst;
    reg  [3:0]            hundreds, tens, ones;
    wire [NUM_DIGITS-1:0] an;
    wire [6:0]            seg;

    integer errors;
    integer d;
    integer i;
    integer active_bit;

    seven_seg_driver #(
        .NUM_DIGITS   (NUM_DIGITS),
        .REFRESH_CLKS (REFRESH_CLKS)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .hundreds (hundreds),
        .tens     (tens),
        .ones     (ones),
        .an       (an),
        .seg      (seg)
    );

    // 125 MHz clock (8 ns period)
    initial clk = 1'b0;
    always #4 clk = ~clk;

    // Reference encoder (mirrors the RTL, active-high a..g).
    function [6:0] exp_seg(input [3:0] v);
        begin
            case (v)
                4'd0: exp_seg = 7'b1111110;
                4'd1: exp_seg = 7'b0110000;
                4'd2: exp_seg = 7'b1101101;
                4'd3: exp_seg = 7'b1111001;
                4'd4: exp_seg = 7'b0110011;
                4'd5: exp_seg = 7'b1011011;
                4'd6: exp_seg = 7'b1011111;
                4'd7: exp_seg = 7'b1110000;
                4'd8: exp_seg = 7'b1111111;
                4'd9: exp_seg = 7'b1111011;
                default: exp_seg = 7'b0000000;
            endcase
        end
    endfunction

    // Count of set bits in the anode bus (must be exactly 1).
    function integer ones_count(input [NUM_DIGITS-1:0] v);
        integer j;
        begin
            ones_count = 0;
            for (j = 0; j < NUM_DIGITS; j = j + 1)
                ones_count = ones_count + v[j];
        end
    endfunction

    initial begin
        errors   = 0;
        rst      = 1'b1;
        hundreds = 4'd0; tens = 4'd0; ones = 4'd0;
        @(negedge clk); @(negedge clk); rst = 1'b0;

        // ---- Test 1: segment encoding for 0..9 ---------------------------
        for (d = 0; d <= 9; d = d + 1) begin
            hundreds = d[3:0]; tens = d[3:0]; ones = d[3:0];
            @(posedge clk); #1;   // let the scan advance / outputs settle
            if (seg !== exp_seg(d[3:0])) begin
                errors = errors + 1;
                $display("FAIL: digit %0d -> seg=%b (expected %b)", d, seg, exp_seg(d[3:0]));
            end
            else begin
                $display("PASS: digit %0d -> seg=%b", d, seg);
            end
        end

        // ---- Test 2: multiplexing with distinct digits -------------------
        // ones=4, tens=5, hundreds=6.  an[0]=ones, an[1]=tens, an[2]=hundreds.
        hundreds = 4'd6; tens = 4'd5; ones = 4'd4;
        rst = 1'b1; @(negedge clk); rst = 1'b0;   // restart scan cleanly

        // Watch across two full scans (2 * NUM_DIGITS * REFRESH_CLKS clocks).
        for (i = 0; i < 2*NUM_DIGITS*REFRESH_CLKS + 4; i = i + 1) begin
            @(posedge clk); #1;

            // Exactly one anode active.
            if (ones_count(an) !== 1) begin
                errors = errors + 1;
                $display("FAIL: an=%b is not one-hot", an);
            end

            // Segment bus must match the active position's digit.
            active_bit = -1;
            if (an[0]) active_bit = 0;
            else if (an[1]) active_bit = 1;
            else if (an[2]) active_bit = 2;

            case (active_bit)
                0: if (seg !== exp_seg(4'd4)) begin
                       errors = errors + 1;
                       $display("FAIL: ones slot seg=%b (expected %b)", seg, exp_seg(4'd4));
                   end
                1: if (seg !== exp_seg(4'd5)) begin
                       errors = errors + 1;
                       $display("FAIL: tens slot seg=%b (expected %b)", seg, exp_seg(4'd5));
                   end
                2: if (seg !== exp_seg(4'd6)) begin
                       errors = errors + 1;
                       $display("FAIL: hundreds slot seg=%b (expected %b)", seg, exp_seg(4'd6));
                   end
            endcase
        end
        $display("Multiplex scan checked (one-hot anodes + per-slot segments).");

        $display("------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED.");
        else
            $display("%0d TEST(S) FAILED.", errors);

        $finish;
    end

endmodule
