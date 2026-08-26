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
// -----------------------------------------------------------------------------

module bcd_converter #(
    parameter integer IN_WIDTH = 10   // enough for 0..999 (max 1023)
) (
    input  wire [IN_WIDTH-1:0] bin,
    output reg  [3:0]          hundreds,
    output reg  [3:0]          tens,
    output reg  [3:0]          ones
);

    integer i;
    // Scratch register: binary in the low IN_WIDTH bits, 3 BCD nibbles above.
    reg [IN_WIDTH+11:0] shift;

    // Clamp to 999 so the result always fits in three BCD digits.
    wire [IN_WIDTH-1:0] value = (bin > 10'd999) ? 10'd999 : bin;

    always @* begin
        shift               = {(IN_WIDTH+12){1'b0}};
        shift[IN_WIDTH-1:0] = value;

        for (i = 0; i < IN_WIDTH; i = i + 1) begin
            // Add 3 to any BCD nibble that is 5 or more, then shift left.
            if (shift[IN_WIDTH+0 +: 4] >= 4'd5)
                shift[IN_WIDTH+0 +: 4] = shift[IN_WIDTH+0 +: 4] + 4'd3;  // ones
            if (shift[IN_WIDTH+4 +: 4] >= 4'd5)
                shift[IN_WIDTH+4 +: 4] = shift[IN_WIDTH+4 +: 4] + 4'd3;  // tens
            if (shift[IN_WIDTH+8 +: 4] >= 4'd5)
                shift[IN_WIDTH+8 +: 4] = shift[IN_WIDTH+8 +: 4] + 4'd3;  // hundreds

            shift = shift << 1;
        end

        ones     = shift[IN_WIDTH+0 +: 4];
        tens     = shift[IN_WIDTH+4 +: 4];
        hundreds = shift[IN_WIDTH+8 +: 4];
    end

endmodule
