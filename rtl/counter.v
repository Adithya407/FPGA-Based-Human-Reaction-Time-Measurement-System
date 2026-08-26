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
//
// STRUCTURAL implementation. Control is expressed as three mutually-exclusive,
// priority-ordered events (rst has top priority via the register resets):
//
//   c_start = start & ~running                 -- begin a new measurement
//   c_stop  = stop  &  running & ~c_start      -- freeze the count
//   c_run   = running & ~c_start & ~c_stop     -- normal counting cycle
//
// Each register's next value / enable is then derived from those events with
// gate primitives and the adder/comparator/mux blocks in primitives.v.
// -----------------------------------------------------------------------------

module counter #(
    parameter integer CLKS_PER_MS = 125000,  // 125 MHz -> 1 ms tick
    parameter integer MS_WIDTH    = 10        // elapsed-ms output width (0..1023)
) (
    input  wire                clk,
    input  wire                rst,      // synchronous, active-high
    input  wire                start,    // begin measurement
    input  wire                stop,     // end measurement
    output wire [MS_WIDTH-1:0] ms,       // elapsed milliseconds
    output wire                done,     // high once stopped, until next start
    output wire                running   // high while actively counting
);

    // Width needed to hold the prescaler range 0 .. CLKS_PER_MS-1.
    localparam integer        PW           = (CLKS_PER_MS <= 1) ? 1 : $clog2(CLKS_PER_MS);
    localparam [PW-1:0]       PRESCALE_MAX = CLKS_PER_MS[PW-1:0] - 1'b1;
    // All-ones saturation value for the ms output.
    localparam [MS_WIDTH-1:0] MS_MAX       = {MS_WIDTH{1'b1}};

    wire [PW-1:0]       prescale;
    // ------------------------------------------------------------------------
    // Priority-ordered control events.
    // ------------------------------------------------------------------------
    wire not_running, c_start, c_stop, c_run;
    wire not_c_start, stop_and_run, not_c_stop, run_and_ncs;

    not (not_running, running);
    and (c_start, start, not_running);            // start & ~running

    and (stop_and_run, stop, running);
    not (not_c_start, c_start);
    and (c_stop, stop_and_run, not_c_start);      // stop & running & ~c_start

    not (not_c_stop, c_stop);
    and (run_and_ncs, running, not_c_start);
    and (c_run, run_and_ncs, not_c_stop);         // running & ~c_start & ~c_stop

    // ------------------------------------------------------------------------
    // running: set by c_start, cleared by c_stop, else held.
    //   d = c_start (1 on start, 0 on stop) ; en = c_start | c_stop
    // ------------------------------------------------------------------------
    wire run_en;
    or (run_en, c_start, c_stop);
    dffr #(1'b0) u_running (.clk(clk), .rst(rst), .en(run_en), .d(c_start), .q(running));

    // ------------------------------------------------------------------------
    // done: cleared by c_start, set by c_stop, else held.
    //   d = c_stop ; en = c_start | c_stop
    // ------------------------------------------------------------------------
    dffr #(1'b0) u_done (.clk(clk), .rst(rst), .en(run_en), .d(c_stop), .q(done));

    // ------------------------------------------------------------------------
    // prescale: cleared by c_start; on c_run, wrap at PRESCALE_MAX else +1.
    //   en = c_start | c_run
    // ------------------------------------------------------------------------
    wire at_max_p;
    eqN #(.WIDTH(PW)) u_pmax (.a(prescale), .b(PRESCALE_MAX), .eq(at_max_p));

    wire [PW-1:0] pre_plus1, pre_run_next, pre_next;
    wire          pre_co;
    adderN #(.WIDTH(PW)) u_pinc (
        .a(prescale), .b({PW{1'b0}}), .cin(1'b1), .sum(pre_plus1), .cout(pre_co)
    );
    // on c_run: at_max_p ? 0 : prescale+1
    mux2N #(.WIDTH(PW)) u_prun (
        .a(pre_plus1), .b({PW{1'b0}}), .sel(at_max_p), .y(pre_run_next)
    );
    // on c_start force 0, otherwise take the run value
    mux2N #(.WIDTH(PW)) u_pmux (
        .a(pre_run_next), .b({PW{1'b0}}), .sel(c_start), .y(pre_next)
    );
    wire pre_en;
    or (pre_en, c_start, c_run);
    registerN #(.WIDTH(PW), .RESET_VAL({PW{1'b0}})) u_prescale (
        .clk(clk), .rst(rst), .en(pre_en), .d(pre_next), .q(prescale)
    );

    // ------------------------------------------------------------------------
    // ms: cleared by c_start; increments on a prescaler tick while running,
    //     saturating at MS_MAX.
    //   ms_tick = c_run & at_max_p & (ms != MS_MAX)
    //   en      = c_start | ms_tick ;  d = c_start ? 0 : ms+1
    // ------------------------------------------------------------------------
    wire ms_is_max, ms_not_max, tick_pre, ms_tick, ms_en;
    eqN #(.WIDTH(MS_WIDTH)) u_msmax (.a(ms), .b(MS_MAX), .eq(ms_is_max));
    not (ms_not_max, ms_is_max);
    and (tick_pre, c_run, at_max_p);
    and (ms_tick, tick_pre, ms_not_max);
    or  (ms_en, c_start, ms_tick);

    wire [MS_WIDTH-1:0] ms_plus1, ms_next;
    wire                ms_co;
    adderN #(.WIDTH(MS_WIDTH)) u_msinc (
        .a(ms), .b({MS_WIDTH{1'b0}}), .cin(1'b1), .sum(ms_plus1), .cout(ms_co)
    );
    mux2N #(.WIDTH(MS_WIDTH)) u_msmux (
        .a(ms_plus1), .b({MS_WIDTH{1'b0}}), .sel(c_start), .y(ms_next)
    );
    registerN #(.WIDTH(MS_WIDTH), .RESET_VAL({MS_WIDTH{1'b0}})) u_ms (
        .clk(clk), .rst(rst), .en(ms_en), .d(ms_next), .q(ms)
    );

endmodule
