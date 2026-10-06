## ============================================================================
## zybo_top.xdc -- pin and timing constraints for rtl/top.v
##
## Board : Digilent Zybo Z7 (Rev. B)
##           Zybo Z7-10 -> part xc7z010clg400-1
##           Zybo Z7-20 -> part xc7z020clg400-1
##         Both variants use the CLG400 package and the same pins for every
##         resource used here (JB, RGB LED5 and the fan are Z7-20 only and are
##         not used by this design).
##
## Source: Digilent Zybo-Z7-Master.xdc (github.com/Digilent/digilent-xdc) and
##         the Zybo Z7 reference manual. NOTE: the original (non-Z7) ZYBO uses
##         a different clock and BTN0 pin -- this file is for the Zybo Z7 only.
##
## All PL I/O used here is 3.3 V -> IOSTANDARD LVCMOS33.
##
## Display: two Digilent Pmod SSD modules (2 digits each, 3 digits used)
##   Pmod SSD #1 (tens | ones)     on Pmod JD
##   Pmod SSD #2 (unused | hundreds) on Pmod JC
##   Place SSD #2 to the LEFT of SSD #1 so the digits read  _ H T O.
##
##   Each Pmod SSD has two 1x6 headers (J1, J2); each Zybo Pmod port is 2x6.
##   Connect each module with a Digilent 2x6-pin to dual 6-pin splitter cable
##   (or 12 jumper wires):
##     Zybo port top row    pins 1-6  -> SSD J1 pins 1-6  (AA AB AC AD GND VCC)
##     Zybo port bottom row pins 7-12 -> SSD J2 pins 1-6  (AE AF AG C  GND VCC)
##   Line up pin 1 on both ends so GND and VCC (3.3 V) land on GND and VCC.
##
## Port map (rtl/top.v) -- 22 I/O: 4 inputs, 18 outputs
##
##   Port             Dir  Pin  Zybo resource   SSD pin   Notes
##   ---------------  ---  ---  --------------  --------  ----------------------
##   clk              in   K17  sysclk 125 MHz            MRCC clock-capable pin
##   btn_reset        in   K18  BTN0                      active-high
##   btn_start        in   P16  BTN1                      active-high
##   pmod_button_in   in   V12  Pmod JE pin 1             active-high, int. pulldown
##   led_stimulus     out  M14  LD0                       active-high
##   led_false_start  out  M15  LD1                       active-high
##   ssd_lo_seg[6]    out  T14  Pmod JD pin 1   #1 J1-1   AA  segment a
##   ssd_lo_seg[5]    out  T15  Pmod JD pin 2   #1 J1-2   AB  segment b
##   ssd_lo_seg[4]    out  P14  Pmod JD pin 3   #1 J1-3   AC  segment c
##   ssd_lo_seg[3]    out  R14  Pmod JD pin 4   #1 J1-4   AD  segment d
##   ssd_lo_seg[2]    out  U14  Pmod JD pin 7   #1 J2-1   AE  segment e
##   ssd_lo_seg[1]    out  U15  Pmod JD pin 8   #1 J2-2   AF  segment f
##   ssd_lo_seg[0]    out  V17  Pmod JD pin 9   #1 J2-3   AG  segment g
##   ssd_lo_c         out  V18  Pmod JD pin 10  #1 J2-4   C   0=ones 1=tens
##   ssd_hi_seg[6]    out  V15  Pmod JC pin 1   #2 J1-1   AA  segment a
##   ssd_hi_seg[5]    out  W15  Pmod JC pin 2   #2 J1-2   AB  segment b
##   ssd_hi_seg[4]    out  T11  Pmod JC pin 3   #2 J1-3   AC  segment c
##   ssd_hi_seg[3]    out  T10  Pmod JC pin 4   #2 J1-4   AD  segment d
##   ssd_hi_seg[2]    out  W14  Pmod JC pin 7   #2 J2-1   AE  segment e
##   ssd_hi_seg[1]    out  Y14  Pmod JC pin 8   #2 J2-2   AF  segment f
##   ssd_hi_seg[0]    out  T12  Pmod JC pin 9   #2 J2-3   AG  segment g
##   ssd_hi_c         out  U12  Pmod JC pin 10  #2 J2-4   C   0=hundreds (fixed)
##
## Why JC + JD for the displays: both are "high-speed" Pmods (0-ohm series
## shunts), so the two modules get identical drive and match in brightness.
## JE is a "standard" Pmod (200-ohm series resistors), which suits the
## hand-wired response button.
## ============================================================================


## ---------------------------------------------------------------------------
## System clock -- 125 MHz on K17
##   On the Zybo Z7 this clock is the CLK125 output of the Ethernet PHY. It
##   stops if the PHY is held in reset (PHYRSTB, PL pin E17, driven low). This
##   design leaves E17 unused; never drive it low.
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports clk];             # IO_L12P_T1_MRCC_35 Sch=sysclk
create_clock -period 8.000 -name sys_clk_pin -waveform {0.000 4.000} -add [get_ports clk]


## ---------------------------------------------------------------------------
## Onboard push-buttons (low at rest, high when pressed)
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports btn_reset];       # IO_L12N_T1_MRCC_35 Sch=btn[0]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports btn_start];       # IO_L24N_T3_34      Sch=btn[1]


## ---------------------------------------------------------------------------
## Onboard LEDs (anode-connected via 330 ohm -> logic 1 = on)
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports led_stimulus];    # IO_L23P_T3_35      Sch=led[0]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports led_false_start]; # IO_L23N_T3_35      Sch=led[1]


## ---------------------------------------------------------------------------
## External response button on Pmod JE pin 1
##   The RTL treats a press as logic 1. Wire the button between JE pin 1 and
##   JE pin 6 (3.3 V); the internal pull-down holds the input low at rest.
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33 PULLDOWN true} [get_ports pmod_button_in]; # IO_L4P_T0_34 Sch=je[1]


## ---------------------------------------------------------------------------
## Pmod SSD #1 -- tens (left digit) | ones (right digit) -- on Pmod JD
##   Segments active-high. C = 0 lights the right digit, C = 1 the left.
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {ssd_lo_seg[6]}]; # IO_L5P_T0_34       Sch=jd_p[1]  JD1  -> J1-1 AA
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {ssd_lo_seg[5]}]; # IO_L5N_T0_34       Sch=jd_n[1]  JD2  -> J1-2 AB
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {ssd_lo_seg[4]}]; # IO_L6P_T0_34       Sch=jd_p[2]  JD3  -> J1-3 AC
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {ssd_lo_seg[3]}]; # IO_L6N_T0_VREF_34  Sch=jd_n[2]  JD4  -> J1-4 AD
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {ssd_lo_seg[2]}]; # IO_L11P_T1_SRCC_34 Sch=jd_p[3]  JD7  -> J2-1 AE
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {ssd_lo_seg[1]}]; # IO_L11N_T1_SRCC_34 Sch=jd_n[3]  JD8  -> J2-2 AF
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {ssd_lo_seg[0]}]; # IO_L21P_T3_DQS_34  Sch=jd_p[4]  JD9  -> J2-3 AG
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports ssd_lo_c];        # IO_L21N_T3_DQS_34  Sch=jd_n[4]  JD10 -> J2-4 C


## ---------------------------------------------------------------------------
## Pmod SSD #2 -- unused (left digit) | hundreds (right digit) -- on Pmod JC
##   C is held at 0, so only the right digit is ever used.
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {ssd_hi_seg[6]}]; # IO_L10P_T1_34      Sch=jc_p[1]  JC1  -> J1-1 AA
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports {ssd_hi_seg[5]}]; # IO_L10N_T1_34      Sch=jc_n[1]  JC2  -> J1-2 AB
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {ssd_hi_seg[4]}]; # IO_L1P_T0_34       Sch=jc_p[2]  JC3  -> J1-3 AC
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {ssd_hi_seg[3]}]; # IO_L1N_T0_34       Sch=jc_n[2]  JC4  -> J1-4 AD
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports {ssd_hi_seg[2]}]; # IO_L8P_T1_34       Sch=jc_p[3]  JC7  -> J2-1 AE
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports {ssd_hi_seg[1]}]; # IO_L8N_T1_34       Sch=jc_n[3]  JC8  -> J2-2 AF
set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVCMOS33} [get_ports {ssd_hi_seg[0]}]; # IO_L2P_T0_34       Sch=jc_p[4]  JC9  -> J2-3 AG
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports ssd_hi_c];        # IO_L2N_T0_34       Sch=jc_n[4]  JC10 -> J2-4 C


## ---------------------------------------------------------------------------
## I/O timing
##   Every input is asynchronous to clk and is re-timed inside the design
##   (2-FF reset synchronizer in top.v, 2-FF synchronizer in debounce.v).
##   Every output drives an LED or a ~1 kHz multiplexed display. None of these
##   paths has a meaningful external timing requirement, so exclude them from
##   timing analysis instead of leaving them unconstrained.
## ---------------------------------------------------------------------------
set_false_path -from [get_ports {btn_reset btn_start pmod_button_in}]
set_false_path -to   [get_ports {led_stimulus led_false_start {ssd_lo_seg[*]} ssd_lo_c {ssd_hi_seg[*]} ssd_hi_c}]

## Output load estimate (pF) for power and output-timing reports.
set_load 5.000 [all_outputs]
