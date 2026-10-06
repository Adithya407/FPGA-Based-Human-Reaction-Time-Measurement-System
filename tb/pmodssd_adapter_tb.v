// -----------------------------------------------------------------------------
// pmodssd_adapter_tb.v -- exhaustive testbench for rtl/pmodssd_adapter.v
//
// Applies every segment pattern (0..127) with every legal digit select
// (none, ones, tens, hundreds) to two adapters, one per C_RIGHT setting, and
// checks for each:
//   * only the module that owns the active digit gets the segment pattern;
//     the other module (or both, when no digit is active) is dark
//   * SSD #1's C selects the right digit for ones and the left digit for tens
//   * SSD #2's C always selects the right digit (hundreds)
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module pmodssd_adapter_tb;

    reg  [6:0] seg;
    reg  [2:0] an;

    wire [6:0] lo_seg0, hi_seg0, lo_seg1, hi_seg1;
    wire       lo_c0,   hi_c0,   lo_c1,   hi_c1;

    // C_RIGHT = 0 (Digilent Pmod SSD) and C_RIGHT = 1 (swapped-digit fallback)
    pmodssd_adapter #(.C_RIGHT(1'b0)) dut0 (
        .seg(seg), .an(an),
        .ssd_lo_seg(lo_seg0), .ssd_lo_c(lo_c0), .ssd_hi_seg(hi_seg0), .ssd_hi_c(hi_c0)
    );
    pmodssd_adapter #(.C_RIGHT(1'b1)) dut1 (
        .seg(seg), .an(an),
        .ssd_lo_seg(lo_seg1), .ssd_lo_c(lo_c1), .ssd_hi_seg(hi_seg1), .ssd_hi_c(hi_c1)
    );

    integer errors;
    integer s, a;
    reg [2:0] an_vals [0:3];

    // Expected outputs for one adapter. c_right = level that selects the right
    // digit; "x" C values (module dark) are not checked.
    task check_one(input c_right,
                   input [6:0] lo_seg, input lo_c, input [6:0] hi_seg, input hi_c);
        reg [6:0] exp_lo, exp_hi;
        begin
            exp_lo = (an[0] | an[1]) ? seg : 7'b0;
            exp_hi = an[2]           ? seg : 7'b0;
            if (lo_seg !== exp_lo || hi_seg !== exp_hi) begin
                errors = errors + 1;
                $display("  FAIL: C_RIGHT=%b seg=%b an=%b -> lo=%b hi=%b (exp lo=%b hi=%b)",
                         c_right, seg, an, lo_seg, hi_seg, exp_lo, exp_hi);
            end
            if (an[0] && lo_c !== c_right) begin
                errors = errors + 1;
                $display("  FAIL: C_RIGHT=%b ones slot: ssd_lo_c=%b (exp right=%b)", c_right, lo_c, c_right);
            end
            if (an[1] && lo_c !== ~c_right) begin
                errors = errors + 1;
                $display("  FAIL: C_RIGHT=%b tens slot: ssd_lo_c=%b (exp left=%b)", c_right, lo_c, ~c_right);
            end
            if (hi_c !== c_right) begin
                errors = errors + 1;
                $display("  FAIL: C_RIGHT=%b ssd_hi_c=%b (exp right=%b)", c_right, hi_c, c_right);
            end
        end
    endtask

    initial begin
        errors = 0;
        an_vals[0] = 3'b000;   // blank
        an_vals[1] = 3'b001;   // ones
        an_vals[2] = 3'b010;   // tens
        an_vals[3] = 3'b100;   // hundreds

        for (a = 0; a < 4; a = a + 1) begin
            for (s = 0; s < 128; s = s + 1) begin
                an  = an_vals[a];
                seg = s[6:0];
                #1;
                check_one(1'b0, lo_seg0, lo_c0, hi_seg0, hi_c0);
                check_one(1'b1, lo_seg1, lo_c1, hi_seg1, hi_c1);
            end
        end

        if (errors == 0) $display("PMODSSD_ADAPTER: ALL CHECKS PASSED (512 vectors x 2 configs).");
        else             $display("PMODSSD_ADAPTER: %0d CHECK(S) FAILED.", errors);
        $finish;
    end

endmodule
