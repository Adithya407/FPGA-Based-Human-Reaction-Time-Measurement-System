# FPGA-Based Human Reaction Time Measurement System

**Course:** 23ECE383 VLSI Design Laboratory — 2026-27 Odd Semester (Class ECE B)
**Team Name:** Team Latency

## Team Members

| Roll Number | Name |
|---|---|
| CB.EN.U4ECE24106 | Beesetty Rohith |
| CB.EN.U4ECE24129 | Kodiyalam Vasantha Krishnan |
| CB.EN.U4ECE24133 | Lalithaditya Krishna Enukonda |

## Overview

Human reaction time is the interval between a visual stimulus and the corresponding motor response. This project implements an FPGA-based human reaction time measurement system in Verilog, targeting the Digilent ZYBO (ZYNQ-7000 SoC) board.

A Finite State Machine (FSM) controls the overall measurement process, while a Linear Feedback Shift Register (LFSR) generates a pseudo-random delay before the stimulus is triggered, preventing the user from anticipating the response window.

When the LED stimulus is activated, a synchronous counter starts measuring elapsed time until a debounced PMOD push-button is pressed. The measured time is converted into milliseconds and displayed on a PMOD seven-segment display. A false-start detection mechanism resets the system if the button is pressed before the stimulus appears.

The design is simulated in Xilinx Vivado and implemented on the ZYBO (ZYNQ-7000 SoC) board.

## Objectives

- Design and implement a digital system that accurately measures human visual-to-motor reaction time using FPGA-based sequential logic.
- Implement core digital design concepts including FSM, synchronous counters, debouncing logic, and seven-segment display driving.
- Interface a PMOD push button and a PMOD seven-segment display with the FPGA.
- Generate pseudo-random stimulus delays using an LFSR to eliminate user anticipation.
- Perform functional simulation and design verification in Vivado.
- Extend the base system into a more advanced reaction-time analysis tool on hardware.

## System Components

- **FSM** — controls the sequence of states: idle, random delay, stimulus, measurement, result, and false-start reset.
- **LFSR** — generates pseudo-random delay values to randomize stimulus timing.
- **Synchronous Counter** — measures elapsed time between stimulus and button press.
- **Debouncing Logic** — filters mechanical noise from the PMOD push-button input.
- **Seven-Segment Display Driver** — converts and displays the measured reaction time in milliseconds via the PMOD seven-segment display.
- **False-Start Detection** — resets the system if the button is pressed before the stimulus is triggered.

## Hardware & Tools

- **Target Board:** Digilent ZYBO Board (ZYNQ-7000 SoC)
- **Peripherals:** PMOD Push Button, PMOD Seven-Segment Display, onboard LED
- **HDL:** Verilog
- **Simulation & Implementation Tool:** Xilinx Vivado
