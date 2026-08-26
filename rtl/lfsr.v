// -----------------------------------------------------------------------------
// lfsr.v -- 8-bit Fibonacci LFSR (pseudo-random delay generator)
//
// Maximal-length (period 255) 8-bit sequence using the primitive polynomial
//     x^8 + x^6 + x^5 + x^4 + 1
// Feedback taps at positions 8, 6, 5, 4  ->  register bits [7], [5], [4], [3].
//
// Fibonacci form: the XOR of the tapped bits is fed into the LSB while the
// register shifts left. An all-zero state is a lock-up state for any LFSR, so
// the synchronous reset loads a non-zero SEED value.
//
// STRUCTURAL implementation: the state is an 8-bit `registerN`; the next-state
// value is selected by 2:1 muxes and the feedback bit is a single XOR gate.
// See primitives.v for the building blocks.
// -----------------------------------------------------------------------------

module lfsr #(
    parameter [7:0] SEED = 8'hFF   // non-zero reset value (must never be 0)
) (
    input  wire       clk,         // clock
    input  wire       rst,         // synchronous, active-high reset
    input  wire       load,        // synchronous load of `seed_in`
    input  wire [7:0] seed_in,     // external seed (loaded when `load` asserted)
    output wire [7:0] value        // current LFSR state
);

    wire [7:0] state;              // current register contents

    // --- Fibonacci feedback: x^8 + x^6 + x^5 + x^4 + 1 ----------------------
    wire feedback;
    xor (feedback, state[7], state[5], state[4], state[3]);

    // Shift-left result with the feedback bit entering the LSB: {state[6:0], fb}
    wire [7:0] shift_val;
    assign shift_val = {state[6:0], feedback};   // pure wiring (concatenation)

    // --- Seed selection: reject an all-zero external seed -------------------
    wire seed_is_zero;
    eqN #(.WIDTH(8)) u_zero (.a(seed_in), .b(8'h00), .eq(seed_is_zero));

    // load_val = (seed_in == 0) ? SEED : seed_in
    wire [7:0] load_val;
    mux2N #(.WIDTH(8)) u_seedmux (
        .a   (seed_in),
        .b   (SEED),
        .sel (seed_is_zero),
        .y   (load_val)
    );

    // --- Next-state select: load ? load_val : shift_val ---------------------
    wire [7:0] next_state;
    mux2N #(.WIDTH(8)) u_nextmux (
        .a   (shift_val),
        .b   (load_val),
        .sel (load),
        .y   (next_state)
    );

    // --- State register: resets to the non-zero SEED, always enabled --------
    registerN #(.WIDTH(8), .RESET_VAL(SEED)) u_state (
        .clk (clk),
        .rst (rst),
        .en  (1'b1),
        .d   (next_state),
        .q   (state)
    );

    assign value = state;          // pure wiring (output alias)

endmodule
