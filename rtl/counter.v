// -----------------------------------------------------------------------------
// counter.v -- synchronous millisecond (elapsed-time) counter
//
// Divides the 125 MHz system clock down to 1 ms ticks and counts those ticks
// while running, giving the elapsed reaction time in milliseconds.
//
//   start : active-high, begins a fresh measurement (clears count and `done`)
//   stop  : active-high, freezes the count and raises `done`
//   rst   : synchronous, active-high, clears everything
//
// CLKS_PER_MS is a parameter so the testbench can override it with a small
// value for fast simulation. At 125 MHz, 1 ms = 125_000 clock cycles.
//
// The ms output saturates at its maximum value instead of wrapping, so a very
// long (or missing) response cannot alias to a small time.
// -----------------------------------------------------------------------------

module counter #(
    parameter integer CLKS_PER_MS = 125000,  // 125 MHz -> 1 ms tick
    parameter integer MS_WIDTH    = 10        // elapsed-ms output width (0..1023)
) (
    input  wire                clk,
    input  wire                rst,      // synchronous, active-high
    input  wire                start,    // begin measurement
    input  wire                stop,     // end measurement
    output reg  [MS_WIDTH-1:0] ms,       // elapsed milliseconds
    output reg                 done,     // high once stopped, until next start
    output reg                 running   // high while actively counting
);

    // Width needed to hold the prescaler range 0 .. CLKS_PER_MS-1.
    localparam integer PW           = (CLKS_PER_MS <= 1) ? 1 : $clog2(CLKS_PER_MS);
    localparam integer PRESCALE_MAX = CLKS_PER_MS - 1;

    reg [PW-1:0] prescale;

    // Convenience: all-ones saturation value for the ms output.
    localparam [MS_WIDTH-1:0] MS_MAX = {MS_WIDTH{1'b1}};

    always @(posedge clk) begin
        if (rst) begin
            running  <= 1'b0;
            done     <= 1'b0;
            ms       <= {MS_WIDTH{1'b0}};
            prescale <= {PW{1'b0}};
        end
        else if (start && !running) begin
            // Kick off a new measurement.
            running  <= 1'b1;
            done     <= 1'b0;
            ms       <= {MS_WIDTH{1'b0}};
            prescale <= {PW{1'b0}};
        end
        else if (stop && running) begin
            // Freeze the count. (Priority over the tick logic below, so the
            // stopping edge never sneaks in an extra millisecond.)
            running <= 1'b0;
            done    <= 1'b1;
        end
        else if (running) begin
            if (prescale == PRESCALE_MAX[PW-1:0]) begin
                prescale <= {PW{1'b0}};
                if (ms != MS_MAX)          // saturate instead of wrapping
                    ms <= ms + 1'b1;
            end
            else begin
                prescale <= prescale + 1'b1;
            end
        end
    end

endmodule
