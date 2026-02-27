# FPGA Enigma — Specification Index

This repository implements the Wehrmacht Enigma I cipher machine targeting the Lattice iCE40-HX8K Breakout Board (ICE40HX8K-B-EVN), with secondary support for AMD/Digilent Arty A7-100T and Nexys A7-100T (Artix-7 XC7A100T). The full specification is split across five documents. Agents should read only the document(s) relevant to their task; the table and quick-reference below identify the right document for each task.

## Spec Documents

| Document | Primary Audience | Key Topics |
|---|---|---|
| `spec_cipher_algorithm.md` | Cipher correctness, algorithm logic | Signal path (ETW→plugboard→rotors→UKW→return), mathematical permutation model, rotor wiring tables (I–V + Reflector B), forward/inverse substitution algorithm, ring settings (Ringstellung) math, double-stepping anomaly explanation, worked cipher examples, key design rules |
| `spec_rtl_modules.md` | RTL/Verilog developers | Module hierarchy and ASCII block diagram, full port definitions for all 8 modules (`enigma_top`, `uart_rx`, `uart_tx`, `enigma_forward`, `enigma_backward`, `stepper`, `plugboard`, `fsm_controller`, `response_generator`, `config_manager`), FSM state machine (~285 lines), LC/resource budget, LUT vs BRAM strategy, AMD Artix-7 MMCM clock adaptation, AMD pin assignments and build commands |
| `spec_uart_protocol.md` | Host/FPGA interface implementors | UART parameters (115200 8N1), data-vs-command byte distinction, full 54-command reference table, command descriptions with argument encoding, response format, complete example configuration session, FSM implementation notes, ASCII-to-index conversion, input byte behavior table, output encoding rules, TX buffer overflow behavior |
| `spec_reset_init.md` | Reset/startup behavior | Power-on FPGA configuration sequence, GSR (Global Set/Reset) behavior, startup banner transmission spec, Grundstellung reset (`:G` command) sequence, factory reset (`:F` command) sequence, hardware reset mechanisms, reset FSM state transitions, LED heartbeat and diagnostic behavior, Verilog coding guidelines for reset logic |
| `spec_verification.md` | Verification, CI, physical implementation | Combinational timing analysis and 2-cycle pipeline strategy, three official test vectors (ground settings, Barbarossa historical message, double-step anomaly), testbench architecture (~260 lines), resource constraints (7680 LCs, 32 BRAMs), open-source toolchain commands (Yosys/nextpnr/iceprog), iCE40-HX8K pin assignment table, `.pcf` constraints file, project license |

## Task → Document Quick Reference

| Task | Read |
|---|---|
| Debugging incorrect cipher output | `spec_cipher_algorithm.md` |
| Understanding rotor wiring or reflector mapping | `spec_cipher_algorithm.md` |
| Understanding the double-stepping anomaly | `spec_cipher_algorithm.md` |
| Working on rotor substitution or ring setting math | `spec_cipher_algorithm.md` |
| Writing or modifying a Verilog module | `spec_rtl_modules.md` |
| Understanding module ports or the module hierarchy | `spec_rtl_modules.md` |
| Working on the FSM controller | `spec_rtl_modules.md` |
| Adding or adapting AMD Artix-7 support | `spec_rtl_modules.md` |
| Implementing or testing UART commands | `spec_uart_protocol.md` |
| Writing a host-side configuration script | `spec_uart_protocol.md` |
| Working on reset or startup behavior | `spec_reset_init.md` |
| Working on the startup banner or LED diagnostics | `spec_reset_init.md` |
| Writing a testbench or checking expected cipher output | `spec_verification.md` |
| Setting up the toolchain or programming the board | `spec_verification.md` |
| Checking iCE40-HX8K pin assignments | `spec_verification.md` |
| Checking timing / combinational path depth | `spec_verification.md` |

## Scope Notes

- Reflector B (UKW-B) only; Reflector C (UKW-C) is excluded from this implementation.
- Five standard Wehrmacht rotors (I–V) supported; any three are selected for left, middle, and right positions.
- UART interface: 115200 baud, 8N1, via FTDI FT2232HL USB-to-serial bridge.
- Primary target: Lattice iCE40-HX8K Breakout Board (ICE40HX8K-B-EVN).
- Secondary targets: AMD/Digilent Arty A7-100T and Nexys A7-100T (Artix-7 XC7A100T) — supported via thin MMCM wrapper modules.
