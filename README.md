# FPGA Enigma I

A faithful hardware implementation of the Wehrmacht Enigma I cipher machine in Verilog, targeting the Lattice iCE40-HX8K Breakout Board (ICE40HX8K-B-EVN).

Communicate with the machine over a 115200-baud serial terminal — type a letter, get the enciphered letter back instantly, exactly as the original 1930s electromechanical device would have produced it.

## Features

- **All five standard rotors (I-V)** with correct historical wiring tables
- **Reflector UKW-B** with the no-self-mapping property
- **Double-step anomaly** — the middle rotor's mechanical quirk is accurately reproduced
- **Plugboard** — up to 13 reciprocal letter pairs, configurable at runtime
- **Runtime configuration** — set rotors, rings, positions, and plugboard pairs over UART
- **Self-reciprocal** — encrypt with one setting, decrypt by typing the ciphertext with the same setting
- **2-cycle cipher pipeline** at 12 MHz, 115200-baud 8N1 UART

## Hardware Requirements

- **Lattice iCE40-HX8K Breakout Board** (ICE40HX8K-B-EVN)
- USB cable (board provides power and serial via onboard FTDI FT2232HL)
- Serial terminal: minicom, screen, PuTTY, etc.

## Resource Utilization

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUT4s | 3,182 | 7,680 | 41% |
| Flip-flops | 518 | 7,680 | 7% |
| Carry chains | 513 | — | — |
| Block RAM | 0 | 32 | 0% |
| I/O Pins | 8 | 256 | 3% |
| Fmax | 12.86 MHz | 12 MHz required | PASS |

*Synthesis numbers from Yosys `synth_ice40` via `make synth-check`.*

## Quick Start

```
# Build
apio build

# Upload
apio upload

# Connect (Linux example)
minicom -D /dev/ttyUSB1 -b 115200
```

On power-up:
```
ENIGMA I READY
```

Type any letter to encipher it. See [doc/QuickStart.md](doc/QuickStart.md) for a full walkthrough including configuration and round-trip encryption/decryption.

## Commands

All configuration is done over the serial interface. Commands start with `:`.

| Command | Example | Effect |
|---------|---------|--------|
| `:R` | `:R312` | Set rotor order (left-mid-right, digits 1-5) |
| `:N` | `:NDOG` | Set ring settings (three letters A-Z) |
| `:P` | `:PCAT` | Set Grundstellung / start positions |
| `:G` | `:G` | Reload positions from Grundstellung |
| `:S` | `:SHX` | Add plugboard pair; max 13 pairs |
| `:S--` | `:S--` | Clear all plugboard pairs |
| `:?` | `:?` | Show current configuration |
| `:F` | `:F` | Factory reset |
| `:UB` | `:UB` | Confirm reflector B |

## Project Structure

```
fpga_enigma/
├── rtl/                  Synthesizable design source
│   ├── enigma_top.v        Top-level module + LED drivers
│   ├── uart_rx.v           UART receiver (115200 8N1)
│   ├── uart_tx.v           UART transmitter + 1-byte queue
│   ├── plugboard.v         Combinational 26:1 MUX substitution
│   ├── enigma_forward.v    Forward cipher path (plugboard -> rotors -> reflector)
│   ├── enigma_backward.v   Inverse cipher path (reflector -> rotors -> plugboard)
│   ├── stepper.v           Rotor stepping with double-step anomaly
│   ├── config_manager.v    Configuration registers + plugboard storage
│   ├── fsm_controller.v    Main FSM: startup, cipher, commands, reset
│   ├── response_generator.v  Command response formatter (OK/ERR/:?)
│   └── enigma_common.vh    Shared helper functions (mod26)
├── tb/                   Regression testbenches (9 total)
│   ├── enigma_tb.v         Comprehensive 7-case cipher test suite
│   ├── error_handling_tb.v Error path coverage (9 cases)
│   ├── rotor_coverage_tb.v Rotors IV/V in left position
│   ├── timeout_tb.v        FSM timeout mechanism
│   ├── plugboard_tb.v      Plugboard command tests
│   ├── uart_tb.v           UART TX/RX unit tests (loopback, framing, all 256 bytes)
│   ├── stepper_tb.v        Stepper unit tests (notches, double-step)
│   ├── plugboard_tb_unit.v Plugboard unit tests (reciprocity, full 13 pairs)
│   ├── config_manager_tb.v Config register unit tests
│   └── dev/                Development/debug testbenches
├── constraints/          Pin constraints
│   └── fpga_enigma.pcf    iCE40-HX8K-CT256 pin assignments
├── doc/                  Documentation
│   ├── fpga_enigma_spec_v2.md  Technical specification
│   └── QuickStart.md           User walkthrough
├── scripts/              Helper scripts
│   ├── verify_pyenigma.sh  Cross-validation against pyenigma oracle
│   └── coverage_summary.sh VCD-based signal toggle coverage report
├── .github/workflows/
│   └── ci.yml            GitHub Actions CI (lint, synth-check, test, coverage)
├── Makefile              Build and test automation
└── apio.ini              Board configuration
```

## Verification

The design is validated against known Enigma test vectors and the [pyenigma](https://pypi.org/project/pyenigma/) Python oracle:

```
# Run all 9 regression testbenches (requires Icarus Verilog)
make test

# Verilator lint check
make lint

# Yosys iCE40 synthesis check (no place-and-route; requires Yosys)
make synth-check

# VCD-based signal toggle coverage report
make coverage

# Cross-validate against pyenigma (requires: pip install pyenigma)
./scripts/verify_pyenigma.sh
```

Test cases include ground settings, Operation Barbarossa historical settings, double-step anomaly, ring offsets, triple-notch turnover, 26-character full cycle, self-reciprocal round-trip, UART protocol tests, and unit-level coverage for the stepper, plugboard, and config manager modules. A GitHub Actions CI pipeline runs lint, synth-check, test, and coverage on every push and PR.

## Toolchain

- [apio](https://github.com/FPGAwars/apio) for build/upload workflow
- [Yosys](https://github.com/YosysHQ/yosys) for synthesis and synthesis checking
- [nextpnr](https://github.com/YosysHQ/nextpnr) for place and route
- [Icarus Verilog](https://github.com/steveicarus/iverilog) for simulation
- [Verilator](https://github.com/verilator/verilator) for linting

## Status & Disclaimer

This project is an experimental exploration of historical cryptography on modern hardware. While the implementation is rigorous and passes a comprehensive suite of tests, it is provided as-is for educational and research purposes. We cannot guarantee its suitability for any specific mission-critical or secure application. Use of this code is at your own discretion and risk—happy hacking!

## License

This project is licensed under the BSD 3-Clause License. See the [LICENSE](LICENSE) file for the full license text.
