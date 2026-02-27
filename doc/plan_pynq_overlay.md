# Pynq Z2 Enigma Overlay — Implementation Plan

## Goal

Add a Pynq Z2 target that exposes the Enigma cipher engine via a web interface.
The FPGA fabric runs the cipher; the Zynq ARM runs a Python/Flask web server
that talks to the hardware through memory-mapped AXI-Lite registers.

Existing iCE40, Arty, and Nexys targets are untouched.

## Architecture

```
Browser  <-->  Flask (ARM/PS)  <-->  AXI-Lite  <-->  Enigma cipher (PL)
```

- **PL:** AXI-Lite slave wrapping config_manager + stepper + forward/backward cipher paths
- **PS:** Zynq block design providing FCLK (12 MHz) + AXI GP master
- **Software:** Python overlay driver + Flask app + single-page HTML UI

## Register Map (AXI-Lite slave, 32-bit aligned)

| Offset | Name       | R/W | Bits                                          |
|--------|------------|-----|-----------------------------------------------|
| 0x00   | CIPHER     | RW  | W: plaintext byte → triggers encrypt. R: ciphertext byte |
| 0x04   | STATUS     | RO  | [0]=busy                                      |
| 0x08   | ROTOR_SEL  | RW  | [8:6]=left [5:3]=mid [2:0]=right (0-4)        |
| 0x0C   | RING_SET   | RW  | [14:10]=left [9:5]=mid [4:0]=right (0-25)     |
| 0x10   | GRUND_SET  | RW  | [14:10]=left [9:5]=mid [4:0]=right (0-25)     |
| 0x14   | PLUG_PAIR  | WO  | [9:5]=letter_a [4:0]=letter_b → adds pair     |
| 0x18   | CONTROL    | WO  | [0]=load_grund [1]=clear_plugs [2]=factory_reset |
| 0x1C   | POSITION   | RO  | [14:10]=left [9:5]=mid [4:0]=right (live)     |

## File Plan

```
rtl/
  enigma_axi_wrapper.v       # NEW — AXI-Lite slave + cipher control FSM
constraints/
  pynq_z2.xdc                # NEW — LEDs (4) + buttons
pynq/
  block_design.tcl            # NEW — Vivado TCL: Zynq PS + AXI + enigma wrapper
  build_pynq.tcl              # NEW — batch build: source block_design, synth, impl, bit
  enigma_overlay.py           # NEW — Python driver class (MMIO register access)
  app.py                      # NEW — Flask web server
  templates/
    index.html                # NEW — single-page UI
Makefile                      # MODIFY — add synth-pynq target
```

## Checklist

### Phase 1: RTL
- [ ] **1.1** Create `rtl/enigma_axi_wrapper.v`
  - AXI-Lite slave (read/write decode for register map above)
  - 4-state cipher mini-FSM (IDLE → STEP → CIPHER_A → CIPHER_B → done)
  - Instantiates: config_manager, stepper, enigma_forward, enigma_backward, plugboard
  - Directly drives: pt_index, mid_letter_reg, step_pulse, load_pulse, cfg_wr_*, cfg_data
  - Busy flag while cipher in progress
- [ ] **1.2** Create `constraints/pynq_z2.xdc`
  - 4 LEDs (LD0-LD3): R14, P14, N16, M14 — map to led_d2..led_d5 (skip heartbeat)
  - BTN0 (D19) as reset — active-high, inverted in wrapper
  - No clock or UART pins (provided by PS block design)
- [ ] **1.3** Verify AXI wrapper passes existing testbench logic
  - Write a minimal simulation testbench that drives the register interface
  - Validate cipher output matches known Enigma test vectors

### Phase 2: Block Design & Build Flow
- [ ] **2.1** Create `pynq/block_design.tcl`
  - Zynq PS: enable FCLK_CLK0 at 12 MHz, one AXI GP master, UART on MIO
  - AXI interconnect → enigma_axi_wrapper slave
  - Wire 4 LEDs and reset button as external ports
- [ ] **2.2** Create `pynq/build_pynq.tcl`
  - Source block_design.tcl, generate wrapper
  - Add RTL sources (core cipher modules + enigma_axi_wrapper)
  - Read pynq_z2.xdc constraints
  - synth_design → opt → place → route → write_bitstream
  - Part: xc7z020clg400-1
- [ ] **2.3** Add Makefile targets
  - `synth-pynq: vivado -mode batch -source pynq/build_pynq.tcl`
  - Update .PHONY and RTL_AMD exclusion list
- [ ] **2.4** Build succeeds — bitstream generated, timing met

### Phase 3: Python Overlay & Web Server
- [ ] **3.1** Create `pynq/enigma_overlay.py`
  - Class `EnigmaOverlay` wrapping PYNQ `Overlay` + `MMIO`
  - Methods: `set_rotors()`, `set_rings()`, `set_positions()`, `add_plug_pair()`,
    `clear_plugboard()`, `factory_reset()`, `encrypt_char()`, `encrypt_string()`,
    `get_position()`, `get_config()`
- [ ] **3.2** Create `pynq/app.py`
  - Flask app with routes: `GET /` (UI), `POST /api/configure`, `POST /api/encrypt`
  - JSON request/response
  - Instantiates EnigmaOverlay on startup
- [ ] **3.3** Create `pynq/templates/index.html`
  - Config section: rotor order, ring settings, start positions, plugboard pairs
  - Text input + Encrypt button
  - Result display
  - Vanilla JS fetch calls to the API
- [ ] **3.4** End-to-end test on Pynq Z2 hardware
  - Load overlay, open browser, configure, encrypt, verify against known vectors
