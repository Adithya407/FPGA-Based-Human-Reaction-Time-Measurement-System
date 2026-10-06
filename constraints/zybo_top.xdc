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
##
##     [ Pmod SSD #1: JE + JD top rows ]  [ Pmod SSD #2: JC ]
##        hundreds         tens               ones    (dark)
##
##   Pmod SSD #1 plugs straight into the TOP ROWS of two ports:
##     J2 -> JE pins 1-6   (AE AF AG C  GND VCC)   hundreds digit over JE
##     J1 -> JD pins 1-6   (AA AB AC AD GND VCC)   tens digit over JD
##   Pmod SSD #2 uses BOTH rows of JC (2x6-to-dual-6 splitter cable or wires):
##     JC pins 1-6  -> J1 pins 1-6 (AA AB AC AD GND VCC)
##     JC pins 7-12 -> J2 pins 1-6 (AE AF AG C  GND VCC)
##   Place SSD #2 to the RIGHT of SSD #1; ones shows on its LEFT digit.
##
## Port map (rtl/top.v) -- 22 I/O: 4 inputs, 18 outputs
##
##   Port             Dir  Pin  Zybo resource   SSD pin   Notes
##   ---------------  ---  ---  --------------  --------  ----------------------
##   clk              in   K17  sysclk 125 MHz            MRCC clock-capable pin
##   btn_reset        in   K18  BTN0                      active-high
##   btn_start        in   P16  BTN1                      active-high
##   pmod_button_in   in   K19  BTN2                      active-high (response)
##   led_stimulus     out  M14  LD0                       active-high
##   led_false_start  out  M15  LD1                       active-high
##   ssd_ht_seg[6]    out  T14  Pmod JD pin 1   #1 J1-1   AA  segment a
##   ssd_ht_seg[5]    out  T15  Pmod JD pin 2   #1 J1-2   AB  segment b
##   ssd_ht_seg[4]    out  P14  Pmod JD pin 3   #1 J1-3   AC  segment c
##   ssd_ht_seg[3]    out  R14  Pmod JD pin 4   #1 J1-4   AD  segment d
##   ssd_ht_seg[2]    out  V12  Pmod JE pin 1   #1 J2-1   AE  segment e
##   ssd_ht_seg[1]    out  W16  Pmod JE pin 2   #1 J2-2   AF  segment f
##   ssd_ht_seg[0]    out  J15  Pmod JE pin 3   #1 J2-3   AG  segment g
##   ssd_ht_c         out  H15  Pmod JE pin 4   #1 J2-4   C   1=hundreds 0=tens
##   ssd_ones_seg[6]  out  V15  Pmod JC pin 1   #2 J1-1   AA  segment a
##   ssd_ones_seg[5]  out  W15  Pmod JC pin 2   #2 J1-2   AB  segment b
##   ssd_ones_seg[4]  out  T11  Pmod JC pin 3   #2 J1-3   AC  segment c
##   ssd_ones_seg[3]  out  T10  Pmod JC pin 4   #2 J1-4   AD  segment d
##   ssd_ones_seg[2]  out  W14  Pmod JC pin 7   #2 J2-1   AE  segment e
##   ssd_ones_seg[1]  out  Y14  Pmod JC pin 8   #2 J2-2   AF  segment f
##   ssd_ones_seg[0]  out  T12  Pmod JC pin 9   #2 J2-3   AG  segment g
##   ssd_ones_c       out  U12  Pmod JC pin 10  #2 J2-4   C   1=ones (fixed)
##
## Note: JE is a "standard" Pmod with 200-ohm series resistors; JC and JD are
## "high-speed" Pmods with 0-ohm shunts. On SSD #1, segments e/f/g and C go
## through JE's resistors while a/b/c/d do not, so those segments or one of its
## digits may look slightly dimmer than the rest.
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
##   BTN2 is the reaction-time response button (port name kept as
##   pmod_button_in so the RTL and testbenches are unchanged).
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports btn_reset];       # IO_L12N_T1_MRCC_35 Sch=btn[0]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports btn_start];       # IO_L24N_T3_34      Sch=btn[1]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS33} [get_ports pmod_button_in];  # IO_L10P_T1_AD11P_35 Sch=btn[2]


## ---------------------------------------------------------------------------
## Onboard LEDs (anode-connected via 330 ohm -> logic 1 = on)
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports led_stimulus];    # IO_L23P_T3_35      Sch=led[0]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports led_false_start]; # IO_L23N_T3_35      Sch=led[1]


## ---------------------------------------------------------------------------
## Pmod SSD #1 -- hundreds (left digit) | tens (right digit)
##   Plugged directly into the top rows of JE (its J2) and JD (its J1).
##   Segments active-high. C = 1 lights the left digit, C = 0 the right.
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {ssd_ht_seg[6]}];   # IO_L5P_T0_34       Sch=jd_p[1]  JD1 -> J1-1 AA
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {ssd_ht_seg[5]}];   # IO_L5N_T0_34       Sch=jd_n[1]  JD2 -> J1-2 AB
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {ssd_ht_seg[4]}];   # IO_L6P_T0_34       Sch=jd_p[2]  JD3 -> J1-3 AC
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {ssd_ht_seg[3]}];   # IO_L6N_T0_VREF_34  Sch=jd_n[2]  JD4 -> J1-4 AD
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {ssd_ht_seg[2]}];   # IO_L4P_T0_34       Sch=je[1]    JE1 -> J2-1 AE
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {ssd_ht_seg[1]}];   # IO_L18N_T2_34      Sch=je[2]    JE2 -> J2-2 AF
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {ssd_ht_seg[0]}];   # IO_25_35           Sch=je[3]    JE3 -> J2-3 AG
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports ssd_ht_c];          # IO_L19P_T3_35      Sch=je[4]    JE4 -> J2-4 C


## ---------------------------------------------------------------------------
## Pmod SSD #2 -- ones (left digit) | unused (right digit) -- on Pmod JC
##   C is held at 1, so only the left digit is ever used.
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {ssd_ones_seg[6]}]; # IO_L10P_T1_34      Sch=jc_p[1]  JC1  -> J1-1 AA
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports {ssd_ones_seg[5]}]; # IO_L10N_T1_34      Sch=jc_n[1]  JC2  -> J1-2 AB
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {ssd_ones_seg[4]}]; # IO_L1P_T0_34       Sch=jc_p[2]  JC3  -> J1-3 AC
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {ssd_ones_seg[3]}]; # IO_L1N_T0_34       Sch=jc_n[2]  JC4  -> J1-4 AD
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports {ssd_ones_seg[2]}]; # IO_L8P_T1_34       Sch=jc_p[3]  JC7  -> J2-1 AE
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports {ssd_ones_seg[1]}]; # IO_L8N_T1_34       Sch=jc_n[3]  JC8  -> J2-2 AF
set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVCMOS33} [get_ports {ssd_ones_seg[0]}]; # IO_L2P_T0_34       Sch=jc_p[4]  JC9  -> J2-3 AG
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports ssd_ones_c];        # IO_L2N_T0_34       Sch=jc_n[4]  JC10 -> J2-4 C


## ---------------------------------------------------------------------------
## I/O timing
##   Every input is asynchronous to clk and is re-timed inside the design
##   (2-FF reset synchronizer in top.v, 2-FF synchronizer in debounce.v).
##   Every output drives an LED or a ~1 kHz multiplexed display. None of these
##   paths has a meaningful external timing requirement, so exclude them from
##   timing analysis instead of leaving them unconstrained.
## ---------------------------------------------------------------------------
set_false_path -from [get_ports {btn_reset btn_start pmod_button_in}]
set_false_path -to   [get_ports {led_stimulus led_false_start {ssd_ht_seg[*]} ssd_ht_c {ssd_ones_seg[*]} ssd_ones_c}]

## Output load estimate (pF) for power and output-timing reports.
set_load 5.000 [all_outputs]
