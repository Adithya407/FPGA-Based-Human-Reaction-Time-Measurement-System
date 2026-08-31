set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports clk]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports btn_reset]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports btn_start]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports led_stimulus]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports led_false_start]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports pmod_button_in]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {seg[6]}]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {seg[5]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {seg[4]}]
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {seg[3]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {seg[2]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {seg[1]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {seg[0]}]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports {an[0]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {an[1]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {an[2]}]
## ============================================================================
## zybo_top.xdc -- pin constraints for rtl/top.v on the Digilent ZYBO (Zynq-7010)
##
## !!! PLACEHOLDER PIN ASSIGNMENTS -- VERIFY BEFORE IMPLEMENTATION !!!
##
## Every PACKAGE_PIN below is a best-effort guess based on the commonly cited
## Digilent ZYBO master XDC. The trailing comment on each line names the ZYBO
## reference-manual signal (sysclk, BTNx, LDx, JxN) it is meant to map to --
## cross-check each one against the ZYBO reference manual / official master XDC
## for YOUR board revision and correct as needed. The Zybo Z7 (7010/7020) uses
## different pins than the original ZYBO; confirm which board you have.
##
## All PL I/O on the ZYBO is 3.3 V -> IOSTANDARD LVCMOS33.
##
## Port map (rtl/top.v):
##   clk             -> system clock          (onboard 125 MHz oscillator)
##   btn_reset       -> reset push-button     (onboard BTN)
##   btn_start       -> start-trial button    (onboard BTN)   [added port]
##   led_stimulus    -> stimulus LED          (onboard LD)
##   led_false_start -> false-start LED       (onboard LD)     [added port]
##   pmod_button_in  -> external push-button  (PMOD header pin)
##   seg[6:0]        -> 7-seg segments a..g   (PMOD header pins)
##   an[2:0]         -> 7-seg digit-select    (PMOD header pins)
## ============================================================================


## ---------------------------------------------------------------------------
## System clock -- 125 MHz onboard oscillator
## ---------------------------------------------------------------------------
create_clock -period 8.000 -name sys_clk_pin -waveform {0.000 4.000} -add [get_ports clk]


## ---------------------------------------------------------------------------
## Onboard push-buttons (active-high on ZYBO)
## ---------------------------------------------------------------------------


## ---------------------------------------------------------------------------
## Onboard LEDs (active-high on ZYBO)
## ---------------------------------------------------------------------------


## ---------------------------------------------------------------------------
## External push-button on a PMOD header pin
##   Uses PMOD JC top-row pin 1.
## ---------------------------------------------------------------------------


## ---------------------------------------------------------------------------
## Seven-segment display on PMOD header pins
##   Segments seg[6:0] = a,b,c,d,e,f,g  (seg[6]=a ... seg[0]=g, active-high)
##   Digit-select an[2:0] (one-hot)     (an[0]=ones, an[1]=tens, an[2]=hundreds)
##
##   Segments a..g mapped across PMOD JD (all 8 pins), plus an[0] on JD10.
##   Remaining digit-selects an[1], an[2] on PMOD JE.
## ---------------------------------------------------------------------------


set_load 5.000 [all_outputs]
set_property LOAD 5 [get_ports {an[0]}]
set_property LOAD 5 [get_ports {an[1]}]
set_property LOAD 5 [get_ports {an[2]}]
set_property LOAD 5 [get_ports led_false_start]
set_property LOAD 5 [get_ports led_stimulus]
set_property LOAD 5 [get_ports {seg[0]}]
set_property LOAD 5 [get_ports {seg[1]}]
set_property LOAD 5 [get_ports {seg[2]}]
set_property LOAD 5 [get_ports {seg[3]}]
set_property LOAD 5 [get_ports {seg[4]}]
set_property LOAD 5 [get_ports {seg[5]}]
set_property LOAD 5 [get_ports {seg[6]}]
