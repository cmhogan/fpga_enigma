<!--
  spec_reset_init.md — Part 4 of 5
  Audience: RTL developers and agents working on power-on behavior, reset
  sequencing, startup banner transmission, LED diagnostics, Grundstellung reset
  (:G command), and factory reset (:F command).

  Sibling documents (do NOT duplicate their content here):
    spec_cipher_algorithm.md  — Cipher math, wiring tables, substitution algorithm
    spec_rtl_modules.md       — Module hierarchy, port definitions, FSM, AMD support
    spec_uart_protocol.md     — UART protocol, command reference, character I/O
    spec_verification.md      — Timing analysis, test vectors, toolchain, pin assignments
    spec_index.md             — Navigator: one-line description of each spec document
-->

## Reset and Initialization

The reset and initialization subsystem of the Enigma I FPGA implementation must provide reliable power-on behavior, runtime reconfiguration capabilities, and a diagnostic interface to confirm operational readiness. Unlike mechanical Enigma machines, which required manual setup before each operating session, the digital implementation must manage three distinct categories of reset: hardware initialization following FPGA configuration, operator-initiated Grundstellung reset (returning rotors to their configured starting positions), and factory reset (returning all configuration parameters to their default values). This section specifies the precise timing, electrical behavior, register initialization strategy, and protocol responses for each reset mechanism.

### Power-On Initialization and FPGA Configuration Sequence

The iCE40-HX8K implements a hardwired configuration sequence controlled by an internal state machine. Upon application of power to the iCE40-HX8K Breakout Board, the FPGA immediately begins loading its bitstream from the onboard Micron N25Q032A SPI flash memory. This process is governed by the iCE40's internal configuration logic and typically completes within 50-100 milliseconds, depending on the bitstream size and SPI clock rate.

During the configuration phase, all flip-flops and registers within the user design are subject to the **Global Set/Reset (GSR)** signal. The GSR is a dedicated internal signal that initializes all sequential elements to their declared initial values before releasing the design into normal operation. For the Enigma I implementation, this means that all rotor position registers, configuration settings, FSM state registers, and UART interface logic are synchronously reset to well-defined values at the conclusion of the bitstream load.

The iCE40 architecture guarantees that GSR is asserted for a minimum duration sufficient to reset all sequential elements, regardless of their physical location on the die. Once the configuration is complete and the GSR is deasserted, the 12 MHz oscillator begins driving the global clock network, and the design enters its operational state.

#### Electrical Behavior of UART Interface at Power-On

A critical detail for reliable terminal communication is the behavior of the UART TX line during and immediately after configuration. The iCE40 I/O pins are held in a high-impedance state during bitstream loading. Once configuration completes, the UART TX pin is driven by the user logic and must immediately transition to the UART idle state, which is logic HIGH.

However, the FTDI FT2232HL USB-to-serial bridge on the iCE40-HX8K Breakout Board may interpret the transition from high-impedance or undefined state to logic HIGH as a transient glitch or incomplete start bit, potentially causing synchronization errors in the attached terminal application. To mitigate this, the FPGA design must implement a **startup delay** of approximately 1 millisecond (12,000 clock cycles at 12 MHz) following GSR deassertion before transmitting any characters on the UART TX line. This delay allows the FTDI receiver to stabilize and synchronize to the idle line state.

#### Mandatory Initial Values for All Configuration Registers

To ensure predictable behavior across power cycles and to eliminate any dependency on undefined logic states, **all configuration and state registers must be explicitly initialized** in the Verilog source code. The Yosys synthesis tool for the iCE40 architecture supports two forms of register initialization:

1. **Inline initial value assignment:**
   ```verilog
   reg [4:0] rotor1_position = 5'd0;
   reg [4:0] rotor2_position = 5'd0;
   reg [4:0] rotor3_position = 5'd0;
   ```

2. **Initial block assignment:**
   ```verilog
   reg [4:0] rotor1_position;
   initial begin
       rotor1_position = 5'd0;
   end
   ```

Both forms are synthesizable on the iCE40 and result in identical behavior: the register is reset to the specified value during GSR. The inline form is preferred for configuration registers due to its compactness and clarity.

The following registers must have explicit initial values defined:

| Register Name | Width | Initial Value | Description |
|---------------|-------|---------------|-------------|
| `rotor_order[2:0]` | 3×3 bits | `{3'd0, 3'd1, 3'd2}` | Rotor selection: I-II-III (indices 0, 1, 2) |
| `ring_settings[2:0]` | 3×5 bits | `{5'd0, 5'd0, 5'd0}` | Ring settings: AAA (all zero offset) |
| `initial_positions[2:0]` | 3×5 bits | `{5'd0, 5'd0, 5'd0}` | Grundstellung: AAA |
| `current_positions[2:0]` | 3×5 bits | `{5'd0, 5'd0, 5'd0}` | Current rotor positions: AAA |
| `plugboard[25:0]` | 26×5 bits | Identity mapping | Each entry maps to itself (no swaps) |
| `fsm_state` | 4 bits | `STARTUP_DELAY` (4'b0000) | FSM starts in STARTUP_DELAY; performs 1 ms stabilization delay, then transmits banner, then enters IDLE |
| `uart_tx` | 1 bit | `1'b1` | TX line must be HIGH (idle) |
| `heartbeat_counter` | 20-24 bits | `0` | LED heartbeat timer |

The reflector selection is fixed to UKW-B in this implementation and does not require a configuration register.

### Startup Banner Transmission

Immediately following the 1 ms stabilization delay after GSR deassertion, the FPGA must transmit a **startup banner** via the UART interface. The purpose of this banner is to provide immediate confirmation to the operator that the device has successfully configured, passed internal initialization, and is ready to accept commands.

The recommended startup banner is:

```
ENIGMA I READY\r\n
```

This string is compact (16 bytes including the CR-LF terminator), historically appropriate, and unambiguous. Alternative banners such as `WEHRAMCHT ENIGMA I v1.0\r\n` may be used if version identification or additional metadata is desired, but the banner must not exceed 64 bytes to avoid excessive startup delay.

The startup banner transmission is managed by the FSM as follows:

1. The FSM enters a dedicated `STARTUP` state following the 1 ms post-GSR delay.
2. A character pointer is initialized to index 0 of the banner string (stored in a ROM or parameter array).
3. Each character is sequentially loaded into the UART TX module and transmitted.
4. Upon completion of the final character (`\n`), the FSM transitions to the `IDLE` state and begins monitoring the UART RX line for incoming commands.

The startup banner should be transmitted at the configured baud rate of 115,200 bps, resulting in a total transmission time of approximately 1.4 milliseconds for a 16-byte banner.

**Timing Diagram: Power-On to Operational State**

```
Power Applied
    |
    v
[0 ms] ────────► FPGA begins bitstream load from SPI flash
    |
    |  (50-100 ms typical)
    |
    v
[~80 ms] ───────► Configuration complete, GSR deasserted
    |              All registers initialized to declared values
    |              UART TX transitions to HIGH (idle)
    |
    v
[~81 ms] ───────► 1 ms stabilization delay (FTDI sync)
    |
    v
[~82 ms] ───────► Startup banner transmission begins
    |              "ENIGMA I READY\r\n" (16 bytes @ 115200 bps)
    |
    v
[~83.4 ms] ─────► FSM enters IDLE state
    |              Ready to accept UART commands
    v
[Normal Operation]
```

### Grundstellung Reset (`:G` Command)

> **Cross-reference:** FSM state transitions for `:G` and `:F` are defined in **Section 7 (`fsm_controller`)**. This section provides operational context, scope, and timing details.

The `:G` command implements the operator's ability to reset the rotor positions to their configured Grundstellung (initial positions) without disturbing any other machine parameters. This corresponds to the physical action of manually rotating the rotor rings back to their starting letters before beginning a new message encryption session.

**Scope of Reset:**
- **Modified:** `current_positions[2:0]` registers are copied from `initial_positions[2:0]`
- **Preserved:** `rotor_order`, `ring_settings`, `initial_positions`, `plugboard`, reflector selection

**Command Protocol:**

1. The operator transmits the 2-byte sequence `:G`. The FSM executes immediately upon receiving the `G` opcode byte — no CR/LF terminator is required.
2. The UART RX module captures the command and asserts a `cmd_grundstellung` signal to the FSM.
3. The FSM, if currently in the `IDLE` state, transitions to a `RESET_GRUNDSTELLUNG` state.
4. In a single clock cycle, the FSM executes:
   ```verilog
   current_positions[0] <= initial_positions[0];  // Right rotor
   current_positions[1] <= initial_positions[1];  // Middle rotor
   current_positions[2] <= initial_positions[2];  // Left rotor
   ```
5. The FSM transitions to the `TRANSMIT` state and sends the response string `OK\r\n` via the UART TX module.
6. Upon completion of the transmission, the FSM returns to the `IDLE` state.

The Grundstellung reset is **non-blocking** and takes effect immediately. If a character encryption operation was in progress when the `:G` command was received, that operation is aborted, and the response is sent without completing the encryption. This ensures that configuration commands have priority over data processing.

**Timing:** The Grundstellung reset completes in approximately 4 clock cycles (register update + FSM transition overhead) plus the UART transmission time for `OK\r\n` (4 bytes ≈ 347 µs at 115,200 bps).

### Factory Reset (`:F` Command)

The `:F` command performs a **complete reset** of all configuration registers to their power-on default values. This is the software equivalent of power-cycling the device and is intended for diagnostic purposes, recovery from misconfiguration, or preparation for a new operator session.

**Scope of Reset:**
- **Modified:** All configuration and state registers (see table above)
- **Effect:** Equivalent to GSR, but initiated by software command rather than hardware

**Command Protocol:**

1. The operator transmits the 2-byte sequence `:F`. The FSM executes immediately upon receiving the `F` opcode byte — no CR/LF terminator is required.
2. The UART RX module captures the command and asserts a `cmd_factory_reset` signal to the FSM.
3. The FSM transitions to a `FACTORY_RESET` state and asserts a synchronous reset signal, `factory_rst`, for one clock cycle.
4. All configuration registers are synchronously reset to their initial values using the same values specified for GSR initialization.
5. The FSM transitions to the `STARTUP` state and **retransmits the startup banner** (`ENIGMA I READY\r\n`).
6. Following the banner, the FSM sends the response `OK\r\n` and returns to the `IDLE` state.

**Deferred Load Pulse:** The `cfg_wr_factory` signal fires in the `FACTORY_RESET` FSM state, resetting `config_manager` registers including the grundstellung to AAA. The `load_pulse` signal fires later, in the `STARTUP` state after the banner transmission completes. This timing ensures that the stepper reloads its positions from the now-reset grundstellung, avoiding a same-cycle race where the stepper would sample the old grundstellung values.

**Verilog Implementation:**

Each configuration register module must include a synchronous reset input that overrides normal operation:

```verilog
always @(posedge clk) begin
    if (factory_rst) begin
        rotor_order[0] <= 3'd0;  // Rotor I
        rotor_order[1] <= 3'd1;  // Rotor II
        rotor_order[2] <= 3'd2;  // Rotor III
        ring_settings[0] <= 5'd0;
        ring_settings[1] <= 5'd0;
        ring_settings[2] <= 5'd0;
        initial_positions[0] <= 5'd0;
        initial_positions[1] <= 5'd0;
        initial_positions[2] <= 5'd0;
        current_positions[0] <= 5'd0;
        current_positions[1] <= 5'd0;
        current_positions[2] <= 5'd0;
        // Plugboard reset to identity
        for (int i = 0; i < 26; i = i + 1) begin
            plugboard[i] <= i[4:0];
        end
    end else begin
        // Normal configuration and operation logic
    end
end
```

**Note on Banner Transmission:**

The factory reset is the **only** runtime command that triggers retransmission of the startup banner. This distinguishes it from the Grundstellung reset and provides the operator with clear feedback that a complete system reset has occurred. The banner is sent first, followed by the `OK\r\n` acknowledgment.

**Timing:** Factory reset completes in 1 clock cycle (synchronous reset assertion) followed by the startup banner transmission (~1.4 ms) and the `OK\r\n` response (~347 µs), for a total elapsed time of approximately 1.75 milliseconds.

### Hardware Reset Mechanisms and GSR Details

The iCE40-HX8K does not expose a dedicated external reset pin in typical configurations, and the iCE40-HX8K Breakout Board does not provide a user-accessible reset button. However, the implementation provides two hardware reset mechanisms beyond GSR:

**1. Global Set/Reset (GSR):** Automatically asserted during FPGA configuration. Triggered by:
- **Power-on:** Application of VCC to the FPGA die.
- **Reprogramming:** Uploading a new bitstream via `iceprog` or SPI flash update.
- **Configuration error recovery:** Internal watchdog or CRC failure during bitstream load.

**2. Power-On Reset (POR) counter:** After GSR deassertion, a 10-bit counter in `enigma_top` holds `rst_n` deasserted for 1024 clock cycles (~85 µs at 12 MHz). This ensures all sub-modules are cleanly reset before the FSM begins operation.

**3. External reset (`ext_rst_n`):** The `enigma_top` module accepts an optional active-low `ext_rst_n` input pin, guarded by a 2-FF metastability synchronizer. When driven LOW, it holds all sub-modules in reset. Tie to `1'b1` if unused. The derived reset signal is:

```verilog
wire rst_n = por_done & ext_rst_sync2;
```

This signal is routed to all sub-module `rst_n` ports, providing a unified reset path for GSR, POR, and external reset.

**Note on AMD boards:** On AMD-based boards (using `enigma_top_amd.v`), the `ext_rst_n` input is currently bypassed: `combined_rst_n = mmcm_locked` (not `mmcm_locked & ext_rst_n`). This is because pin N17 (CPU_RESETN) on the Nexys A7 Rev D reads as permanently low, which would hold the design in reset. On these boards, the POR generator and MMCM lock provide the only reset sources. The iCE40 path is unchanged.

#### Optional Soft Reset via SB_GB Global Buffer

For designs requiring the external reset to reach all sequential elements with minimal skew, the iCE40 architecture provides the `SB_GB` global buffer primitive. This is not required for the baseline implementation (the `ext_rst_n` path above is sufficient) but may be useful for high-fanout scenarios.

Example instantiation:

```verilog
wire global_reset;
SB_GB reset_buffer (
    .USER_SIGNAL_TO_GLOBAL_BUFFER(external_reset_btn),
    .GLOBAL_BUFFER_OUTPUT(global_reset)
);
```

### Reset Sequencing and FSM State Transitions

The following state diagram illustrates the interaction between the FSM and the three reset mechanisms:

```
                              Power-On / GSR
                                    |
                                    v
                            [ STARTUP_DELAY ]
                             (1 ms timer)
                                    |
                                    v
                              [ STARTUP ]
                          (Transmit banner)
                                    |
                                    v
        ┌───────────────────────► [ IDLE ] ◄──────────────┐
        |                             |                     |
        |                             |                     |
        |   ':G' received             |   ':F' received    |
        |                             v                     |
        |                    [ RESET_GRUNDSTELLUNG ]        |
        |                      (Copy initial_pos)           |
        |                             |                     |
        |                             v                     |
        |                       [ TRANSMIT ]                |
        |                       (Send OK\r\n)               |
        |                             |                     |
        └─────────────────────────────┘                     |
                                                            |
                                                            v
                                                  [ FACTORY_RESET ]
                                                   (Assert factory_rst)
                                                            |
                                                            v
                                                      [ STARTUP ]
                                                 (Retransmit banner)
                                                            |
                                                            v
                                                       [ TRANSMIT ]
                                                       (Send OK\r\n)
                                                            |
                                                            └──────────► (return to IDLE)
```

### LED Diagnostic and Heartbeat Behavior

The iCE40-HX8K Breakout Board provides five user-accessible LEDs (D1–D5). All five are used in this implementation:

| LED | Function | Implementation | Timing |
|-----|----------|----------------|--------|
| D1  | Heartbeat | 23-bit free-running counter, toggles at `HEARTBEAT_MAX_VAL` (derived from `CLK_FREQ / 2 - 1`) | ~1 Hz toggle (~0.5 s half-period at 12 MHz) |
| D2  | RX activity | 21-bit monostable counter, retriggered on each `rx_valid` pulse | ~100 ms pulse per received byte |
| D3  | TX activity | 21-bit monostable counter, retriggered on each `tx_start` pulse | ~100 ms pulse per transmitted byte |
| D4  | Command mode | Combinational output from `fsm_controller.cmd_mode`; HIGH during CMD_OPCODE, CMD_ARG, CMD_EXEC, CMD_RESP | Level-driven (on while command active) |
| D5  | Error indicator | 22-bit monostable counter, triggered on `error_led` from FSM | ~200 ms pulse on error |

The heartbeat is implemented using a parameterized free-running counter:

```verilog
reg [22:0] heartbeat_cnt = 23'd0;
reg        heartbeat_led = 1'b0;

always @(posedge clk) begin
    if (heartbeat_cnt == HEARTBEAT_MAX_VAL) begin
        heartbeat_cnt <= 23'd0;
        heartbeat_led <= ~heartbeat_led;
    end else begin
        heartbeat_cnt <= heartbeat_cnt + 23'd1;
    end
end

assign led_d1 = heartbeat_led;
```

The monostable LEDs (D2, D3, D5) use a similar pattern: on the trigger event, a down-counter is loaded with a fixed value (e.g., `21'd1_199_999` for ~100 ms at 12 MHz); the LED output stays HIGH while the counter is non-zero.

All LED counters reside in `enigma_top` (not in sub-modules). Total estimated LC usage for LED logic: ~88 LCs.

### Summary of Reset Behavior

| Reset Type | Trigger | Scope | Response | FSM Transition | Timing |
|------------|---------|-------|----------|----------------|--------|
| **Power-On (GSR + POR)** | Bitstream load | All registers | Startup banner | `STARTUP_DELAY` → `STARTUP` → `IDLE` | ~83 ms total |
| **External Reset (`ext_rst_n`)** | Pin driven LOW | All registers (equivalent to GSR) | Startup banner | Same as Power-On | Same as Power-On (bypassed on AMD boards) |
| **Grundstellung (`:G`)** | UART command | `current_positions` only | `OK\r\n` | `IDLE` → `RESET_GRUNDSTELLUNG` → `CMD_RESP` → `IDLE` | ~350 µs |
| **Factory Reset (`:F`)** | UART command | All configuration registers | Banner + `OK\r\n` | `IDLE` → `FACTORY_RESET` → `STARTUP` → `CMD_RESP` → `IDLE` | ~1.75 ms |

### Verification Requirements

To validate correct reset behavior, the following test cases must be executed on the synthesized bitstream running on the iCE40-HX8K Breakout Board hardware:

1. **Power-On Test:**
   - Power-cycle the iCE40-HX8K Breakout Board.
   - Verify that the startup banner `ENIGMA I READY\r\n` is received within 100 ms.
   - Verify that the heartbeat LED begins toggling within 1 second.
   - Encrypt the test vector `AAAAA` and verify the output `BDZGO`.

2. **Grundstellung Reset Test:**
   - Configure the machine to a non-default Grundstellung (e.g., `:PBLA`).
   - Encrypt several characters to advance the rotor positions.
   - Issue the `:G` command.
   - Verify the response `OK\r\n`.
   - Verify that the next encrypted character matches the expected output for the configured Grundstellung (not the advanced position).

3. **Factory Reset Test:**
   - Configure the machine with non-default rotor order, ring settings, and plugboard.
   - Issue the `:F` command.
   - Verify that the startup banner is retransmitted.
   - Verify the response `OK\r\n`.
   - Encrypt the test vector `AAAAA` and verify the output `BDZGO` (ground state).

4. **Reset Isolation Test:**
   - Issue the `:G` command and verify that plugboard settings are preserved.
   - Issue the `:F` command and verify that all settings return to defaults.

### Verilog Coding Guidelines for Reset Logic

To ensure portability and correct synthesis with Yosys and nextpnr, the following guidelines must be followed:

1. **Use synchronous reset only.** The iCE40 does not provide asynchronous reset capabilities on all flip-flops. All reset logic must be triggered by the rising edge of the system clock.

2. **Explicitly initialize all registers.** Use inline assignment or `initial` blocks for all configuration and state registers.

3. **Avoid combinational loops in reset paths.** The `factory_rst` signal should be a simple register output from the FSM, not a complex combinational function.

4. **Test reset behavior in simulation.** Use Icarus Verilog or Verilator to simulate power-on and command-triggered resets before synthesizing to hardware.

5. **Document reset dependencies.** Any module that contains configuration registers must clearly document its reset behavior in comments and in the module header.

---

This specification provides a complete and unambiguous definition of the reset and initialization subsystem for the Wehrmacht Enigma I FPGA implementation on the iCE40-HX8K. The combination of hardware GSR initialization, runtime command-based resets, and diagnostic feedback via the startup banner and heartbeat LED ensures that the system is both robust and operator-friendly.

