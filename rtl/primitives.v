// -----------------------------------------------------------------------------
// primitives.v -- reusable structural building blocks
//
// This file provides the component library used to build the rest of the RTL
// in a *structural* style: every higher-level module is assembled by wiring
// these blocks together (plus Verilog gate primitives) instead of describing
// behaviour with procedural always-blocks or arithmetic/logic operators.
//
// Style convention used throughout the RTL:
//   * All *logic* is realised with gate primitives (and/or/xor/not/buf/xnor)
//     or by instantiating the blocks below.
//   * Continuous `assign` is used ONLY for pure net wiring -- aliasing,
//     bit-concatenation and constant tie-offs -- never for logic operators.
//   * The single behavioural leaf is the D flip-flop (`dffr`); a register is
//     the natural atomic storage element and is modelled behaviourally, which
//     is standard practice for structural design.
//
// Blocks:
//   dffr           1-bit D flip-flop, synchronous reset + clock enable
//   registerN      N-bit register (array of dffr)
//   mux2 / mux2N   1-bit / N-bit 2:1 multiplexer (gate-built)
//   full_adder     1-bit full adder (gate-built)
//   adderN         N-bit ripple-carry adder
//   eqN            N-bit equality comparator (a == b)
//   geN            N-bit unsigned >= comparator (a >= b)
//   gtN            N-bit unsigned >  comparator (a >  b)
//   onehot_decoder binary -> one-hot decoder
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// dffr -- D flip-flop with synchronous, active-high reset and clock enable.
//         Reset value is a parameter so registers can reset to non-zero.
//         (Behavioural leaf primitive -- the atomic storage element.)
// -----------------------------------------------------------------------------
module dffr #(
    parameter RESET_VAL = 1'b0
) (
    input  wire clk,
    input  wire rst,   // synchronous, active-high
    input  wire en,    // clock enable (hold when low)
    input  wire d,
    output reg  q
);
    always @(posedge clk) begin
        if (rst)     q <= RESET_VAL;
        else if (en) q <= d;
    end
endmodule


// -----------------------------------------------------------------------------
// registerN -- N-bit register built as an array of dffr cells. Each bit resets
//              to the corresponding bit of RESET_VAL.
// -----------------------------------------------------------------------------
module registerN #(
    parameter integer     WIDTH     = 8,
    parameter [WIDTH-1:0] RESET_VAL = {WIDTH{1'b0}}
) (
    input  wire             clk,
    input  wire             rst,
    input  wire             en,
    input  wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] q
);
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : bitslice
            dffr #(.RESET_VAL(RESET_VAL[i])) ff (
                .clk (clk),
                .rst (rst),
                .en  (en),
                .d   (d[i]),
                .q   (q[i])
            );
        end
    endgenerate
endmodule


// -----------------------------------------------------------------------------
// mux2 -- 1-bit 2:1 multiplexer.  sel=0 -> a, sel=1 -> b.
// -----------------------------------------------------------------------------
module mux2 (
    input  wire a,
    input  wire b,
    input  wire sel,
    output wire y
);
    wire nsel, ta, tb;
    not (nsel, sel);
    and (ta, a, nsel);
    and (tb, b, sel);
    or  (y, ta, tb);
endmodule


// -----------------------------------------------------------------------------
// mux2N -- N-bit 2:1 multiplexer (array of mux2).  sel=0 -> a, sel=1 -> b.
// -----------------------------------------------------------------------------
module mux2N #(
    parameter integer WIDTH = 8
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire             sel,
    output wire [WIDTH-1:0] y
);
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : m
            mux2 u (.a(a[i]), .b(b[i]), .sel(sel), .y(y[i]));
        end
    endgenerate
endmodule


// -----------------------------------------------------------------------------
// full_adder -- 1-bit full adder.  {cout,sum} = a + b + cin.
// -----------------------------------------------------------------------------
module full_adder (
    input  wire a,
    input  wire b,
    input  wire cin,
    output wire sum,
    output wire cout
);
    wire axb, t1, t2;
    xor (axb, a, b);
    xor (sum, axb, cin);
    and (t1, a, b);
    and (t2, axb, cin);
    or  (cout, t1, t2);
endmodule


// -----------------------------------------------------------------------------
// adderN -- N-bit ripple-carry adder.  {cout,sum} = a + b + cin.
// -----------------------------------------------------------------------------
module adderN #(
    parameter integer WIDTH = 8
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire             cin,
    output wire [WIDTH-1:0] sum,
    output wire             cout
);
    wire [WIDTH:0] carry;
    buf (carry[0], cin);
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : fa
            full_adder u (
                .a    (a[i]),
                .b    (b[i]),
                .cin  (carry[i]),
                .sum  (sum[i]),
                .cout (carry[i+1])
            );
        end
    endgenerate
    buf (cout, carry[WIDTH]);
endmodule


// -----------------------------------------------------------------------------
// eqN -- N-bit equality comparator.  eq = (a == b).
//        Per-bit XNOR, then an AND chain reduces the match bits.
// -----------------------------------------------------------------------------
module eqN #(
    parameter integer WIDTH = 8
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire             eq
);
    wire [WIDTH-1:0] biteq;
    wire [WIDTH-1:0] chain;
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : cmp
            xnor (biteq[i], a[i], b[i]);
        end
        buf (chain[0], biteq[0]);
        for (i = 1; i < WIDTH; i = i + 1) begin : andc
            and (chain[i], chain[i-1], biteq[i]);
        end
    endgenerate
    buf (eq, chain[WIDTH-1]);
endmodule


// -----------------------------------------------------------------------------
// geN -- N-bit unsigned "greater-than-or-equal".  ge = (a >= b).
//        Computes a + (~b) + 1 (= a - b); the carry-out is 1 iff a >= b.
// -----------------------------------------------------------------------------
module geN #(
    parameter integer WIDTH = 8
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire             ge
);
    wire [WIDTH-1:0] nb;
    wire [WIDTH-1:0] diff;   // subtraction result (unused)
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : inv
            not (nb[i], b[i]);
        end
    endgenerate
    adderN #(.WIDTH(WIDTH)) sub (
        .a    (a),
        .b    (nb),
        .cin  (1'b1),
        .sum  (diff),
        .cout (ge)
    );
endmodule


// -----------------------------------------------------------------------------
// gtN -- N-bit unsigned "greater-than".  gt = (a > b) = ~(b >= a).
// -----------------------------------------------------------------------------
module gtN #(
    parameter integer WIDTH = 8
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire             gt
);
    wire ge_ba;
    geN #(.WIDTH(WIDTH)) c (.a(b), .b(a), .ge(ge_ba));  // ge_ba = (b >= a)
    not (gt, ge_ba);                                    // gt = (a > b)
endmodule


// -----------------------------------------------------------------------------
// onehot_decoder -- binary select -> one-hot.  onehot[k] = (sel == k).
//                   Each output bit is an equality comparison against the
//                   constant k, so exactly one line is high for sel < OUT_WIDTH.
// -----------------------------------------------------------------------------
module onehot_decoder #(
    parameter integer SEL_WIDTH = 2,
    parameter integer OUT_WIDTH = 3
) (
    input  wire [SEL_WIDTH-1:0] sel,
    output wire [OUT_WIDTH-1:0] onehot
);
    genvar k;
    generate
        for (k = 0; k < OUT_WIDTH; k = k + 1) begin : d
            localparam [SEL_WIDTH-1:0] KV = k[SEL_WIDTH-1:0];
            eqN #(.WIDTH(SEL_WIDTH)) c (.a(sel), .b(KV), .eq(onehot[k]));
        end
    endgenerate
endmodule
