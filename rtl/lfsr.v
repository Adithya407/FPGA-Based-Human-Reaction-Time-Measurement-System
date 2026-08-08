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

    reg [7:0] state;

    // Fibonacci feedback: x^8 + x^6 + x^5 + x^4 + 1
    wire feedback = state[7] ^ state[5] ^ state[4] ^ state[3];

    always @(posedge clk) begin
        if (rst)
            state <= SEED;                     // guaranteed non-zero on reset
        else if (load)
            state <= (seed_in == 8'h00) ? SEED // reject an all-zero seed
                                        : seed_in;
        else
            state <= {state[6:0], feedback};   // shift left, feedback into LSB
    end

    assign value = state;

endmodule
