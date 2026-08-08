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
    output reg  [NUM_DIGITS-1:0] an,         // digit-select (one active at a time)
    output reg  [6:0]            seg         // segment pattern a..g
);

    localparam integer RW = (REFRESH_CLKS <= 1) ? 1 : $clog2(REFRESH_CLKS);
    localparam integer DW = (NUM_DIGITS   <= 1) ? 1 : $clog2(NUM_DIGITS);

    // --- Refresh / digit-scan timing ----------------------------------------
    reg [RW-1:0] refresh_cnt;
    reg [DW-1:0] digit_idx;

    always @(posedge clk) begin
        if (rst) begin
            refresh_cnt <= {RW{1'b0}};
            digit_idx   <= {DW{1'b0}};
        end
        else if (refresh_cnt == REFRESH_CLKS[RW-1:0] - 1'b1) begin
            refresh_cnt <= {RW{1'b0}};
            if (digit_idx == NUM_DIGITS[DW-1:0] - 1'b1)
                digit_idx <= {DW{1'b0}};
            else
                digit_idx <= digit_idx + 1'b1;
        end
        else begin
            refresh_cnt <= refresh_cnt + 1'b1;
        end
    end

    // --- Select the BCD digit for the active slot ---------------------------
    reg [3:0] cur_bcd;
    always @* begin
        case (digit_idx)
            2'd0:    cur_bcd = ones;
            2'd1:    cur_bcd = tens;
            2'd2:    cur_bcd = hundreds;
            default: cur_bcd = 4'd0;
        endcase
    end

    // --- BCD -> 7-segment (active-high, 1 = lit) ----------------------------
    function [6:0] seg_decode(input [3:0] d);
        begin
            case (d)                     //             abcdefg
                4'd0: seg_decode = 7'b1111110;
                4'd1: seg_decode = 7'b0110000;
                4'd2: seg_decode = 7'b1101101;
                4'd3: seg_decode = 7'b1111001;
                4'd4: seg_decode = 7'b0110011;
                4'd5: seg_decode = 7'b1011011;
                4'd6: seg_decode = 7'b1011111;
                4'd7: seg_decode = 7'b1110000;
                4'd8: seg_decode = 7'b1111111;
                4'd9: seg_decode = 7'b1111011;
                default: seg_decode = 7'b0000000; // blank for A-F
            endcase
        end
    endfunction

    // --- Drive outputs (one-hot digit-select + decoded segments) ------------
    reg [NUM_DIGITS-1:0] an_onehot;
    always @* begin
        an_onehot            = {NUM_DIGITS{1'b0}};
        an_onehot[digit_idx] = 1'b1;
    end

    always @* begin
        an  = AN_ACTIVE_LOW  ? ~an_onehot          : an_onehot;
        seg = SEG_ACTIVE_LOW ? ~seg_decode(cur_bcd) : seg_decode(cur_bcd);
    end

endmodule
