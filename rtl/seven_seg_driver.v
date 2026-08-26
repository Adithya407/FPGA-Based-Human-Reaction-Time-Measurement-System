// -----------------------------------------------------------------------------
// seven_seg_driver.v -- multiplexed seven-segment display driver
//
// Time-multiplexes 3 BCD digits (hundreds, tens, ones) onto a shared set of
// segment lines, cycling the digit-select (anode) signals fast enough that the
// display looks continuous to the eye.
//
// Refresh timing (defaults, 125 MHz clock):
//   REFRESH_CLKS = 41667 clocks per digit slot -> slot ~= 333 us
//   full scan    = NUM_DIGITS * REFRESH_CLKS   ~= 1 ms  -> each digit is
//   refreshed ~1000 times/second (>> the ~60 Hz flicker-fusion threshold).
//
// Segment bus ordering: seg[6]=a, seg[5]=b, seg[4]=c, seg[3]=d,
//                       seg[2]=e, seg[1]=f, seg[0]=g. A '1' lights a segment.
//
// Active levels are parameterized. Defaults are active-high segments and
// active-high digit-select (an[k]=1 selects digit k). For a common-anode
// module set SEG_ACTIVE_LOW=1; for active-low digit-select set AN_ACTIVE_LOW=1.
// Digit index: an[0]=ones, an[1]=tens, an[2]=hundreds.
//
// STRUCTURAL implementation: the refresh prescaler and digit index are
// `registerN` counters with wrap logic built from eqN/adderN/mux2N; the active
// digit is selected with a one-hot decoder driving both the anodes and an
// AND/OR input mux; the BCD->7-seg map is the gate-level `seg7_decoder`; and
// the output polarity is chosen by a generate-if of buf/not gates. Assumes
// NUM_DIGITS >= 3 (three digit data inputs). See primitives.v.
// -----------------------------------------------------------------------------

module seven_seg_driver #(
    parameter integer NUM_DIGITS     = 3,
    parameter integer REFRESH_CLKS   = 41667,  // clocks per digit slot
    parameter         SEG_ACTIVE_LOW = 1'b0,   // 1 => common-anode (segments active-low)
    parameter         AN_ACTIVE_LOW  = 1'b0    // 1 => digit-select active-low
) (
    input  wire                  clk,
    input  wire                  rst,        // synchronous, active-high
    input  wire [3:0]            hundreds,
    input  wire [3:0]            tens,
    input  wire [3:0]            ones,
    output wire [NUM_DIGITS-1:0] an,         // digit-select (one active at a time)
    output wire [6:0]            seg         // segment pattern a..g
);

    localparam integer      RW    = (REFRESH_CLKS <= 1) ? 1 : $clog2(REFRESH_CLKS);
    localparam integer      DW    = (NUM_DIGITS   <= 1) ? 1 : $clog2(NUM_DIGITS);
    localparam [RW-1:0]     R_MAX = REFRESH_CLKS[RW-1:0] - 1'b1;   // slot terminal count
    localparam [DW-1:0]     D_MAX = NUM_DIGITS[DW-1:0]   - 1'b1;   // last digit index

    // ------------------------------------------------------------------------
    // Refresh prescaler: counts every clock, wraps at R_MAX. `slot_done`
    // (one clock per digit slot) advances the digit index.
    // ------------------------------------------------------------------------
    wire [RW-1:0] refresh_cnt, refr_plus1, refr_next;
    wire          slot_done, refr_co;
    eqN #(.WIDTH(RW)) u_rmax (.a(refresh_cnt), .b(R_MAX), .eq(slot_done));
    adderN #(.WIDTH(RW)) u_rinc (
        .a(refresh_cnt), .b({RW{1'b0}}), .cin(1'b1), .sum(refr_plus1), .cout(refr_co)
    );
    mux2N #(.WIDTH(RW)) u_rmux (
        .a(refr_plus1), .b({RW{1'b0}}), .sel(slot_done), .y(refr_next)
    );
    registerN #(.WIDTH(RW), .RESET_VAL({RW{1'b0}})) u_refresh (
        .clk(clk), .rst(rst), .en(1'b1), .d(refr_next), .q(refresh_cnt)
    );

    // ------------------------------------------------------------------------
    // Digit index: advances once per slot, wraps at D_MAX (= NUM_DIGITS-1).
    // ------------------------------------------------------------------------
    wire [DW-1:0] digit_idx, dig_plus1, dig_wrap, dig_next;
    wire          at_last, dig_co;
    eqN #(.WIDTH(DW)) u_dmax (.a(digit_idx), .b(D_MAX), .eq(at_last));
    adderN #(.WIDTH(DW)) u_dinc (
        .a(digit_idx), .b({DW{1'b0}}), .cin(1'b1), .sum(dig_plus1), .cout(dig_co)
    );
    mux2N #(.WIDTH(DW)) u_dmux (
        .a(dig_plus1), .b({DW{1'b0}}), .sel(at_last), .y(dig_wrap)
    );
    // digit register only updates on a slot boundary (enable = slot_done).
    registerN #(.WIDTH(DW), .RESET_VAL({DW{1'b0}})) u_digit (
        .clk(clk), .rst(rst), .en(slot_done), .d(dig_wrap), .q(digit_idx)
    );

    // ------------------------------------------------------------------------
    // One-hot digit select (drives both the anodes and the input mux below).
    // ------------------------------------------------------------------------
    wire [NUM_DIGITS-1:0] an_onehot;
    onehot_decoder #(.SEL_WIDTH(DW), .OUT_WIDTH(NUM_DIGITS)) u_dec (
        .sel (digit_idx), .onehot (an_onehot)
    );

    // ------------------------------------------------------------------------
    // Select the BCD digit for the active slot: an_onehot[0]->ones,
    // [1]->tens, [2]->hundreds. AND-mask each input by its select, then OR.
    // Slots >= 3 (if NUM_DIGITS > 3) get 0 -> a blank digit.
    // ------------------------------------------------------------------------
    wire [3:0] cur_bcd;
    genvar b;
    generate
        for (b = 0; b < 4; b = b + 1) begin : bcdmux
            wire mo, mt, mh;
            and (mo, ones[b],     an_onehot[0]);
            and (mt, tens[b],     an_onehot[1]);
            and (mh, hundreds[b], an_onehot[2]);
            or  (cur_bcd[b], mo, mt, mh);
        end
    endgenerate

    // ------------------------------------------------------------------------
    // BCD -> 7-segment (active-high, 1 = lit).
    // ------------------------------------------------------------------------
    wire [6:0] seg_raw;
    seg7_decoder u_seg (.d(cur_bcd), .seg(seg_raw));

    // ------------------------------------------------------------------------
    // Output polarity: invert per the parameters (compile-time choice).
    // ------------------------------------------------------------------------
    genvar k;
    generate
        for (k = 0; k < NUM_DIGITS; k = k + 1) begin : an_pol
            if (AN_ACTIVE_LOW) not (an[k], an_onehot[k]);
            else               buf (an[k], an_onehot[k]);
        end
        for (k = 0; k < 7; k = k + 1) begin : seg_pol
            if (SEG_ACTIVE_LOW) not (seg[k], seg_raw[k]);
            else                buf (seg[k], seg_raw[k]);
        end
    endgenerate

endmodule


// -----------------------------------------------------------------------------
// seg7_decoder -- gate-level BCD (0..9) to 7-segment decoder.
//
// seg[6]=a .. seg[0]=g, active-high (1 = lit). Digits A..F (10..15) blank.
// Implemented as a sum-of-minterms: minterms m0..m9 are 4-input ANDs of the
// input literals, and each segment is the OR of the minterms for the digits
// where it is lit. For inputs 10..15 every minterm is 0 -> all segments off.
// -----------------------------------------------------------------------------
module seg7_decoder (
    input  wire [3:0] d,
    output wire [6:0] seg
);
    wire n3, n2, n1, n0;
    not (n3, d[3]);
    not (n2, d[2]);
    not (n1, d[1]);
    not (n0, d[0]);

    wire m0, m1, m2, m3, m4, m5, m6, m7, m8, m9;
    and (m0, n3, n2, n1, n0);   // 0000
    and (m1, n3, n2, n1, d[0]); // 0001
    and (m2, n3, n2, d[1], n0); // 0010
    and (m3, n3, n2, d[1], d[0]); // 0011
    and (m4, n3, d[2], n1, n0); // 0100
    and (m5, n3, d[2], n1, d[0]); // 0101
    and (m6, n3, d[2], d[1], n0); // 0110
    and (m7, n3, d[2], d[1], d[0]); // 0111
    and (m8, d[3], n2, n1, n0); // 1000
    and (m9, d[3], n2, n1, d[0]); // 1001

    // Segment ON minterm sets (digits that light each segment):
    or (seg[6], m0, m2, m3, m5, m6, m7, m8, m9);        // a : 0,2,3,5,6,7,8,9
    or (seg[5], m0, m1, m2, m3, m4, m7, m8, m9);        // b : 0,1,2,3,4,7,8,9
    or (seg[4], m0, m1, m3, m4, m5, m6, m7, m8, m9);    // c : all except 2
    or (seg[3], m0, m2, m3, m5, m6, m8, m9);            // d : 0,2,3,5,6,8,9
    or (seg[2], m0, m2, m6, m8);                        // e : 0,2,6,8
    or (seg[1], m0, m4, m5, m6, m8, m9);                // f : 0,4,5,6,8,9
    or (seg[0], m2, m3, m4, m5, m6, m8, m9);            // g : 2,3,4,5,6,8,9
endmodule
