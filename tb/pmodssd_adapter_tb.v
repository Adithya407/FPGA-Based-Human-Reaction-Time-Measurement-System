// -----------------------------------------------------------------------------
// pmodssd_adapter_tb.v -- exhaustive testbench for rtl/pmodssd_adapter.v
//
// Applies every segment pattern (0..127) with every legal digit select
// (none, ones, tens, hundreds) to two adapters, one per C_RIGHT setting, and
// checks for each:
//   * only the module that owns the active digit gets the segment pattern;
//     the other module (or both, when no digit is active) is dark
//   * SSD #1's C selects the left digit for hundreds and the right for tens
//   * SSD #2's C always selects the left digit (ones)
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module pmodssd_adapter_tb;

    reg  [6:0] seg;
    reg  [2:0] an;

    wire [6:0] ht_seg0, ones_seg0, ht_seg1, ones_seg1;
    wire       ht_c0,   ones_c0,   ht_c1,   ones_c1;

    // C_RIGHT = 0 (Digilent Pmod SSD) and C_RIGHT = 1 (swapped-digit fallback)
    pmodssd_adapter #(.C_RIGHT(1'b0)) dut0 (
        .seg(seg), .an(an),
        .ssd_ht_seg(ht_seg0), .ssd_ht_c(ht_c0), .ssd_ones_seg(ones_seg0), .ssd_ones_c(ones_c0)
    );
    pmodssd_adapter #(.C_RIGHT(1'b1)) dut1 (
        .seg(seg), .an(an),
        .ssd_ht_seg(ht_seg1), .ssd_ht_c(ht_c1), .ssd_ones_seg(ones_seg1), .ssd_ones_c(ones_c1)
    );

    integer errors;
    integer s, a;
    reg [2:0] an_vals [0:3];

    // Expected outputs for one adapter. c_right = level that selects the right
    // digit; C values of a dark module are not checked.
    task check_one(input c_right,
                   input [6:0] ht_seg, input ht_c, input [6:0] ones_seg, input ones_c);
        reg [6:0] exp_ht, exp_ones;
        begin
            exp_ht   = (an[1] | an[2]) ? seg : 7'b0;
            exp_ones = an[0]           ? seg : 7'b0;
            if (ht_seg !== exp_ht || ones_seg !== exp_ones) begin
                errors = errors + 1;
                $display("  FAIL: C_RIGHT=%b seg=%b an=%b -> ht=%b ones=%b (exp ht=%b ones=%b)",
                         c_right, seg, an, ht_seg, ones_seg, exp_ht, exp_ones);
            end
            if (an[2] && ht_c !== ~c_right) begin
                errors = errors + 1;
                $display("  FAIL: C_RIGHT=%b hundreds slot: ssd_ht_c=%b (exp left=%b)", c_right, ht_c, ~c_right);
            end
            if (an[1] && ht_c !== c_right) begin
                errors = errors + 1;
                $display("  FAIL: C_RIGHT=%b tens slot: ssd_ht_c=%b (exp right=%b)", c_right, ht_c, c_right);
            end
            if (ones_c !== ~c_right) begin
                errors = errors + 1;
                $display("  FAIL: C_RIGHT=%b ssd_ones_c=%b (exp left=%b)", c_right, ones_c, ~c_right);
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
                check_one(1'b0, ht_seg0, ht_c0, ones_seg0, ones_c0);
                check_one(1'b1, ht_seg1, ht_c1, ones_seg1, ones_c1);
            end
        end

        if (errors == 0) $display("PMODSSD_ADAPTER: ALL CHECKS PASSED (512 vectors x 2 configs).");
        else             $display("PMODSSD_ADAPTER: %0d CHECK(S) FAILED.", errors);
        $finish;
    end

endmodule
