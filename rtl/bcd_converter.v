// -----------------------------------------------------------------------------
// bcd_converter.v -- binary to 3-digit BCD via the double-dabble algorithm
//
// Converts a binary value (0..999) into three 4-bit BCD digits:
// hundreds, tens, ones. Combinational (shift-and-add-3 unrolled over the
// input width).
//
// Values above 999 would overflow three BCD digits, so the input is clamped
// to 999 first -- the elapsed-ms counter can saturate above 999, and this
// keeps the display from showing garbage in that case.
//
// STRUCTURAL implementation: the unrolled double-dabble is realised as a chain
// of IN_WIDTH stages. Each stage applies the "add 3 if >= 5" correction to the
// three BCD nibbles (module `dabble_cell`) and then shifts the whole vector
// left by one bit (pure wiring). The clamp is a gtN comparator + mux2N. See
// primitives.v for the building blocks.
// -----------------------------------------------------------------------------

module bcd_converter #(
    parameter integer IN_WIDTH = 10   // enough for 0..999 (max 1023)
) (
    input  wire [IN_WIDTH-1:0] bin,
    output wire [3:0]          hundreds,
    output wire [3:0]          tens,
    output wire [3:0]          ones
);

    localparam integer          SW     = IN_WIDTH + 12;  // scratch width (bin + 3 BCD nibbles)
    localparam [IN_WIDTH-1:0]   MAX999 = 999;            // clamp constant

    // --- Clamp to 999 so the result always fits in three BCD digits ---------
    wire                gt999;
    wire [IN_WIDTH-1:0] value;
    gtN   #(.WIDTH(IN_WIDTH)) u_clampcmp (.a(bin),  .b(MAX999), .gt(gt999));
    mux2N #(.WIDTH(IN_WIDTH)) u_clampmux (.a(bin),  .b(MAX999), .sel(gt999), .y(value));

    // --- Double-dabble stage chain ------------------------------------------
    // stage[0]   : binary in the low IN_WIDTH bits, BCD nibbles (12 bits) zero.
    // stage[i+1] : correct-then-shift-left of stage[i].
    // Nibble positions within a stage word:
    //   ones     = [IN_WIDTH   +: 4]
    //   tens     = [IN_WIDTH+4 +: 4]
    //   hundreds = [IN_WIDTH+8 +: 4]
    wire [SW-1:0] stage [0:IN_WIDTH];

    assign stage[0] = {12'b0, value};   // pure wiring (concatenation)

    genvar i;
    generate
        for (i = 0; i < IN_WIDTH; i = i + 1) begin : ddstage
            // Copy the array word into a plain vector so the part-selects below
            // operate on a normal net (portable across tools).
            wire [SW-1:0] cur;
            wire [SW-1:0] corr;
            assign cur = stage[i];

            // Low IN_WIDTH bits (the not-yet-shifted binary) pass through.
            assign corr[IN_WIDTH-1:0] = cur[IN_WIDTH-1:0];

            // "Add 3 if >= 5" correction on each of the three BCD nibbles.
            dabble_cell c_ones (.in(cur[IN_WIDTH   +: 4]), .out(corr[IN_WIDTH   +: 4]));
            dabble_cell c_tens (.in(cur[IN_WIDTH+4 +: 4]), .out(corr[IN_WIDTH+4 +: 4]));
            dabble_cell c_huns (.in(cur[IN_WIDTH+8 +: 4]), .out(corr[IN_WIDTH+8 +: 4]));

            // Shift the corrected vector left by one bit (0 into the LSB).
            assign stage[i+1] = {corr[SW-2:0], 1'b0};   // pure wiring
        end
    endgenerate

    // --- Extract the final BCD digits ---------------------------------------
    wire [SW-1:0] result;
    assign result   = stage[IN_WIDTH];
    assign ones     = result[IN_WIDTH   +: 4];
    assign tens     = result[IN_WIDTH+4 +: 4];
    assign hundreds = result[IN_WIDTH+8 +: 4];

endmodule


// -----------------------------------------------------------------------------
// dabble_cell -- one double-dabble BCD correction cell.
//   out = in + 3  when in >= 5   (else out = in)
//
// "in >= 5" for a 4-bit nibble = in[3] | (in[2] & (in[1] | in[0])).
// The +3 is added with a 4-bit adder whose addend is {0,0,ge5,ge5}
// (3 when ge5 is high, 0 otherwise). The carry-out is discarded: nibbles
// never exceed 9 here, so in+3 (max 12) always fits in 4 bits.
// -----------------------------------------------------------------------------
module dabble_cell (
    input  wire [3:0] in,
    output wire [3:0] out
);
    wire lo, mid, ge5, co;
    or  (lo,  in[1], in[0]);
    and (mid, in[2], lo);
    or  (ge5, in[3], mid);

    adderN #(.WIDTH(4)) u_add3 (
        .a    (in),
        .b    ({2'b00, ge5, ge5}),   // 4'b0011 when ge5, else 4'b0000
        .cin  (1'b0),
        .sum  (out),
        .cout (co)
    );
endmodule
