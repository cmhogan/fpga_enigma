<!--
  spec_rtl_modules.md — Part 2 of 5
  Audience: RTL implementation agents and developers writing or modifying Verilog
  modules. Contains the complete module tree, port definitions, FSM state machine,
  hardware resource budgets, and AMD Artix-7 adaptation details.

  Sibling documents (do NOT duplicate their content here):
    spec_cipher_algorithm.md  — Cipher math, wiring tables, substitution algorithm
    spec_uart_protocol.md     — UART protocol, command reference, character I/O
    spec_reset_init.md        — Reset mechanisms, power-on sequencing, LED diagnostics
    spec_verification.md      — Timing analysis, test vectors, toolchain, pin assignments
    spec_index.md             — Navigator: one-line description of each spec document
-->

## Hardware Implementation Strategy

The Lattice iCE40-HX8K is an FPGA with 7,680 logic cells and 32 4-kilobit Block RAM (BRAM) units. An optimized Enigma implementation must prioritize low logic utilization to leave overhead for the UART controller and configuration logic.

### Resource Optimization: LUTs vs. Block RAM

The decision between using Logic Cells (LUTs) or BRAMs for rotor storage depends on the desired throughput and the complexity of the state machine.

- **Distributed RAM (LUT-based):** Implementing the 26-entry substitution tables as combinational logic using case statements or 26x5-bit distributed RAM arrays allows for asynchronous, single-cycle lookups. Each rotor's forward and inverse tables would consume roughly 40-60 LCs. With 3 rotors and a reflector, the total logic consumption for the scrambler unit would be approximately 400 LCs.
- **Block RAM (BRAM):** Each iCE40 BRAM can store 4,096 bits. A single BRAM could store all five standard rotors plus the reflector and their inverses. However, BRAMs are synchronous and require at least one clock cycle for a read operation. This would necessitate a sequential state machine that takes at least 7-10 cycles to "bounce" the signal through the components and back.

For the iCE40-HX8K Breakout Board, the LUT-based approach is superior. It allows the entire permutation path (ETW $\to$ Plugboard $\to$ Rotors $\to$ UKW $\to$ Rotors $\to$ Plugboard) to be implemented as a single combinational block. This results in an extremely fast "cipher" operation that completes in a single clock cycle of the 12MHz master clock, simplifying the overall Finite State Machine.

### Finite State Machine (FSM) Architecture

The hardware controller must orchestrate the interface between the UART serial stream and the cryptographic core. A **14-state FSM** governs the complete system lifecycle, from power-on startup through both cipher and configuration command paths. The core cipher path uses six of these states:

- **IDLE:** The FSM polls the UART receiver. When a "Data Ready" signal is asserted (indicating an ASCII character has arrived), the FSM captures the 8-bit value. An alphabetic character transitions to the STEP state. A `:` prefix character transitions to the CMD_OPCODE state to await the opcode byte.
- **STEP:** The FSM asserts `step_pulse` to advance rotor positions via the `stepper` module.
- **STEP_WAIT:** A single-cycle wait state that allows the `stepper` module's registered position outputs to settle before the cipher path reads them.
- **CIPHER_A:** The first pipeline stage. The updated rotor positions and plaintext index are driven into `enigma_forward` (plugboard → right → middle → left rotors → reflector). The 5-bit intermediate result (`mid_letter`) is latched into `mid_letter_reg` at the end of this cycle.
- **CIPHER_B:** The second pipeline stage. `mid_letter_reg` is driven into `enigma_backward` (left → middle → right rotors → plugboard). The 5-bit ciphertext result is latched into a register.
- **TRANSMIT:** The FSM passes the ciphertext to the UART transmitter. It waits for the "Transmit Complete" signal before returning to the IDLE state to process the next character.

The remaining eight states handle startup sequencing, command parsing (including the CMD_OPCODE state), and reset operations. The complete 14-state table with encodings and transition rules is the authoritative definition in **Section 7 (`fsm_controller`)** of the Module Hierarchy.

### UART Interface and Parameters

The iCE40-HX8K Breakout Board utilizes an onboard 12MHz oscillator. The UART module must be configured to communicate with a PC terminal at 115,200 baud.

| Parameter | Value | Logic / Implementation |
| --- | --- | --- |
| Baud Rate | 115,200 bps | Derived from 12MHz / 104 clock cycles per bit. |
| Data Bits | 8 | Standard ASCII character encoding. |
| Parity | None | No parity bit is used in the standard 115200-8-N-1 config. |
| Stop Bits | 1 | Single stop bit to signal frame end. |
| RX Sampling | Midpoint | Detect start-bit edge; count 52 clocks to bit center; sample every 104 clocks (±0.16% baud error). |

Table 2: UART Interface Parameters for the iCE40-HX8K Breakout Board Implementation.

#### UART Receiver Sampling Detail

### Why 16x Oversampling Is Not Applicable Here

At 115,200 baud on a 12 MHz clock:

```
Clocks per bit = 12,000,000 / 115,200 = 104.17 (non-integer)
```

True 16x oversampling would require a sample clock of:

```
104.17 / 16 = 6.51 clocks per sample  ← not an integer; cannot be implemented exactly
```

16x oversampling is not achievable at this clock/baud combination without a fractional clock divider. The correct approach is **midpoint sampling**.

---

### Baud Rate Error with Integer Divisor

Using the nearest integer divisor of **104 clocks per bit**:

| Parameter | Value |
|-----------|-------|
| Nominal baud rate | 115,200 baud |
| Actual baud rate (÷104) | 12,000,000 / 104 = **115,384.6 baud** |
| Absolute error | 115,384.6 − 115,200 = 184.6 baud |
| Relative error | (184.6 / 115,200) × 100% = **+0.16%** |
| UART tolerance | ±2–3% |

0.16% is well within the standard UART tolerance. A divisor of 104 is used throughout this specification.

---

### Recommended Approach: Midpoint Sampling

The RX logic detects the falling edge of the start bit, waits approximately half a bit period to land at the **midpoint** of each bit cell, then samples once per bit period. Sampling at the midpoint maximises the margin against edge jitter and inter-symbol interference.

#### Step-by-step Algorithm

1. **Idle state** — monitor `rx_sync2` for a HIGH→LOW transition (start-bit falling edge).
2. **Start-bit midpoint** — count **52 clocks** after the falling edge, then sample `rx_sync2`.  
   - If still LOW → valid start bit; proceed.  
   - If HIGH → glitch/noise; abort and return to idle.
3. **Data bits 0–7** — wait **104 clocks** from the previous sample point; sample `rx_sync2`; repeat for all 8 bits (LSB first, standard UART).
4. **Stop bit** — wait **104 clocks** from bit 7 sample; sample `rx_sync2`.  
   - Verify HIGH. If LOW → framing error.
5. **Return to idle** and assert `rx_valid` with the assembled byte.

#### Timing Table (one complete byte frame)

| Bit | Sample offset from falling edge (clocks) | Expected level |
|-----|------------------------------------------|----------------|
| Start bit (verify) | 52 | LOW |
| Bit 0 (LSB) | 52 + 104 = 156 | data |
| Bit 1 | 52 + 208 = 260 | data |
| Bit 2 | 52 + 312 = 364 | data |
| Bit 3 | 52 + 416 = 468 | data |
| Bit 4 | 52 + 520 = 572 | data |
| Bit 5 | 52 + 624 = 676 | data |
| Bit 6 | 52 + 728 = 780 | data |
| Bit 7 (MSB) | 52 + 832 = 884 | data |
| Stop bit | 52 + 936 = 988 | HIGH |

**Total frame duration:** 10 × 104 = **1,040 clocks** per byte  
**Frame time at 12 MHz:** 1,040 / 12,000,000 ≈ **86.7 µs**

---

### Alternative: 8x Oversampling

For designs that prefer an explicit oversampling counter, an 8x scheme divides more cleanly:

```
Sample period = 12,000,000 / 923,077 ≈ 13 clocks  (exact: 12 MHz / 13 = 923,076.9 Hz)
Oversampling ratio per bit = 104.17 / 13 ≈ 8x
```

The RX logic runs a free-running 13-clock sample counter, majority-votes three samples around the expected bit centre, and advances a bit counter. This is slightly more complex than midpoint sampling and introduces a small additional quantisation error (~half a sample period = ±6.5 clocks vs. ±1 clock for midpoint). It is listed here for completeness but is **not** the primary specification.

---

### Metastability Synchronizer (Required)

The raw `uart_rx_pin` signal is asynchronous to the FPGA fabric clock. A **2-flip-flop synchronizer** must be the first logic to touch the pin, placed with timing constraints that minimise the probability of a metastable output propagating downstream.

```verilog
// 2-FF metastability synchronizer — place both FFs in the same logic tile
// as close as possible to the IOB (use ALOC / placement constraints).
reg rx_sync1 = 1'b1, rx_sync2 = 1'b1;

always @(posedge clk) begin
    rx_sync1 <= uart_rx_pin;   // first stage: may be metastable
    rx_sync2 <= rx_sync1;      // second stage: resolved before use
end
```

- `uart_rx_pin` — direct connection from the iCE40-HX8K Breakout Board FTDI UART RX pin.
- `rx_sync1` — first-stage register; **never** used by any combinational logic.
- `rx_sync2` — stable, synchronised signal used by **all** downstream RX logic (edge detection, bit counter, shift register).

Initialize both registers to `1'b1` (UART idle = HIGH) so no spurious start-bit edge is generated on power-up.

---

## Module Hierarchy and Port Definitions

---

### ASCII Connectivity Diagram

```
                          iCE40-HX8K Breakout Board (12 MHz, iCE40-HX8K)
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │                              enigma_top                                      │
 │                                                                              │
 │   UART RX pin ──► uart_rx ──► fsm_controller ──► uart_tx ──► UART TX pin    │
 │                       │       ┌─────────────────┐    ▲                       │
 │                       │       │ ┌─────────────┐ │    │                       │
 │                       │       │ │  response_  │ │    │                       │
 │                       │       │ │  generator  ├─┼──► TX mux ──► tx_byte/    │
 │                       │       │ │(OK/ERR/:?)  │ │    ▲          tx_start    │
 │                       │       │ └──────┬──────┘ │    │                       │
 │                       │       │   cfg_status,   │    │                       │
 │                       │       │   pos, plug_map │    │                       │
 │                       │       └────────┬────────┘    │                       │
 │                       │    (rx_byte,   │  ▲          │                       │
 │                       │    rx_valid)   │  │(tx_busy)  │                       │
 │                       │               ▼  │           │                       │
 │                       │       config_manager          │                       │
 │                       │       (rotor_sel, rings,      │                       │
 │                       │        grundstellung,         │                       │
 │                       │        plugboard pairs)       │                       │
 │                       │             │                 │                       │
 │                       │    cfg bus  │  pos bus        │                       │
 │                       │             ▼                 │                       │
 │                       │         stepper ◄──── STEP pulse (from fsm)          │
 │                       │         (current_pos ──► next_pos)                   │
 │                       │             │                 │                       │
 │                       │     pos[2:0]│  cfg[rotor_sel, │                       │
 │                       │             │   rings,plug]   │                       │
 │                       │             ▼                 │                       │
 │                       │       enigma_forward (comb.)  │                       │
 │                       │       plug ──► rR ──► rM ──► │                       │
 │                       │       rL ──► reflector        │                       │
 │                       │             │                 │                       │
 │                       │     mid_letter (5-bit reg in FSM)                    │
 │                       │             │                 │                       │
 │                       │       enigma_backward (comb.) │                       │
 │                       │       rL ──► rM ──► rR ──►   │                       │
 │                       │       plug ──► ct_index       │                       │
 │                       │             │                 │                       │
 │                       └─────────────────────────────► fsm_controller         │
 └──────────────────────────────────────────────────────────────────────────────┘

  enigma_forward:                          enigma_backward:
  ┌────────────────────────────────┐       ┌────────────────────────────────┐
  │  pt_index ──► plugboard_fwd   │       │  mid_letter ──► rL_inv        │
  │  ──► rR_fwd ──► rM_fwd       │       │  ──► rM_inv ──► rR_inv       │
  │  ──► rL_fwd ──► reflector    │       │  ──► plugboard_bwd           │
  │  ──► mid_letter_out          │       │  ──► ct_index                │
  └────────────────────────────────┘       └────────────────────────────────┘
```

---

### 1. `enigma_top`

**Purpose:** Top-level structural wrapper that instantiates all sub-modules and connects board I/O pins to the internal design.

**Parameters:**
- `CLK_FREQ = 12_000_000` — System clock frequency in Hz
- `BAUD_RATE = 115_200` — UART baud rate
- `CMD_TIMEOUT = 0` — Command timeout override (0 = use CLK_FREQ * 3)

**Derived localparams:**
- `BAUD_DIV_VAL = CLK_FREQ / BAUD_RATE - 1` — passed to `uart_rx` and `uart_tx`
- `HALF_BIT_VAL = (CLK_FREQ / BAUD_RATE) / 2 - 1` — passed to `uart_rx`
- `TIMEOUT_LIMIT_VAL = (CMD_TIMEOUT != 0) ? CMD_TIMEOUT : CLK_FREQ * 3` — passed to `fsm_controller`
- `HEARTBEAT_MAX_VAL = CLK_FREQ / 2 - 1` — used for LED D1 heartbeat counter

| Port Name  | Direction | Width | Description                                      |
|------------|-----------|-------|--------------------------------------------------|
| `clk`      | input     | 1     | 12 MHz board clock (iCE40-HX8K Breakout Board CLK pin)            |
| `ext_rst_n`| input     | 1     | Active-low external reset. Directly synchronised and ANDed with POR counter output. Tie to `1'b1` if unused. |
| `uart_rx`  | input     | 1     | UART receive pin from USB-UART bridge            |
| `uart_tx`  | output    | 1     | UART transmit pin to USB-UART bridge             |
| `led_d1`   | output    | 1     | Heartbeat (~1 Hz toggle)                         |
| `led_d2`   | output    | 1     | RX activity (~100 ms monostable pulse)           |
| `led_d3`   | output    | 1     | TX activity (~100 ms monostable pulse)           |
| `led_d4`   | output    | 1     | Command mode indicator (HIGH during command processing) |
| `led_d5`   | output    | 1     | Error indicator (~200 ms monostable pulse)       |

**Internal notes:**
- Structural instantiation and port mapping, plus LED driver logic (counters and monostable timers).
- **Power-on reset (POR) generator:** A 10-bit counter holds `rst_n` deasserted for 1024 clock cycles (~85 µs at 12 MHz) after GSR deassertion. The counter increments from 0 to 1023, then sets `por_done = 1'b1`.
- **External reset synchronizer:** A 2-FF synchronizer chain (`ext_rst_sync1`, `ext_rst_sync2`) provides metastability protection for the `ext_rst_n` input.
- **Derived reset:** All sub-modules receive `rst_n = por_done & ext_rst_sync2`. This ensures a clean power-on sequence and allows optional external reset via the `ext_rst_n` pin.
- LED counters reside here (not in sub-modules): D1 heartbeat (23-bit counter using parameterized `HEARTBEAT_MAX_VAL`, ~23 LCs), D2 RX activity monostable (21-bit, ~100 ms pulse, ~21 LCs), D3 TX activity monostable (21-bit, ~100 ms pulse, ~21 LCs), D5 error monostable (22-bit, ~200 ms pulse, ~22 LCs), D4 mode indicator (combinational from `fsm_controller.cmd_mode`, ~1 LC). See the LED Function Definitions section for timing details.

**Estimated LC usage:** ~103 LCs (5 wiring/buffers + ~88 LED counters/monostables + ~10 POR counter and reset synchronizer)

---

### 2. `uart_rx`

**Purpose:** Deserialises an incoming UART byte at 115200 baud using a 2-FF metastability synchroniser and midpoint (centre) sampling.

| Port Name     | Direction | Width | Description                                                  |
|---------------|-----------|-------|--------------------------------------------------------------|
| `clk`         | input     | 1     | System clock (12 MHz)                                        |
| `rst_n`       | input     | 1     | Active-low synchronous reset                                 |
| `rxd`         | input     | 1     | Raw UART RX line from pin                                    |
| `rx_byte`     | output    | 8     | Received data byte (valid when `rx_valid` pulses)            |
| `rx_valid`    | output    | 1     | Single-cycle pulse: byte in `rx_byte` is ready              |
| `rx_error`    | output    | 1     | Framing error: stop bit not detected (held until next start) |
| `rx_active`   | output    | 1     | High while a byte is being received                          |

**Internal registers / state:**
- `parameter BAUD_DIV = 103` — clock-divider constant for 115200 baud at 12 MHz ((12,000,000 / 115,200) − 1 = 103). Passed in from `enigma_top` and overrides the module default.
- `parameter HALF_BIT = 51` — half-bit delay for midpoint sampling ((BAUD_DIV + 1) / 2 − 1 = 51). Passed in from `enigma_top` and overrides the module default.
- `sync_ff[1:0]` — 2-FF synchroniser for `rxd` input.
- `baud_cnt[11:0]` — baud rate counter; reloaded from `BAUD_DIV`.
- `bit_cnt[3:0]` — counts 0..9 (start + 8 data + stop).
- `shift_reg[7:0]` — shift register; MSB shifts in on each sample point.
- State machine: IDLE → START_WAIT (half-bit delay) → RECEIVE (8 bits) → STOP.
- Sampling occurs when `baud_cnt` reaches zero (midpoint of each bit period).

**Estimated LC usage:** ~45 LCs

---

### 3. `uart_tx`

**Purpose:** Serialises an 8-bit byte onto the UART TX line at 115200 baud with one start bit, eight data bits, and one stop bit (8N1). Includes a 1-byte output queue so the FSM can hand off a second byte immediately while the first is still being shifted out.

| Port Name   | Direction | Width | Description                                                                     |
|-------------|-----------|-------|---------------------------------------------------------------------------------|
| `clk`       | input     | 1     | System clock (12 MHz)                                                           |
| `rst_n`     | input     | 1     | Active-low synchronous reset                                                    |
| `tx_byte`   | input     | 8     | Data byte to transmit                                                           |
| `tx_start`  | input     | 1     | Single-cycle pulse: load `tx_byte` into the queue and begin/continue transmit  |
| `txd`       | output    | 1     | UART TX line (idle high)                                                        |
| `tx_busy`   | output    | 1     | High while the shift register **or** the 1-byte queue holds data; gate new `tx_start` pulses on this signal |

**Internal registers / state:**
- `parameter BAUD_DIV = 103` — clock-divider constant for 115200 baud at 12 MHz. Passed in from `enigma_top` and overrides the module default.
- `baud_cnt[11:0]` — baud rate counter; reloaded from `BAUD_DIV`.
- `bit_cnt[3:0]` — counts 0..9 (start + 8 data + stop).
- `shift_reg[9:0]` — {stop=1, data[7:0], start=0} loaded from the queue when transmission begins.
- `queue_byte[7:0]` — 1-byte holding register for the next byte to transmit.
- `queue_valid` — set when `queue_byte` holds an unread byte; cleared when the byte is moved into `shift_reg`.
- State machine: IDLE → TRANSMIT (shifts LSB-first) → back to IDLE (or immediately begin next byte if `queue_valid`).
- `txd` is driven from `shift_reg[0]` during TRANSMIT, held 1 in IDLE.
- **Queue overflow policy:** If `tx_start` is asserted while both `shift_reg` is active **and** `queue_valid` is set, the new byte is **silently dropped**. At 115200 baud each byte takes ~87 µs; back-to-back overflow is extremely rare during normal cipher operation.

**Estimated LC usage:** ~45 LCs (queue register and valid flag add ~5 LCs over the shift-register-only baseline)

---

### 4a. `enigma_forward`

**Purpose:** Purely combinational forward half of the cipher path: plugboard → three rotors forward → reflector. Produces the 5-bit intermediate letter that the FSM registers between CIPHER_A and CIPHER_B.

| Port Name          | Direction | Width | Description                                                            |
|--------------------|-----------|-------|------------------------------------------------------------------------|
| `pt_index`         | input     | 5     | Plaintext letter index 0..25 (A=0 … Z=25)                            |
| `rotor_sel_l`      | input     | 3     | Left rotor selection (0=I, 1=II, 2=III, 3=IV, 4=V)                   |
| `rotor_sel_m`      | input     | 3     | Middle rotor selection                                                 |
| `rotor_sel_r`      | input     | 3     | Right rotor selection                                                  |
| `ring_l`           | input     | 5     | Left rotor ring setting (Ringstellung) 0..25                          |
| `ring_m`           | input     | 5     | Middle rotor ring setting                                              |
| `ring_r`           | input     | 5     | Right rotor ring setting                                               |
| `pos_l`            | input     | 5     | Left rotor current position 0..25                                      |
| `pos_m`            | input     | 5     | Middle rotor current position                                          |
| `pos_r`            | input     | 5     | Right rotor current position                                           |
| `plug_map[129:0]`  | input     | 5×26  | Plugboard wiring: `plug_map[i*5 +: 5]` = letter that index i maps to |
| `mid_letter`       | output    | 5     | Reflector output (intermediate result). FSM latches this at end of CIPHER_A. |

**Internal notes:**
- All computation is pure combinational logic — no registers, no mode select.
- Signal flow: `pt_index` → plugboard lookup → right rotor forward → middle rotor forward → left rotor forward → reflector lookup → `mid_letter`.
- The `mod26` helper function (used for positional offset arithmetic) is defined in the shared include file `rtl/enigma_common.vh` and included via `` `include "enigma_common.vh" `` inside the module. This eliminates duplication with `enigma_backward`.
- Each rotor substitution uses a MUX tree selected by `rotor_sel_*`. The five forward rotor wirings (I–V) and UKW-B are stored as `localparam` arrays.
- The positional offset and ring correction formula applied per rotor:
  `entry = (signal_in + pos - ring + 26) % 26`, look up forward wiring, `out = (wiring_out - pos + ring + 26) % 26`.
- The reflector is fixed to UKW-B (hardwired `localparam`), no offset arithmetic.
- Instantiates one `plugboard` module for the input-side swap.
- Path depth: plug (3 LUT levels) + 3× rotor forward (11 each) + reflector (3) = **39 LUT levels**.

**Estimated LC usage:** ~120 LCs

---

### 4b. `enigma_backward`

**Purpose:** Purely combinational backward half of the cipher path: three rotors inverse → plugboard. Takes the registered midpoint letter from the FSM and produces the final ciphertext index.

| Port Name          | Direction | Width | Description                                                            |
|--------------------|-----------|-------|------------------------------------------------------------------------|
| `mid_letter`       | input     | 5     | Reflector output (from FSM register, latched at end of CIPHER_A)      |
| `rotor_sel_l`      | input     | 3     | Left rotor selection (0=I, 1=II, 2=III, 3=IV, 4=V)                   |
| `rotor_sel_m`      | input     | 3     | Middle rotor selection                                                 |
| `rotor_sel_r`      | input     | 3     | Right rotor selection                                                  |
| `ring_l`           | input     | 5     | Left rotor ring setting (Ringstellung) 0..25                          |
| `ring_m`           | input     | 5     | Middle rotor ring setting                                              |
| `ring_r`           | input     | 5     | Right rotor ring setting                                               |
| `pos_l`            | input     | 5     | Left rotor current position 0..25                                      |
| `pos_m`            | input     | 5     | Middle rotor current position                                          |
| `pos_r`            | input     | 5     | Right rotor current position                                           |
| `plug_map[129:0]`  | input     | 5×26  | Plugboard wiring: `plug_map[i*5 +: 5]` = letter that index i maps to |
| `ct_index`         | output    | 5     | Ciphertext letter index 0..25. Valid at end of CIPHER_B.              |

**Internal notes:**
- All computation is pure combinational logic — no registers, no mode select.
- Signal flow: `mid_letter` → left rotor inverse → middle rotor inverse → right rotor inverse → plugboard lookup → `ct_index`.
- The `mod26` helper function is included from the shared `rtl/enigma_common.vh` file via `` `include "enigma_common.vh" ``, shared with `enigma_forward`.
- Each rotor substitution uses a MUX tree selected by `rotor_sel_*`. The five inverse rotor wirings are stored as `localparam` arrays.
- The positional offset formula is identical to the forward pass; only the lookup table differs (inverse wiring ROM).
- Instantiates one `plugboard` module for the output-side swap.
- Path depth: 3× rotor inverse (11 each) + plug (3) = **36 LUT levels**.

**FSM pipeline usage:**
```
CIPHER_A:  FSM drives pt_index into enigma_forward.
           At clock edge: FSM register latches mid_letter output.

CIPHER_B:  FSM drives registered mid_letter into enigma_backward.
           At clock edge: FSM register latches ct_index output.
```

**Estimated LC usage:** ~100 LCs

> **Combined cipher path total:** ~220 LCs (120 + 100), unchanged from the previous single-module estimate. The split eliminates the `pipe_mode` mux and simplifies both modules at no area cost.

---

### 5. `stepper`

**Purpose:** Clocked module that computes and registers the next rotor positions after each STEP pulse, correctly implementing the double-stepping anomaly of the middle rotor.

| Port Name     | Direction | Width | Description                                                                         |
|---------------|-----------|-------|-------------------------------------------------------------------------------------|
| `clk`         | input     | 1     | System clock                                                                        |
| `rst_n`       | input     | 1     | Active-low synchronous reset                                                        |
| `step_pulse`  | input     | 1     | Single-cycle pulse from FSM (asserted during STEP state) to advance positions       |
| `load_pulse`  | input     | 1     | Single-cycle pulse from FSM to load `grundstellung` into current positions (`:G`)   |
| `rotor_sel_m` | input     | 3     | Middle rotor selection (determines notch position for turnover)                     |
| `rotor_sel_r` | input     | 3     | Right rotor selection (determines notch position for turnover)                      |
| `grundstellung_l` | input | 5     | Loaded into `pos_l` on `load_pulse`                                                |
| `grundstellung_m` | input | 5     | Loaded into `pos_m` on `load_pulse`                                                |
| `grundstellung_r` | input | 5     | Loaded into `pos_r` on `load_pulse`                                                |
| `pos_l`       | output    | 5     | Current left rotor position (registered)                                            |
| `pos_m`       | output    | 5     | Current middle rotor position (registered)                                          |
| `pos_r`       | output    | 5     | Current right rotor position (registered)                                           |

**Internal registers / state:**
- `pos_l_r[4:0]`, `pos_m_r[4:0]`, `pos_r_r[4:0]` — registered position outputs.
- `notch_r[4:0]`, `notch_m[4:0]` — combinationally decoded from `rotor_sel_r` / `rotor_sel_m` using a `localparam` table of the five rotor notch positions (I=Q/16, II=E/4, III=V/21, IV=J/9, V=Z/25).
- Stepping rules (evaluated combinationally, applied on `step_pulse`; see **Section 5.4** for the authoritative pseudocode and ordering constraints):
  1. `step_r` = 1 always (right rotor steps every keypress).
  2. `step_m` = 1 if `pos_r_r == notch_r` OR `pos_m_r == notch_m` (double-step).
  3. `step_l` = 1 if `pos_m_r == notch_m`.
- Modular increment: `(pos + 1) % 26` implemented as: `pos == 25 ? 0 : pos + 1`.

**Estimated LC usage:** ~55 LCs

---

### 6. `plugboard`

**Purpose:** Implements a 26-entry configurable reciprocal substitution table (Steckerbrett) as a combinational lookup.

| Port Name       | Direction | Width | Description                                                           |
|-----------------|-----------|-------|-----------------------------------------------------------------------|
| `letter_in`     | input     | 5     | Input letter index 0..25                                              |
| `plug_map[129:0]`| input     | 5×26  | Flat wiring map; `plug_map[i*5 +: 5]` = output index for input i     |
| `letter_out`    | output    | 5     | Substituted output letter index 0..25                                 |

**Internal notes:**
- Pure combinational 26:1 MUX selecting from the `plug_map` array.
- No identity-pair storage here; unpaired letters must be initialised as self-mapping by `config_manager`.
- One instance is used inside `enigma_forward` (pre-rotor) and one inside `enigma_backward` (post-rotor); both share the same `plug_map` bus because the plugboard is reciprocal.
- The 130-bit `plug_map` bus is driven from `config_manager`.

**Estimated LC usage:** ~30 LCs (per instance; 2 instances = ~60 LCs, shared bus so counted once)

---

### 7. `fsm_controller`

**Purpose:** Orchestrates the full encode/command cycle — receives bytes from `uart_rx`, classifies them as commands or plaintext, drives the STEP and CIPHER pipeline states, parses multi-character commands, and sends responses via `uart_tx`. Instantiates a `response_generator` sub-module internally for OK/ERR/`:?` response emission.

**Parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TIMEOUT_LIMIT` | 36000000 | Command timeout counter limit (3 seconds at 12 MHz; overridable via CMD_TIMEOUT parameter in enigma_top) |

| Port Name           | Direction | Width | Description                                                              |
|---------------------|-----------|-------|--------------------------------------------------------------------------|
| `clk`               | input     | 1     | System clock                                                             |
| `rst_n`             | input     | 1     | Active-low synchronous reset                                             |
| `rx_byte`           | input     | 8     | Incoming byte from `uart_rx`                                             |
| `rx_valid`          | input     | 1     | Pulse: `rx_byte` is valid                                                |
| `tx_busy`           | input     | 1     | `uart_tx` is busy; cannot accept new byte                               |
| `mid_letter_fwd`    | input     | 5     | Reflector output from `enigma_forward` (latched by FSM at end of CIPHER_A) |
| `ct_index`          | input     | 5     | Ciphertext index from `enigma_backward`                                  |
| `tx_byte`           | output    | 8     | Byte to send via `uart_tx` (wire; driven by TX output mux, see `response_generator` below) |
| `tx_start`          | output    | 1     | Pulse: begin transmitting `tx_byte` (wire; driven by TX output mux)      |
| `pt_index`          | output    | 5     | Plaintext index driven into `enigma_forward`                             |
| `mid_letter_reg`    | output    | 5     | Registered midpoint letter driven into `enigma_backward` (latched from `mid_letter_fwd` at end of CIPHER_A) |
| `step_pulse`        | output    | 1     | Pulse to `stepper`: advance rotor positions                              |
| `load_pulse`        | output    | 1     | Pulse to `stepper`: load Grundstellung into positions                    |
| `cfg_wr_rotor`      | output    | 1     | Write-enable to `config_manager` for rotor order                         |
| `cfg_wr_ring`       | output    | 1     | Write-enable to `config_manager` for ring settings                       |
| `cfg_wr_grund`      | output    | 1     | Write-enable to `config_manager` for Grundstellung                       |
| `cfg_wr_plug_add`   | output    | 1     | Write-enable to `config_manager` to add plugboard pair                   |
| `cfg_wr_plug_clr`   | output    | 1     | Write-enable to `config_manager` to clear all plugboard pairs            |
| `cfg_wr_factory`    | output    | 1     | Write-enable to `config_manager` for factory reset                       |
| `cfg_data[15:0]`    | output    | 16    | Generic data bus to `config_manager` (command payload, packed)           |
| `cfg_status[63:0]`  | input     | 64    | Packed status word from `config_manager` for `:?` query response; bit layout defined in `config_manager` section |
| `pos_l[4:0]`        | input     | 5     | Current left rotor live position from `stepper` (for `:?` POS line)     |
| `pos_m[4:0]`        | input     | 5     | Current middle rotor live position from `stepper`                        |
| `pos_r[4:0]`        | input     | 5     | Current right rotor live position from `stepper`                         |
| `plug_map[129:0]`   | input     | 5×26  | Plugboard wiring map from `config_manager` (used for `:S` validation and passed to `response_generator`) |
| `plug_pair_cnt[4:0]`| input     | 5     | Current plugboard pair count from `config_manager` (for `:S` validation) |
| `error_led`         | output    | 1     | Asserted on unrecognised command or out-of-range value                   |
| `cmd_mode`          | output    | 1     | HIGH during command processing (CMD_OPCODE, CMD_ARG, CMD_EXEC, CMD_RESP) |

**Internal registers / state:**

FSM state register `state[3:0]` (unified; one FSM governs startup, cipher, command, and reset paths). The 14 states and their 4-bit encodings are:

| State                | Encoding   |
|----------------------|------------|
| `STARTUP_DELAY`      | `4'b0000`  |
| `STARTUP`            | `4'b0001`  |
| `IDLE`               | `4'b0010`  |
| `STEP`               | `4'b0011`  |
| `CIPHER_A`           | `4'b0100`  |
| `TRANSMIT`           | `4'b0101`  |
| `CMD_ARG`            | `4'b0110`  |
| `CMD_EXEC`           | `4'b0111`  |
| `CMD_RESP`           | `4'b1000`  |
| `RESET_GRUNDSTELLUNG`| `4'b1001`  |
| `FACTORY_RESET`      | `4'b1010`  |
| `CIPHER_B`           | `4'b1011`  |
| `CMD_OPCODE`         | `4'b1100`  |
| `STEP_WAIT`          | `4'b1101`  |

Other internal registers:

- `cmd_opcode[7:0]` — latched first byte after `:` (R, N, P, S, G, F, ?, U).
- `arg_buf[15:0]` — shift register for command argument bytes (converted indices, not raw ASCII).
- `mid_letter_reg[4:0]` — registered capture of `enigma_forward.mid_letter` at end of CIPHER_A state; driven into `enigma_backward.mid_letter`.
- `ct_latch[4:0]` — registered capture of `enigma_backward.ct_index` at end of CIPHER_B state.
- `resp_ok` — latched OK/ERR flag for response_generator.
- `is_query` — latched `:?` query flag for response_generator.
- `resp_start` — single-cycle pulse to start response_generator.
- `resp_done` (wire) — single-cycle pulse from response_generator indicating response complete.
- `fsm_tx_byte[7:0]`, `fsm_tx_start` — FSM's own TX signals; muxed with response_generator's outputs to produce the module-level `tx_byte`/`tx_start` (see TX mux below).

**TX output mux:** The module-level `tx_byte` and `tx_start` ports are wires (not registers), driven by:
```
assign tx_start = fsm_tx_start | resp_tx_start;
assign tx_byte  = resp_tx_start ? resp_tx_byte : fsm_tx_byte;
```
The FSM drives `fsm_tx_byte`/`fsm_tx_start` for banner and cipher output; the `response_generator` sub-module drives `resp_tx_byte`/`resp_tx_start` for OK/ERR/`:?` responses. Since the FSM is in CMD_RESP (idle with respect to TX) whenever the response_generator is active, the two sources are mutually exclusive.

#### State transition table

Every transition edge in the FSM is listed below. Where a state has multiple outgoing transitions, each gets its own row.

| State | Entry From | Condition / Trigger | Actions (single cycle) | Next State |
|-------|-----------|---------------------|------------------------|------------|
| `STARTUP_DELAY` | Reset (power-on) | `delay_cnt` reaches 12,000 (1 ms elapsed) | Clear counter | `STARTUP` |
| `STARTUP` | `STARTUP_DELAY`, `FACTORY_RESET` | Banner character available and `!tx_busy` | Load `fsm_tx_byte` with next banner char; assert `fsm_tx_start` | `STARTUP` (self-loop until banner complete) |
| `STARTUP` | `STARTUP_DELAY`, `FACTORY_RESET` | Banner complete, `send_banner_after` set | Assert `resp_start` (send `OK\r\n`) | `CMD_RESP` |
| `STARTUP` | `STARTUP_DELAY`, `FACTORY_RESET` | Banner complete, `send_banner_after` clear | — | `IDLE` |
| `IDLE` | `TRANSMIT`, `STARTUP`, `CMD_OPCODE` | `rx_valid` && byte is A–Z | Latch `pt_index` = byte − 0x41 | `STEP` |
| `IDLE` | `TRANSMIT`, `STARTUP`, `CMD_OPCODE` | `rx_valid` && byte is `:` | — | `CMD_OPCODE` |
| `IDLE` | `TRANSMIT`, `STARTUP`, `CMD_OPCODE` | `rx_valid` && byte is other | Silently discard | `IDLE` |
| `STEP` | `IDLE` | Unconditional (single cycle) | Assert `step_pulse` | `STEP_WAIT` |
| `STEP_WAIT` | `STEP` | Unconditional (single cycle) | — (allows `stepper` registered outputs to settle) | `CIPHER_A` |
| `CIPHER_A` | `STEP_WAIT` | Unconditional (single cycle) | Drive `pt_index` into `enigma_forward`; latch `mid_letter_fwd` → `mid_letter_reg` at end of cycle | `CIPHER_B` |
| `CIPHER_B` | `CIPHER_A` | Unconditional (single cycle) | Drive `mid_letter_reg` into `enigma_backward`; latch `ct_index` at end of cycle | `TRANSMIT` (return to `IDLE`) |
| `TRANSMIT` | `CIPHER_B` | `tx_busy` == 0 | Assert `fsm_tx_start` with pending output byte | Continuation state (typically `IDLE`) |
| `CMD_OPCODE` | `IDLE` | `rx_valid` && opcode ∈ {`R`,`N`,`P`,`S`,`U`} | Latch `cmd_opcode`; set `arg_count` | `CMD_ARG` |
| `CMD_OPCODE` | `IDLE` | `rx_valid` && opcode == `?` | Latch `cmd_opcode` | `CMD_EXEC` |
| `CMD_OPCODE` | `IDLE` | `rx_valid` && opcode == `G` | — | `RESET_GRUNDSTELLUNG` |
| `CMD_OPCODE` | `IDLE` | `rx_valid` && opcode == `F` | — | `FACTORY_RESET` |
| `CMD_OPCODE` | `IDLE` | `rx_valid` && opcode unknown | Set response to ERR | `IDLE` (via `TRANSMIT`) |
| `CMD_OPCODE` | `IDLE` | Timeout (3 seconds) | — | `IDLE` |
| `CMD_ARG` | `CMD_OPCODE` | `rx_valid` && arg byte received (not CR/LF) | Convert byte to index; shift into `arg_buf` | `CMD_ARG` (continue collecting) |
| `CMD_ARG` | `CMD_OPCODE` | `rx_valid` && CR/LF received (or arg count met) | — | `CMD_EXEC` |
| `CMD_ARG` | `CMD_OPCODE` | Timeout (3 seconds) | — | `IDLE` |
| `CMD_EXEC` | `CMD_ARG`, `CMD_OPCODE` (`:?`) | Validation passes | Assert `cfg_wr_*`; set `resp_ok`=1; assert `resp_start`; (`:R` also asserts `load_pulse`) | `CMD_RESP` |
| `CMD_EXEC` | `CMD_ARG`, `CMD_OPCODE` (`:?`) | Validation fails | Set `resp_ok`=0; assert `resp_start` | `CMD_RESP` |
| `CMD_RESP` | `CMD_EXEC`, `STARTUP`, `RESET_GRUNDSTELLUNG` | `resp_done` asserted by `response_generator` | Clear `is_query` | `IDLE` |
| `RESET_GRUNDSTELLUNG` | `CMD_OPCODE` | Unconditional (single cycle) | Assert `load_pulse`; set `resp_ok`=1; assert `resp_start` | `CMD_RESP` |
| `FACTORY_RESET` | `CMD_OPCODE` | Unconditional (single cycle) | Assert `cfg_wr_factory` | `STARTUP` (retransmit banner, then `OK\r\n` → `IDLE`) |

#### ASCII state diagram

```
                         ┌──────────────────┐
                         │  STARTUP_DELAY   │
                         │    (4'b0000)     │
                         └────────┬─────────┘
                              1 ms elapsed
                                  │
                         ┌────────▼─────────┐
                    ┌────│     STARTUP      │◄──────────────────────────┐
                    │    │    (4'b0001)     │                           │
                    │    └────────┬─────────┘                           │
                    │    banner complete                                │
                    │             │                                     │
                    │  ┌─────────▼───────────────────────┐             │
                    │  │                IDLE              │             │
                    │  │              (4'b0010)           │◄───┐       │
                    │  └──┬──────────────┬──────────┬────┘    │       │
                    │     │              │          │          │       │
                    │  rx A–Z         rx ':'    other rx       │       │
                    │     │              │      (discard)      │       │
                    │     ▼              ▼                     │       │
                    │  ┌──────┐   ┌─────────────┐             │       │
                    │  │ STEP │   │ CMD_OPCODE  │             │       │
                    │  │(0011)│   │  (4'b1100)  │             │       │
                    │  └──┬───┘   └──┬──┬──┬──┬─┘             │       │
                    │     │          │  │  │  │               │       │
                    │     ▼          │  │  │  └───────────┐   │       │
                    │  ┌───────────┐ │  │  │  opcode=G    │   │       │
                    │  │ STEP_WAIT │ │  │  │      ┌───────▼───┴──┐    │
                    │  │ (4'b1101) │ │  │  │      │RESET_GRUNDSTL│    │
                    │  └──┬────────┘ │  │  │      │  (4'b1001)   │    │
                    │     │          │  │  │      └───────┬──────┘    │
                    │     ▼          │  │  │              │           │
                    │  ┌──────────┐  │  │  │     opcode=F │           │
                    │  │ CIPHER_A │  │  │  │      ┌───────▼──────┐    │
                    │  │ (4'b0100)│  │  │  └──────│FACTORY_RESET ├────┘
                    │  └──┬───────┘  │  │         │  (4'b1010)   │
                    │     │          │  │ opcode=? └──────────────┘
                    │     ▼          │  │    │
                    │  ┌──────────┐  │  │    │  opcode=R/N/P/S/U
                    │  │ CIPHER_B │  │  ▼    │
                    │  │ (4'b1011)│  │ ┌──────────┐
                    │  └──┬───────┘  │ │ CMD_ARG  │◄─┐
                    │     │          │ │(4'b0110) │──┘ (collecting args)
                    │     │          │ └──┬───────┘
                    │     │          │    │ CR/LF
                    │     │          │    ▼
                    │     │          │ ┌──────────┐
                    │     │          └►│ CMD_EXEC │
                    │     │            │(4'b0111) │
                    │     │            └──┬───────┘
                    │     │               │ resp_start
                    │     │               ▼
                    │     │          ┌──────────┐
                    │     │          │ CMD_RESP │
                    │     │          │(4'b1000) │ (response_generator
                    │     │          └──┬───────┘  drives TX directly)
                    │     │             │ resp_done
                    │     ▼             ▼
                    │  ┌─────────────────────────┐
                    └─►│       TRANSMIT          │
                       │       (4'b0101)         │
                       └──────────┬──────────────┘
                                  │ tx_busy==0: return to
                                  │ continuation state
                                  └──────────► (IDLE)
```

#### State descriptions by functional group

##### Startup path

**STARTUP_DELAY** (`4'b0000`) — After GSR deassertion, counts 12,000 cycles (1 ms at 12 MHz). This delay ensures the UART transceiver and external terminal have time to stabilize before the FSM begins transmitting. When the counter reaches 12,000, transitions unconditionally to STARTUP.

**STARTUP** (`4'b0001`) — Transmits the startup banner string one character at a time. For each character, loads `fsm_tx_byte` and asserts `fsm_tx_start` directly (self-looping in STARTUP until `!tx_busy`). When the final banner character has been sent: if `send_banner_after` is set (factory reset path), asserts both `load_pulse` (to reload stepper positions from the now-reset grundstellung) and `resp_start` to send `OK\r\n`, then transitions to CMD_RESP; otherwise transitions directly to IDLE.

##### Cipher data path

**IDLE** (`4'b0010`) — Waiting for `rx_valid`. On receipt of an A–Z byte: latches the converted plaintext index and transitions to STEP. On receipt of `:`: transitions to CMD_OPCODE. All other bytes are silently discarded (FSM remains in IDLE).

**STEP** (`4'b0011`) — Asserts `step_pulse` for one cycle to advance rotor positions via the `stepper` module. Transitions unconditionally to STEP_WAIT.

**STEP_WAIT** (`4'b1101`) — Single-cycle wait state. Allows `stepper`'s registered position outputs to settle after the `step_pulse`. Transitions unconditionally to CIPHER_A.

**CIPHER_A** (`4'b0100`) — **First pipeline stage.** Drives `pt_index` into `enigma_forward`. At the end of the cycle, latches the 5-bit `mid_letter_fwd` output into `mid_letter_reg`. Transitions unconditionally to CIPHER_B.

**CIPHER_B** (`4'b1011`) — **Second pipeline stage.** Drives `mid_letter_reg` into `enigma_backward`. At the end of the cycle, latches `ct_index` into `ct_latch`. Transitions unconditionally to TRANSMIT (with continuation state = IDLE).

**TRANSMIT** (`4'b0101`) — Waits for `tx_busy` to deassert. Once low, asserts `fsm_tx_start` with the pending `fsm_tx_byte`. Returns to the continuation state (typically IDLE after cipher output). Note: banner characters are sent directly from STARTUP, and response bytes are sent by the `response_generator` sub-module; TRANSMIT is used only for cipher output.

##### Command path

**CMD_OPCODE** (`4'b1100`) — Waits for `rx_valid` with the opcode byte following `:`. On receipt, latches the byte into `cmd_opcode`, determines `arg_count` from the opcode, and routes:

- `R`, `N`, `P`, `S`, `U` → CMD_ARG
- `?` → CMD_EXEC (no arguments needed)
- `G` → RESET_GRUNDSTELLUNG (bypasses CMD_ARG/CMD_EXEC)
- `F` → FACTORY_RESET (bypasses CMD_ARG/CMD_EXEC)
- Unknown opcode → sends ERR response, returns to IDLE

If no byte arrives within 3 seconds, times out and returns to IDLE.

**CMD_ARG** (`4'b0110`) — Shifts in fixed-length argument bytes. Argument bytes are converted to numeric indices as they arrive: rotor digit bytes use `byte - 0x31` (so `'1'` (0x31) → 0, `'5'` (0x35) → 4); letter bytes use `(byte & 0x5F) - 0x41` (so `'A'`/`'a'` → 0, `'Z'`/`'z'` → 25). The converted indices — not raw ASCII — are what get packed into `cfg_data` per the bit-layout tables below. On CR/LF (or when the expected argument count is met), transitions to CMD_EXEC. If no byte arrives within 3 seconds, times out and returns to IDLE.

**CMD_EXEC** (`4'b0111`) — Validates arguments (see validation rules below). If valid, drives the appropriate `cfg_wr_*` write-enable to `config_manager` and sets the response to `OK`. If invalid, sets the response to `ERR`. Transitions to CMD_RESP. For the `:R` command specifically, CMD_EXEC also asserts `load_pulse` (in addition to `cfg_wr_rotor`) to reload rotor positions from the stored Grundstellung, since changing rotor order invalidates the current stepped positions.

**CMD_RESP** (`4'b1000`) — Waits for the `response_generator` sub-module to finish emitting the response (`OK\r\n`, `ERR\r\n`, or the multi-line `:?` status dump). The `resp_start` pulse was asserted at entry to this state (by CMD_EXEC, STARTUP, or RESET_GRUNDSTELLUNG). The `response_generator` drives `tx_byte`/`tx_start` directly via the TX output mux. When `resp_done` is asserted, the FSM clears `is_query` and transitions to IDLE.

> **Note:** The response generation sub-state machine (line selection, character indexing, plugboard scanning) has been extracted into the `response_generator` module. See **Section 7a** for details.

##### Reset path

**RESET_GRUNDSTELLUNG** (`4'b1001`) — Single-cycle state. Asserts `load_pulse` to copy `grundstellung_*` → `pos_*` in the `stepper`. Sets `resp_ok`=1 and asserts `resp_start`, then transitions to CMD_RESP to await `resp_done`.

**FACTORY_RESET** (`4'b1010`) — Single-cycle state. Asserts `cfg_wr_factory` to restore all `config_manager` registers to factory defaults. Sets `send_banner_after`=1 and transitions to STARTUP to retransmit the banner. Note: `load_pulse` is NOT asserted in this state; it is deferred to STARTUP after the banner completes. After the banner completes, STARTUP asserts `resp_start` and transitions to CMD_RESP to send `OK\r\n`.

**Handling of `rx_valid` in non-waiting states:**

The FSM only samples `rx_valid` in states that explicitly wait for input: IDLE, CMD_OPCODE, and CMD_ARG. In all other states (STEP, STEP_WAIT, CIPHER_A, CIPHER_B, TRANSMIT, CMD_EXEC, CMD_RESP, RESET_GRUNDSTELLUNG, FACTORY_RESET, STARTUP_DELAY, STARTUP), `rx_valid` pulses are **silently ignored** — any byte received during these states is lost.

This is acceptable because the cipher path (STEP → STEP_WAIT → CIPHER_A → CIPHER_B) completes in 4 clock cycles (~333 ns), and the FSM enters TRANSMIT well before the next UART byte can arrive (~87 µs per byte at 115200 baud). The only state where the FSM may dwell for an extended period while not sampling `rx_valid` is TRANSMIT (and CMD_RESP, which loops through TRANSMIT). During multi-byte responses (e.g., the `:?` status dump), incoming bytes are lost. In practice, this is not a problem: the operator should wait for the response to complete before sending further input, and automated hosts should wait for the `OK\r\n` or `ERR\r\n` terminator before issuing the next command.

No input buffering beyond the `uart_rx` module's single `rx_byte` register is provided or required.

**Command parsing (CMD_OPCODE state, on opcode byte receipt):**

| Command prefix | Args expected | Action triggered                                    |
|----------------|---------------|-----------------------------------------------------|
| `:R`           | 3 digits      | `cfg_wr_rotor`; `cfg_data` = {rotor_l, rotor_m, rotor_r} (3×3-bit) |
| `:N`           | 3 letters     | `cfg_wr_ring`; `cfg_data` = {ring_l, ring_m, ring_r} (3×5-bit) |
| `:P`           | 3 letters     | `cfg_wr_grund`; `cfg_data` = {grnd_l, grnd_m, grnd_r} (3×5-bit) |
| `:S`           | 2 letters     | `cfg_wr_plug_add` (if both A-Z) or `cfg_wr_plug_clr` (if `--`) |
| `:G`           | 0             | Transition directly to RESET_GRUNDSTELLUNG (bypasses CMD_ARG/CMD_EXEC) |
| `:F`           | 0             | Transition directly to FACTORY_RESET (bypasses CMD_ARG/CMD_EXEC)       |
| `:?`           | 0             | Read `cfg_status`; stream bytes in CMD_RESP         |
| `:U`           | 1 letter      | Ignored in this implementation (UKW-B fixed)        |

**`cfg_data[15:0]` bit layout per command:**

The FSM packs command arguments into the 16-bit `cfg_data` bus before asserting the corresponding `cfg_wr_*` write-enable. Unused high bits are driven to zero.

| Command | `cfg_data[15:0]` layout | Field widths | Valid range per field |
|---------|------------------------|--------------|---------------------|
| `:R`    | `{7'b0, rotor_l[2:0], rotor_m[2:0], rotor_r[2:0]}` | 3×3-bit | 0–4 each |
| `:N`    | `{1'b0, ring_l[4:0], ring_m[4:0], ring_r[4:0]}` | 3×5-bit | 0–25 each |
| `:P`    | `{1'b0, grnd_l[4:0], grnd_m[4:0], grnd_r[4:0]}` | 3×5-bit | 0–25 each |
| `:S` (add pair) | `{6'b0, letter_a[4:0], letter_b[4:0]}` | 2×5-bit | 0–25 each; `a != b` |
| `:S` (clear) | `{6'b0, 5'h1F, 5'h1F}` | sentinel | Fixed value signals clear-all |
| `:U`    | `{8'b0, refl[7:0]}` | 1×8-bit | Only `8'h42` (`'B'`) accepted |

> **Note:** For zero-argument commands (`:G`, `:F`, `:?`), `cfg_data` is don't-care; the FSM routes directly to the appropriate handler state without passing through CMD_EXEC.

**CMD_EXEC validation rules (all checked in FSM before asserting any `cfg_wr_*`):**

| Command | Validation checks | On failure |
|---------|------------------|------------|
| `:R`    | Each rotor index in range 0–4; all three distinct (`l!=m`, `l!=r`, `m!=r`) | `ERR` |
| `:N`    | Each ring value in range 0–25 | `ERR` |
| `:P`    | Each position value in range 0–25 | `ERR` |
| `:S` (add) | `a != b`; `plug_map[a] == a` (not already wired); `plug_map[b] == b` (not already wired); `plug_pair_cnt < 13` (max 12 active pairs) | `ERR` |
| `:S` (clear) | None (always succeeds) | — |
| `:U`    | Reflector byte == `'B'` (0x42) | `ERR` |

> **Implementation note:** The `:R` duplicate check requires three 3-bit comparators (~3 LCs). The `:S` already-wired check reads `plug_map[a]` and `plug_map[b]` combinationally from `config_manager`'s output bus and compares each against itself (~4 LCs). Total validation overhead: ~10 LCs, included in the FSM's 200 LC estimate.

**Estimated LC usage:** ~200 LCs (the `:?` sub-state registers have been extracted to `response_generator`; TX mux and handshake signals add ~5 LCs)

---

### 7a. `response_generator`

**Purpose:** Command response generation sub-module, instantiated inside `fsm_controller`. Handles `OK\r\n` / `ERR\r\n` string emission and the multi-line `:?` status query response. Receives a `start` pulse from the FSM and drives `tx_byte`/`tx_start` directly (via the FSM's TX output mux). Signals completion with a single-cycle `done` pulse.

| Port Name           | Direction | Width | Description                                                                 |
|---------------------|-----------|-------|-----------------------------------------------------------------------------|
| `clk`               | input     | 1     | System clock                                                                |
| `rst_n`             | input     | 1     | Active-low synchronous reset                                                |
| `start`             | input     | 1     | Single-cycle pulse: begin response                                          |
| `resp_ok`           | input     | 1     | 1 = OK response, 0 = ERR response                                          |
| `is_query`          | input     | 1     | 1 = `:?` multi-line query response                                         |
| `done`              | output    | 1     | Single-cycle pulse: response complete                                       |
| `tx_busy`           | input     | 1     | UART TX busy flag (from `uart_tx` via `fsm_controller`)                     |
| `tx_byte`           | output    | 8     | Byte to transmit (drives FSM's TX output mux)                              |
| `tx_start`          | output    | 1     | Pulse: begin transmitting `tx_byte`                                         |
| `cfg_status[63:0]`  | input     | 64    | Packed status word from `config_manager` (for `:?` query lines)             |
| `pos_l[4:0]`        | input     | 5     | Current left rotor position (for POS line)                                  |
| `pos_m[4:0]`        | input     | 5     | Current middle rotor position                                               |
| `pos_r[4:0]`        | input     | 5     | Current right rotor position                                                |
| `plug_map[129:0]`   | input     | 5×26  | Plugboard wiring map (for PLG line scan)                                    |

**Internal state:**

The module has a 2-state FSM: `RESP_IDLE` and `RESP_ACTIVE`.

On the `start` pulse, the module latches `resp_ok` and `is_query`, resets all internal counters, and transitions to `RESP_ACTIVE`.

Internal registers (all moved here from `fsm_controller`):

- `resp_idx[2:0]` — byte index for OK/ERR emission.
- `resp_phase[2:0]` — selects which `:?` line to emit: 0=UKW, 1=ROT, 2=RNG, 3=GRD, 4=POS, 5=PLG, 6=OK.
- `resp_char[4:0]` — character index within the current line.
- `plug_scan[4:0]` — plugboard scan counter (0–25) for the PLG line.
- `first_pair` — flag controlling space separator before plugboard pairs.
- `plg_substate[1:0]` — PLG sub-sub-state: 0=scanning, 1=emit first letter (after space), 2=emit second letter.

A combinational block generates the next character to emit (`query_char`) based on `resp_phase`, `resp_char`, `plug_scan`, and `plg_substate`. Flags `query_done_line`, `query_done_all`, and `query_no_emit` control line/response completion and plugboard scan skipping.

**TX output mux (in `fsm_controller`):**

The `response_generator`'s `tx_byte`/`tx_start` outputs are named `resp_tx_byte`/`resp_tx_start` at the instantiation site. The FSM has its own `fsm_tx_byte`/`fsm_tx_start` for banner and cipher output. The module-level ports are driven by:

```verilog
assign tx_start = fsm_tx_start | resp_tx_start;
assign tx_byte  = resp_tx_start ? resp_tx_byte : fsm_tx_byte;
```

Since CMD_RESP is mutually exclusive with all other TX-driving states, `resp_tx_start` is zero when the response_generator is idle, and `fsm_tx_start` is zero during CMD_RESP.

**Estimated LC usage:** ~35 LCs (response registers, character generation logic, 2-state FSM)

---

### 8. `config_manager`

**Purpose:** Holds all Enigma machine configuration registers and exposes them as combinational outputs to the cipher and stepper modules, with synchronous write ports driven by the FSM.

| Port Name              | Direction | Width  | Description                                                              |
|------------------------|-----------|--------|--------------------------------------------------------------------------|
| `clk`                  | input     | 1      | System clock                                                             |
| `rst_n`                | input     | 1      | Active-low synchronous reset (loads factory defaults)                    |
| `wr_rotor`             | input     | 1      | Write-enable: update rotor selection registers                           |
| `wr_ring`              | input     | 1      | Write-enable: update ring setting registers                              |
| `wr_grund`             | input     | 1      | Write-enable: update Grundstellung registers                             |
| `wr_plug_add`          | input     | 1      | Write-enable: add one stecker pair                                       |
| `wr_plug_clr`          | input     | 1      | Write-enable: clear all plugboard mappings to identity                   |
| `wr_factory`           | input     | 1      | Write-enable: restore all registers to factory defaults                  |
| `cfg_data[15:0]`       | input     | 16     | Payload from FSM (packed per command type; see FSM table above)          |
| `rotor_sel_l`          | output    | 3      | Left rotor index (0=I…4=V)                                              |
| `rotor_sel_m`          | output    | 3      | Middle rotor index                                                       |
| `rotor_sel_r`          | output    | 3      | Right rotor index                                                        |
| `ring_l`               | output    | 5      | Left rotor ring setting 0..25                                            |
| `ring_m`               | output    | 5      | Middle rotor ring setting                                                |
| `ring_r`               | output    | 5      | Right rotor ring setting                                                 |
| `grundstellung_l`      | output    | 5      | Left initial position 0..25                                              |
| `grundstellung_m`      | output    | 5      | Middle initial position                                                  |
| `grundstellung_r`      | output    | 5      | Right initial position                                                   |
| `plug_map[129:0]`      | output    | 5×26   | Full plugboard wiring map (flat 130-bit bus)                             |
| `pos_l[4:0]`           | input     | 5      | Current left rotor live position from `stepper` (forwarded into `cfg_status`) |
| `pos_m[4:0]`           | input     | 5      | Current middle rotor live position from `stepper`                        |
| `pos_r[4:0]`           | input     | 5      | Current right rotor live position from `stepper`                         |
| `cfg_status[63:0]`     | output    | 64     | Packed status word for `:?` query. Bit layout (MSB→LSB):<br>`[63:55]` rotor_sel (9 bits: `[63:61]`=left, `[60:58]`=mid, `[57:55]`=right)<br>`[54:40]` rings (15 bits: `[54:50]`=left, `[49:45]`=mid, `[44:40]`=right)<br>`[39:25]` grundstellung (15 bits: `[39:35]`=left, `[34:30]`=mid, `[29:25]`=right)<br>`[24:20]` plug_pair_count (5 bits, 0–13)<br>`[19:15]` pos_l live (5 bits, from `stepper`)<br>`[14:10]` pos_m live (5 bits, from `stepper`)<br>`[9:5]` pos_r live (5 bits, from `stepper`)<br>`[4:0]` reserved (tied 0) |

**Internal registers:**
- `rotor_sel_l_r[2:0]`, `rotor_sel_m_r[2:0]`, `rotor_sel_r_r[2:0]` — rotor selection (factory default: 0, 1, 2 = rotors I, II, III).
- `ring_l_r[4:0]`, `ring_m_r[4:0]`, `ring_r_r[4:0]` — ring settings (factory default: 0, 0, 0 = AAA).
- `grundstellung_l_r[4:0]`, `grundstellung_m_r[4:0]`, `grundstellung_r_r[4:0]` — initial positions (factory default: 0, 0, 0 = AAA).
- `plug_map_r[25:0][4:0]` — 26 × 5-bit plugboard entries; initialised to identity (entry i = i); reciprocal pairs written by FSM (both `plug_map_r[a] = b` and `plug_map_r[b] = a`).
- `plug_pair_cnt[4:0]` — count of active stecker pairs (0..12).
- `cfg_status` is assembled combinationally each cycle from the above registers plus the `pos_l/m/r` input ports; it is not a registered output.

**Stecker pair write logic (on `wr_plug_add`):**
- `a = cfg_data[9:5]`, `b = cfg_data[4:0]` (both 0..25).
- **Validation (performed in FSM CMD_EXEC before asserting `wr_plug_add`):**
  - `a == b` → `ERR` (cannot pair a letter with itself).
  - `plug_map_r[a] != a` (letter `a` already wired) → `ERR`.
  - `plug_map_r[b] != b` (letter `b` already wired) → `ERR`.
  - `plug_pair_cnt >= 13` (board full; maximum 12 active pairs) → `ERR`.
  - Otherwise: assert `wr_plug_add`.
- Reciprocal write: `plug_map_r[a] <= b; plug_map_r[b] <= a; plug_pair_cnt <= plug_pair_cnt + 1;`.
- The operator must use `:S--` (`wr_plug_clr`) to clear all pairs before re-wiring any letter that is already part of an existing pair.

> **Note:** The `config_manager` exposes `plug_map` as a combinational output, so the FSM can read `plug_map[a]` and `plug_map[b]` directly during CMD_EXEC to perform the validation checks above. No additional ports are needed.

**Estimated LC usage:** ~150 LCs

---

### LC Budget Summary

| Module               | Estimated LCs | Notes                                                        |
|----------------------|---------------|--------------------------------------------------------------|
| `enigma_top`         | 103           | Structural wiring (5) + POR counter + ext_rst_n sync (10) + LED counters/monostables (88) |
| `uart_rx`            | 45            | Synchroniser + baud counter + shift register                |
| `uart_tx`            | 45            | Baud counter + shift register + 1-byte queue            |
| `enigma_forward`     | 120           | plug + 3× fwd MUX-tree substitutions + 6 modular adders + reflector |
| `enigma_backward`    | 100           | 3× inv MUX-tree substitutions + 6 modular adders + plug    |
| `stepper`            | 55            | 3× 5-bit registered pos + notch decode + step logic         |
| `plugboard`          | 30            | 26:1 MUX (counted once; 2 instances share bus)             |
| `fsm_controller`     | 200           | FSM + cmd parser + buffers + control signals + TX mux       |
| `response_generator` | 35            | Response sub-state machine + char generation (inside `fsm_controller`) |
| `config_manager`     | 150           | 26×5-bit RAM-style registers + write logic                  |
| **Total**            | **2,900**     | **~38% of 7,680 LC budget** ✓                              |

The 2,900 LC estimate leaves ~4,780 LCs (~62%) of headroom for:
- Synthesis overhead and routing duplication (typically +10–15%).
- Optional debug UART echo path.
- Future extension to full 5-rotor selection or additional reflectors.
- Place-and-route slack without risking timing closure at 12 MHz.

> **Actual synthesis results** (Yosys `synth_ice40`, via `make synth-check`): 4,213 cells total — 3,182 SB_LUT4, 518 flip-flops (SB_DFF variants), 513 SB_CARRY. The cell count exceeds the LC estimate because Yosys counts LUTs, flip-flops, and carry chains as separate cells, whereas the LC estimate counts logic cells (each containing one LUT + one FF). The design comfortably fits the 7,680-LC budget.

---

### Design Constraints Notes

1. **Timing:** The full combinational cipher path is estimated at **75 LUT levels**. At typical iCE40 routing delays (~1.34 ns/level) this yields ~100 ns, exceeding the 83.3 ns clock period. The **2-cycle pipeline is the primary implementation**: the cipher path is split into two separate combinational modules (`enigma_forward` and `enigma_backward`) with a 5-bit register in the FSM between them. CIPHER_A drives `enigma_forward` (39 LUT levels, ~52 ns typical); CIPHER_B drives `enigma_backward` (36 LUT levels, ~48 ns typical). Both halves comfortably meet timing. See the Timing Analysis section for full analysis.
2. **UART baud rate:** Default 115200 baud, 8N1. Both `uart_rx` and `uart_tx` accept a `parameter BAUD_DIV` (default 103, derived from `CLK_FREQ / BAUD_RATE - 1`), overridden by `enigma_top`. `uart_rx` also accepts `parameter HALF_BIT` (default 51). All timing constants are derived from `enigma_top`'s `CLK_FREQ` and `BAUD_RATE` parameters.
3. **Plugboard reciprocity:** Enforced entirely in `config_manager` write logic; `enigma_forward` and `enigma_backward` treat `plug_map` as an arbitrary lookup table.
4. **Reset behaviour:** Hardware reset is provided by three mechanisms: (a) iCE40 GSR at power-on/reprogramming initialises all registers to their declared `initial` values; (b) a 10-bit power-on-reset counter in `enigma_top` holds `rst_n` deasserted for 1024 clocks (~85 µs) after GSR; (c) an optional `ext_rst_n` input pin (active-low, 2-FF synchronised) allows external reset buttons. The derived signal `rst_n = por_done & ext_rst_sync2` is routed to all sub-module `rst_n` ports. Runtime factory reset is initiated by the `:F` UART command, which asserts `cfg_wr_factory` to `config_manager` for one clock cycle.
5. **Double-step anomaly:** Implemented in `stepper` by checking `pos_m_r == notch_m` as both a middle-step trigger and a left-step trigger, which is the historically correct Wehrmacht Enigma behaviour.
6. **Plugboard bus fanout:** The 130-bit `plug_map` bus fans out from `config_manager` to both `enigma_forward` and `enigma_backward`. The synthesis tool (Yosys/nextpnr) may duplicate LUTs automatically to reduce routing congestion. Monitor the nextpnr routing report; if congestion is excessive, consider instantiating a single `plugboard` module at the top level and sharing its 5-bit output rather than passing the full 130-bit bus into both cipher modules.


## AMD Artix-7 Support (Arty A7-100T and Nexys A7-100T)

This specification's RTL core (`enigma_top` and all sub-modules) is implemented in portable, vendor-neutral synthesizable Verilog-2001 with no iCE40-specific primitives. AMD Artix-7 board support is provided through thin wrapper modules that adapt the 100 MHz board oscillator to the 12 MHz design clock via an on-chip MMCM.

### Target Parts

| Board | FPGA Part | Toolchain |
|---|---|---|
| Digilent Arty A7-100T | `xc7a100tcsg324-1` | Vivado 2025.1 (batch/CLI mode) |
| Digilent Nexys A7-100T | `xc7a100tcsg324-1L` | Vivado 2025.1 (batch/CLI mode) |

### Clock Architecture

The Artix-7 boards supply a 100 MHz oscillator. An `MMCME2_BASE` primitive generates the 12 MHz design clock:

```
CLKFBOUT_MULT_F  = 9.0      VCO = 100 × 9 / 1 = 900 MHz
DIVCLK_DIVIDE    = 1
CLKOUT0_DIVIDE_F = 75.0     Output = 900 / 75 = 12.000 MHz
```

The `MMCM LOCKED` output gates the combined reset: `combined_rst_n = mmcm_locked` (ext_rst_n is bypassed). The design is held in reset until the MMCM achieves lock.

**Note on ext_rst_n bypass:** The Nexys A7 Rev D board has a known issue where pin N17 (CPU_RESETN) can float or exhibit noise during power-on, causing spurious resets. To work around this, enigma_top_amd bypasses the ext_rst_n input and relies solely on mmcm_locked for reset generation.

### Module Hierarchy for AMD Targets

```
enigma_top_arty   (rtl/enigma_top_arty.v)   ← Vivado top for Arty A7-100T
  └── enigma_top_amd   (rtl/enigma_top_amd.v)   ← MMCM wrapper; generates 12 MHz
        └── enigma_top  (rtl/enigma_top.v)        ← Unchanged original top

enigma_top_nexys  (rtl/enigma_top_nexys.v)  ← Vivado top for Nexys A7-100T
  └── enigma_top_amd   (shared)
        └── enigma_top  (shared)
```

Reset polarity is board-specific: the Arty A7's BTN0 is active-high and is inverted in `enigma_top_arty`; the Nexys A7's `CPU_RESETN` is active-low and is passed through directly in `enigma_top_nexys`.

### AMD Resource Utilization (Yosys `synth_xilinx` estimate)

| Resource | Used (estimated) | Available (XC7A100T) | Utilization |
|---|---|---|---|
| LUT6 | ~968 | 63,400 | ~1.5% |
| MUXCY (carry) | ~741 | — | — |
| MUXF7/F8 | ~395 | — | — |
| MMCME2_BASE | 1 | 8 | — |
| Estimated LCs | ~1,633 | 101,440 | ~1.6% |

The design fits comfortably within even the smallest Artix-7 variant.

### AMD Build and Program Commands

```sh
# Full synthesis + implementation + bitstream (Vivado required in PATH)
make synth-arty        # → build/enigma_arty_a7.bit
make synth-nexys       # → build/enigma_nexys_a7.bit

# Program connected board via Vivado hw_manager
make upload-arty
make upload-nexys

# Open-source Yosys AMD synthesis check (runs in CI, no Vivado required)
make synth-check-amd
```

Vivado is invoked in non-interactive batch mode only:
```sh
vivado -mode batch -source tcl/build_arty_a7.tcl
```

### AMD Pin Assignments

#### Arty A7-100T (`constraints/arty_a7_100t.xdc`)

| Signal | Pin | Description |
|---|---|---|
| `clk_100mhz` | E3 | 100 MHz XTAL oscillator |
| `ext_rst_n` | C2 | BTN0 (active-high, inverted in `enigma_top_arty`) |
| `uart_rx` | A9 | USB-UART FTDI TXD → FPGA RX |
| `uart_tx` | D10 | FPGA TX → USB-UART FTDI RXD |
| `led_d1` | H5 | LD0 (green) — Heartbeat |
| `led_d2` | J5 | LD1 (green) — RX activity |
| `led_d3` | T9 | LD2 (green) — TX activity |
| `led_d4` | T10 | LD3 (green) — Command mode |
| `led_d5` | G6 | LD4_R (red channel) — Error |

#### Nexys A7-100T (`constraints/nexys_a7_100t.xdc`)

| Signal | Pin | Description |
|---|---|---|
| `clk_100mhz` | E3 | 100 MHz system clock |
| `ext_rst_n` | N17 | CPU_RESETN (active-low, passed through directly) |
| `uart_rx` | C4 | USB-RS232 bridge TXD → FPGA RX |
| `uart_tx` | D4 | FPGA TX → USB-RS232 bridge RXD |
| `led_d1` | H17 | LD0 — Heartbeat |
| `led_d2` | K15 | LD1 — RX activity |
| `led_d3` | J13 | LD2 — TX activity |
| `led_d4` | N14 | LD3 — Command mode |
| `led_d5` | R18 | LD4 — Error |

All I/O standards: LVCMOS33.
