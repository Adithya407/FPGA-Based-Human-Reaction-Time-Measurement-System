// -----------------------------------------------------------------------------
// pmodssd_adapter.v -- maps the 3-digit multiplexed display bus onto two
//                      Digilent Pmod SSD modules
//
// A Pmod SSD is a 2-digit common-cathode display with its OWN segment pins
// (AA..AG, active-high) and a single digit-select pin C. Exactly one of its two
// digits is always selected, so the only way to make a module dark is to drive
// all of its segments low. Two modules are needed for three digits:
//
//   physical layout:   [ SSD_HI ][ SSD_HI ] [ SSD_LO ][ SSD_LO ]
//                        unused   hundreds    tens      ones
//
// seven_seg_driver already scans one digit per slot (one-hot `an`), with `seg`
// carrying that digit's pattern. This adapter steers `seg` to the module that
// owns the active digit and blanks the other one:
//
//   an[0] (ones)     -> SSD_LO segments = seg, C selects the right digit
//   an[1] (tens)     -> SSD_LO segments = seg, C selects the left digit
//   an[2] (hundreds) -> SSD_HI segments = seg, C fixed on the right digit
//   none active      -> both modules dark (display blanking)
//
// Each digit is still lit 1/3 of the time, so all three match in brightness.
//
// Inputs must be ACTIVE-HIGH (seven_seg_driver SEG_ACTIVE_LOW = AN_ACTIVE_LOW
// = 0), which is also the Pmod SSD's native polarity.
//
// C_RIGHT is the C level that lights a module's RIGHT digit (0 for the Pmod
// SSD). If tens and ones appear swapped on the hardware, set it to 1.
//
// STRUCTURAL implementation: gate primitives only; `assign` is used solely for
// the constant tie-off of hi_c (see primitives.v style convention).
// -----------------------------------------------------------------------------

module pmodssd_adapter #(
    parameter C_RIGHT = 1'b0          // C level that selects the right digit
) (
    input  wire [6:0] seg,            // shared segment bus a..g (seg[6]=a)
    input  wire [2:0] an,             // one-hot: [0]=ones [1]=tens [2]=hundreds

    output wire [6:0] ssd_lo_seg,     // Pmod SSD #1 AA..AG (seg[6]=AA ... seg[0]=AG)
    output wire       ssd_lo_c,       // Pmod SSD #1 C: ones = right, tens = left
    output wire [6:0] ssd_hi_seg,     // Pmod SSD #2 AA..AG
    output wire       ssd_hi_c        // Pmod SSD #2 C: fixed on the right digit
);

    // SSD_LO owns the ones and tens slots; SSD_HI owns the hundreds slot.
    wire lo_active;
    or (lo_active, an[0], an[1]);

    genvar k;
    generate
        for (k = 0; k < 7; k = k + 1) begin : seg_steer
            and (ssd_lo_seg[k], seg[k], lo_active);
            and (ssd_hi_seg[k], seg[k], an[2]);
        end

        // C must equal C_RIGHT in the ones slot and differ from it in the
        // tens slot. Outside those slots the module is dark, so C is a don't-care.
        if (C_RIGHT) buf (ssd_lo_c, an[0]);   // ones -> 1 (right), tens -> 0 (left)
        else         buf (ssd_lo_c, an[1]);   // ones -> 0 (right), tens -> 1 (left)
    endgenerate

    assign ssd_hi_c = C_RIGHT;   // constant tie-off: hundreds on the right digit

endmodule
