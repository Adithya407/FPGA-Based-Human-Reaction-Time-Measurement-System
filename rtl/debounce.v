// -----------------------------------------------------------------------------
// debounce.v -- push-button debouncer with input synchronizer
//
// Two stages:
//   1. A 2-flip-flop synchronizer brings the asynchronous button into the
//      125 MHz clock domain (metastability hardening).
//   2. A stability counter: the synchronized level must remain different from
//      the current output for STABLE_COUNT consecutive clocks before the
//      output is allowed to follow it. Any bounce back to the current output
//      value restarts the count, so glitches shorter than the window are
//      rejected.
//
// STABLE_COUNT is a parameter so the testbench can shrink the window for fast
// simulation. At 125 MHz, 10 ms = 1_250_000 clock cycles.
//
// Total latency from a clean edge to btn_out changing is STABLE_COUNT + 2
// clocks (2 for the synchronizer).
//
// STRUCTURAL implementation: the two synchronizer flops and the stability
// counter/output flops are `dffr`/`registerN` instances; the control terms
// (level match, window-elapsed, count clear, output update-enable) are gate
// primitives and comparator/adder/mux blocks. See primitives.v.
// -----------------------------------------------------------------------------

module debounce #(
    parameter integer STABLE_COUNT = 1250000  // ~10 ms @ 125 MHz
) (
    input  wire clk,
    input  wire rst,      // synchronous, active-high
    input  wire btn_in,   // raw, asynchronous button input
    output wire btn_out   // clean, synchronized, debounced output
);

    // Width needed to count 0 .. STABLE_COUNT-1.
    localparam integer      CW   = (STABLE_COUNT <= 1) ? 1 : $clog2(STABLE_COUNT);
    // Terminal count value (window elapsed) as a CW-bit constant.
    localparam [CW-1:0]     TERM = STABLE_COUNT[CW-1:0] - 1'b1;

    // --- Stage 1: 2-FF synchronizer -----------------------------------------
    wire sync_0, sync_1;
    dffr #(1'b0) u_sync0 (.clk(clk), .rst(rst), .en(1'b1), .d(btn_in), .q(sync_0));
    dffr #(1'b0) u_sync1 (.clk(clk), .rst(rst), .en(1'b1), .d(sync_0), .q(sync_1));

    wire btn_sync;
    buf (btn_sync, sync_1);

    // --- Stage 2: stability counter -----------------------------------------
    wire [CW-1:0] count;

    // match     : synchronized input already equals the output (nothing pending)
    // at_window : the new level has been held STABLE_COUNT clocks
    wire match, at_window;
    xnor (match, btn_sync, btn_out);            // 1-bit equality (a == b)
    eqN #(.WIDTH(CW)) u_atwin (.a(count), .b(TERM), .eq(at_window));

    // Count next value:
    //   clear when the level matches the output OR the window has elapsed;
    //   otherwise keep timing (count + 1).
    wire clear_count;
    or (clear_count, match, at_window);

    wire [CW-1:0] count_plus1, count_next;
    wire          cnt_co;
    adderN #(.WIDTH(CW)) u_inc (
        .a (count), .b ({CW{1'b0}}), .cin (1'b1), .sum (count_plus1), .cout (cnt_co)
    );
    mux2N #(.WIDTH(CW)) u_cntmux (
        .a (count_plus1), .b ({CW{1'b0}}), .sel (clear_count), .y (count_next)
    );

    registerN #(.WIDTH(CW), .RESET_VAL({CW{1'b0}})) u_count (
        .clk (clk), .rst (rst), .en (1'b1), .d (count_next), .q (count)
    );

    // Output flop: adopt the new synchronized level only when the window has
    // elapsed and the level does not already match (match has priority).
    wire not_match, out_en;
    not (not_match, match);
    and (out_en, at_window, not_match);

    dffr #(1'b0) u_out (
        .clk (clk), .rst (rst), .en (out_en), .d (btn_sync), .q (btn_out)
    );

endmodule
