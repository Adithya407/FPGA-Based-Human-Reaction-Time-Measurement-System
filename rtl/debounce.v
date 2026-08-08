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
// -----------------------------------------------------------------------------

module debounce #(
    parameter integer STABLE_COUNT = 1250000  // ~10 ms @ 125 MHz
) (
    input  wire clk,
    input  wire rst,      // synchronous, active-high
    input  wire btn_in,   // raw, asynchronous button input
    output reg  btn_out   // clean, synchronized, debounced output
);

    // Width needed to count 0 .. STABLE_COUNT-1.
    localparam integer CW = (STABLE_COUNT <= 1) ? 1 : $clog2(STABLE_COUNT);

    // --- Stage 1: 2-FF synchronizer -----------------------------------------
    reg sync_0, sync_1;
    always @(posedge clk) begin
        if (rst) begin
            sync_0 <= 1'b0;
            sync_1 <= 1'b0;
        end
        else begin
            sync_0 <= btn_in;
            sync_1 <= sync_0;
        end
    end
    wire btn_sync = sync_1;

    // --- Stage 2: stability counter -----------------------------------------
    reg [CW-1:0] count;
    always @(posedge clk) begin
        if (rst) begin
            count   <= {CW{1'b0}};
            btn_out <= 1'b0;
        end
        else if (btn_sync == btn_out) begin
            // Synchronized input already matches the output: nothing pending.
            count <= {CW{1'b0}};
        end
        else if (count == STABLE_COUNT[CW-1:0] - 1'b1) begin
            // Held at the new level long enough -> accept it.
            btn_out <= btn_sync;
            count   <= {CW{1'b0}};
        end
        else begin
            // New level is stable so far; keep timing it.
            count <= count + 1'b1;
        end
    end

endmodule
