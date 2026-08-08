// -----------------------------------------------------------------------------
// bcd_converter_tb.v -- testbench for rtl/bcd_converter.v
//
// Exhaustively checks every value 0..999 against the expected hundreds/tens/
// ones digits, plus a couple of >999 cases to confirm the clamp-to-999 guard.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module bcd_converter_tb;

    reg  [9:0] bin;
    wire [3:0] hundreds, tens, ones;

    integer v;
    integer errors;
    integer exp_h, exp_t, exp_o;

    bcd_converter #(.IN_WIDTH(10)) dut (
        .bin      (bin),
        .hundreds (hundreds),
        .tens     (tens),
        .ones     (ones)
    );

    task check(input integer value, input integer eh, input integer et, input integer eo);
        begin
            bin = value[9:0];
            #1;  // settle combinational logic
            if (hundreds !== eh[3:0] || tens !== et[3:0] || ones !== eo[3:0]) begin
                errors = errors + 1;
                $display("FAIL: bin=%0d -> %0d%0d%0d (expected %0d%0d%0d)",
                         value, hundreds, tens, ones, eh, et, eo);
            end
        end
    endtask

    initial begin
        errors = 0;

        // Exhaustive 0..999
        for (v = 0; v <= 999; v = v + 1) begin
            exp_h = (v / 100);
            exp_t = (v / 10) % 10;
            exp_o = (v % 10);
            check(v, exp_h, exp_t, exp_o);
        end
        $display("Checked all values 0..999.");

        // Clamp behavior for out-of-range inputs (max 10-bit is 1023).
        check(1000, 9, 9, 9);
        check(1023, 9, 9, 9);

        // A few explicit spot values for the log.
        check(0,   0, 0, 0);
        check(7,   0, 0, 7);
        check(42,  0, 4, 2);
        check(305, 3, 0, 5);
        check(999, 9, 9, 9);

        $display("------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED.");
        else
            $display("%0d TEST(S) FAILED.", errors);

        $finish;
    end

endmodule
