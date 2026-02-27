<!--
  spec_uart_protocol.md — Part 3 of 5
  Audience: anyone implementing or testing the host↔FPGA interface — test script
  authors, integration agents, or RTL developers implementing the UART FSM.
  Contains: UART parameters, the full 54-command configuration protocol, response
  format, worked examples, character I/O filtering rules, and TX overflow behavior.

  Sibling documents (do NOT duplicate their content here):
    spec_cipher_algorithm.md  — Cipher math, wiring tables, substitution algorithm
    spec_rtl_modules.md       — Module hierarchy, port definitions, FSM, AMD support
    spec_reset_init.md        — Reset mechanisms, power-on sequencing, LED diagnostics
    spec_verification.md      — Timing analysis, test vectors, toolchain, pin assignments
    spec_index.md             — Navigator: one-line description of each spec document
-->

## UART Configuration Protocol

### Overview

All runtime configuration of the FPGA Enigma is performed over the UART interface at **115200 baud, 8N1** via the FTDI FT2232HL USB-to-serial bridge on the iCE40-HX8K Breakout Board. The interface is designed to be **human-operable from any serial terminal** (e.g., `minicom`, `screen`, PuTTY) with no binary framing or host-side tooling required.

The FSM distinguishes command input from normal encipherment traffic by the **`:` prefix character** (ASCII 0x3A). Because `:` is not in the set A–Z / a–z, it cannot appear in normal plaintext or ciphertext and unambiguously signals the start of a configuration command. All other printable alphabetic characters received while the machine is in the IDLE state are enciphered normally and the ciphertext character is echoed back.

---

### Power-On Default State

The machine powers up in the following state. This is also the state restored by a Factory Reset (`:F`).

| Parameter | Default Value |
|---|---|
| Reflector (UKW) | B |
| Rotor Order (L–M–R) | I – II – III |
| Ring Settings (Ringstellung) | A – A – A (0 – 0 – 0) |
| Initial Positions (Grundstellung) | A – A – A (0 – 0 – 0) |
| Current Rotor Positions | A – A – A |
| Plugboard (Steckerbrett) | No pairs (identity) |

---

### FSM Data-vs-Command Distinction

The top-level controller FSM has two primary modes:

```
┌──────────────────────────────────────────────────────┐
│                     IDLE state                       │
│  Incoming byte:                                      │
│    A–Z / a–z  → encipher, echo ciphertext letter    │
│    ':'  (0x3A) → transition to CMD_OPCODE           │
│    all others → silently ignored                     │
└──────────────────────────────────────────────────────┘
              │ ':'
              ▼
┌──────────────────────────────────────────────────────┐
│                  CMD_OPCODE state                    │
│  Wait for next rx_valid byte (the opcode).           │
│  Latch opcode, determine arg count, then route:     │
│    R/N/P/S/U → CMD_ARG (with arg_count set)         │
│    ?         → CMD_EXEC (zero-arg)                  │
│    G         → RESET_GRUNDSTELLUNG (zero-arg)       │
│    F         → FACTORY_RESET (zero-arg)             │
│    unknown   → send ERR, return to IDLE             │
│  Timeout (3 seconds): return to IDLE                  │
└──────────────────────────────────────────────────────┘
              │ opcode byte received
              ▼
┌──────────────────────────────────────────────────────┐
│                    CMD_ARG state                     │
│  Collect arg bytes into shift register               │
│  → CMD_EXEC on receipt of CR (0x0D) or LF (0x0A)   │
│  ':' received mid-arg → abort, send ERR, return to  │
│                          IDLE                        │
└──────────────────────────────────────────────────────┘
              │ CR / LF
              ▼
┌──────────────────────────────────────────────────────┐
│                    CMD_EXEC state                    │
│  Validate arguments; drive cfg_wr_* write enables   │
│  → CMD_RESP                                         │
└──────────────────────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────┐
│                    CMD_RESP state                    │
│  Transmit OK\r\n, ERR\r\n, or multi-line status     │
│  → return to IDLE                                   │
└──────────────────────────────────────────────────────┘
```

**Timeout:** A 3-second timeout applies from the moment the FSM enters CMD_OPCODE or CMD_ARG. If no valid byte or CR/LF is received within that window, the partial command is silently aborted and the FSM returns to IDLE. This prevents a stray `:` from locking up the interface while remaining comfortable for human typing in a serial terminal.

**Case normalization:** The FSM normalizes incoming argument letters to uppercase by masking bit 5 (`arg & 8'h5F`). Command letters are also matched case-insensitively.

---

### Command Reference Table

Commands with arguments follow the format: **`:` `<CMD>` `<ARGS>` `<CR>`**

Arguments are **fixed-length** per command — no spaces, no delimiters. CR (0x0D) terminates commands that take arguments; LF (0x0A) is also accepted as a synonym. **Zero-argument commands** (`:G`, `:F`, `:?`) execute immediately when the opcode byte is received — no CR/LF terminator is required or expected. Any trailing CR/LF after a zero-argument command will be processed normally (echoed in DATA MODE per the Input Byte Behavior Table).

| Command | Syntax | Args | Arg Format | Description |
|---|---|---|---|---|
| Set Reflector | `:UB` | 1 | Letter (`B` only) | Confirm UKW-B (only supported reflector; always returns `OK`) |
| Set Rotor Order | `:RLMR` | 3 | Digits `1`–`5` | Left, Middle, Right rotor selection |
| Set Ring Settings | `:NXYZ` | 3 | Letters `A`–`Z` | Ringstellung for L, M, R rotors |
| Set Initial Positions | `:PXYZ` | 3 | Letters `A`–`Z` | Grundstellung for L, M, R rotors |
| Add Plugboard Pair | `:SXY` | 2 | Letters `A`–`Z`, X ≠ Y | Wire plugboard pair X↔Y |
| Clear Plugboard | `:S--` | 2 | Literal `--` | Remove all plugboard pairs |
| Reset to Grundstellung | `:G` | 0 | — | Reload initial positions, begin new message |
| Factory Reset | `:F` | 0 | — | Restore all power-on defaults; retransmit startup banner before `OK\r\n` |
| Status Query | `:?` | 0 | — | Dump current machine configuration |

---

### Command Descriptions

#### `:UB` — Confirm Reflector (UKW-B)

This implementation supports UKW-B only. Sending `:UB` is accepted and returns `OK` as a no-op confirmation. Any other reflector letter (e.g., `:UC`) returns `ERR`.

- **Syntax:** `:UB` followed by CR
- **Valid values:** `B` only
- **Effect:** No-op; UKW-B is always active and cannot be changed at runtime.
- **Error conditions:** Any character other than `B` → `ERR`

```
:UB↵
OK
```

---

#### `:RLMR` — Set Rotor Order (Walzenlage)

Sets which physical rotor occupies each of the three positions. L = leftmost (slow), M = middle, R = rightmost (fast).

- **Syntax:** `:R` followed by exactly **3 digits**, each `1`–`5`, then CR
- **Valid values per position:** `1` (Rotor I), `2` (II), `3` (III), `4` (IV), `5` (V)
- **Constraint:** All three digits must be distinct (the same rotor cannot appear twice)
- **Effect:** Updates rotor selection. Resets current rotor positions to the currently configured Grundstellung. Does **not** alter ring settings or plugboard.
- **Error conditions:** Any digit outside `1`–`5`, or duplicate rotor → `ERR`

```
:R123↵
OK
```

---

#### `:NXYZ` — Set Ring Settings (Ringstellung)

Sets the ring offset for each rotor. X applies to the left rotor, Y to the middle, Z to the right.

- **Syntax:** `:N` followed by exactly **3 uppercase letters** `A`–`Z` (or lowercase; normalized), then CR
- **Valid values:** `A` (=0) through `Z` (=25)
- **Effect:** Updates ring settings. The new offsets take effect for all subsequent encipherments. Does not change current rotor positions.
- **Error conditions:** Any character outside `A`–`Z` (after normalization) → `ERR`

```
:NBUL↵
OK
```

---

#### `:PXYZ` — Set Initial Positions (Grundstellung)

Sets the three-letter indicator that defines the starting rotor positions for a new message. X = left, Y = middle, Z = right.

- **Syntax:** `:P` followed by exactly **3 uppercase letters** `A`–`Z`, then CR
- **Valid values:** `A` (=0) through `Z` (=25)
- **Effect:** Stores the Grundstellung. Does **not** immediately move the rotors — issue `:G` to apply the positions to the live machine. (This differs from `:R`, which auto-reloads positions. The asymmetry is intentional: changing rotor *order* invalidates the current stepped positions and must reload immediately, whereas updating the *starting position* is a configuration step that the operator applies explicitly with `:G` when ready to begin a new message.)
- **Error conditions:** Any character outside `A`–`Z` → `ERR`

```
:PBLA↵
OK
```

---

#### `:SXY` — Add Plugboard Pair (Steckerbrett)

Wires one reciprocal plugboard connection: X↔Y.

- **Syntax:** `:S` followed by exactly **2 uppercase letters** `A`–`Z`, then CR
- **Valid values:** Any two distinct letters not already wired to another letter
- **Constraint:** Maximum 12 pairs (the historical Enigma supported up to 13, but this implementation limits to 12; the German military standard was 10 pairs). Letters already part of an existing pair cannot be re-wired without first clearing the board.
- **Effect:** Adds the pair immediately. Both directions are wired (X→Y and Y→X).
- **Error conditions:** X == Y, either letter already wired, board full (12 pairs) → `ERR`

```
:SAV↵
OK
:SBS↵
OK
```

---

#### `:S--` — Clear All Plugboard Pairs

Removes all plugboard wiring, restoring identity (no swaps).

- **Syntax:** `:S--` (two hyphen/dash characters, ASCII 0x2D), then CR
- **Effect:** Plugboard is immediately cleared to identity.
- **Error conditions:** None (always succeeds).

```
:S--↵
OK
```

---

#### `:G` — Reset to Grundstellung

Reloads the stored initial positions into the live rotor position registers. Use this to begin enciphering a new message with the same machine settings.

- **Syntax:** `:G` (no arguments; executes immediately on the opcode byte — no CR/LF terminator required)
- **Effect:** Current rotor positions ← stored Grundstellung. All other settings (rotor order, rings, plugboard) are unchanged.
- **Error conditions:** None (always succeeds).

```
:G
OK
```

---

#### `:F` — Factory Reset

Restores the complete machine to power-on defaults (see **Power-On Default State** above).

- **Syntax:** `:F` (no arguments; executes immediately on the opcode byte — no CR/LF terminator required)
- **Effect:** UKW-B, rotors I–II–III, rings AAA, positions AAA, plugboard cleared. Current rotor positions reset to AAA. The startup banner (`ENIGMA I READY\r\n`) is retransmitted before the `OK\r\n` response, providing unambiguous confirmation that a full reset occurred.
- **Error conditions:** None (always succeeds).

```
:F
ENIGMA I READY
OK
```

---

#### `:?` — Status Query

Dumps the current machine configuration as a human-readable multi-line response. The live rotor positions (which may differ from Grundstellung after encipherment) are shown separately.

- **Syntax:** `:?` (no arguments; executes immediately on the opcode byte — no CR/LF terminator required)
- **Response format:**

```
UKW:B
ROT:1 2 3
RNG:A A A
GRD:A A A
POS:A A A
PLG:AV BS CG DL FU HZ IN KM OW RX
OK
```

  - `UKW` — active reflector
  - `ROT` — rotor order (left middle right), as digits 1–5
  - `RNG` — ring settings (left middle right), as letters A–Z
  - `GRD` — stored Grundstellung (left middle right)
  - `POS` — current live rotor positions (left middle right)
  - `PLG` — active plugboard pairs, space-separated; `PLG:` (empty) if none

**Plugboard pair serialization algorithm (`response_generator` module):**

The `response_generator` sub-module (see **Section 7a**) reconstructs the active pairs from the 26-entry `plug_map` by iterating indices 0–25. A 5-bit scan counter `plug_scan` drives the iteration:

```
plug_scan = 0
first_pair = true
transmit "PLG:"
while (plug_scan <= 25):
    partner = plug_map[plug_scan]
    if (partner > plug_scan):          // paired, and emit each pair only once
        if (!first_pair):
            transmit ' '               // space separator between pairs
        transmit (plug_scan + 'A')     // first letter
        transmit (partner + 'A')       // second letter
        first_pair = false
    plug_scan = plug_scan + 1
transmit CR, LF
```

This produces pairs in alphabetical order by the lower letter (e.g., `AV BS CG ...`). Self-mapped entries (`plug_map[i] == i`) are skipped. The condition `partner > plug_scan` ensures each reciprocal pair is emitted exactly once. The scan requires up to 26 iterations; at each step the `response_generator` reads one entry from `plug_map` combinationally, decides whether to emit, and if so transmits 2–3 bytes (space + two letters) via the UART before advancing `plug_scan`.

> **Implementation note:** The `response_generator` does not buffer the entire PLG line. It transmits character-by-character, waiting for `tx_busy` to clear between each byte. The scan counter, `first_pair` flag, and `plg_substate` register are part of the `response_generator` module's internal state (see **Section 7a**).

---

### Response Format

Every command produces exactly one of:

| Response | Meaning |
|---|---|
| `OK\r\n` | Command accepted and applied |
| `ERR\r\n` | Command rejected (invalid argument, constraint violation, etc.) |

Multi-line responses (`:?` status query) always end with `OK\r\n` as the final line.

No partial acknowledgment is sent — the response is only emitted after the full command (including CR/LF terminator) is received and processed.

---

### Argument Encoding Summary

| Context | Encoding |
|---|---|
| Rotor selection | ASCII digit `1`–`5` (single character per rotor) |
| Rotor positions / ring settings | ASCII letter `A`–`Z` (single character = value 0–25) |
| Plugboard pair | Two ASCII letters, no separator |
| Plugboard clear | Two literal hyphen characters `--` |
| No-argument commands (`:G`, `:F`, `:?`) | Executes immediately on the opcode byte; no CR/LF terminator required |

---

### Complete Example Configuration Session

The following session configures the machine for the Case 2 historical test vector (Barbarossa, 7 July 1941: Rotors II–IV–V, Rings B–U–L, Plugboard AV BS CG DL FU HZ IN KM OW RX, Position BLA) and then enciphers a message:

```
# --- Factory reset to known state ---
:F↵
ENIGMA I READY
OK

# --- Set reflector (UKW-B is default but shown explicitly) ---
:UB↵
OK

# --- Set rotor order: Left=II, Middle=IV, Right=V ---
:R245↵
OK

# --- Set ring settings: B U L ---
:NBUL↵
OK

# --- Set Grundstellung: B L A ---
:PBLA↵
OK

# --- Configure plugboard (10 pairs) ---
:SAV↵
OK
:SBS↵
OK
:SCG↵
OK
:SDL↵
OK
:SFU↵
OK
:SHZ↵
OK
:SIN↵
OK
:SKM↵
OK
:SOW↵
OK
:SRX↵
OK

# --- Verify configuration ---
:?↵
UKW:B
ROT:2 4 5
RNG:B U L
GRD:B L A
POS:B L A
PLG:AV BS CG DL FU HZ IN KM OW RX
OK

# --- Begin message (positions are now live at BLA) ---
# Typing 'E' → machine steps rotors, enciphers, echoes ciphertext
EDPUD
AUFKL

# --- Reset to start of next message with same Grundstellung ---
:G↵
OK

# --- Clear plugboard for a fresh configuration ---
:S--↵
OK
```

> **Terminal note:** The iCE40-HX8K Breakout Board echoes the ciphertext character (not the plaintext). In the example above, `EDPUD` was typed and `AUFKL` was echoed back. Configure your terminal for **no local echo** so that only the ciphertext response is displayed.

---

### FSM Implementation Notes for Verilog

The command parser is integrated into the unified 14-state FSM defined in **Section 7 (`fsm_controller`)**. See that section for the complete state table with encodings and transition rules.

A 3-bit counter (`arg_count`) tracks how many argument bytes remain. Its load value is set in the CMD_OPCODE state upon receipt of the opcode byte:

```verilog
// Executed in CMD_OPCODE state on receipt of the opcode byte following ':'.
// cmd_opcode is latched from the received byte.
// arg_count is loaded from this table; FSM transitions per the routing rules.
case (cmd_opcode & 8'h5F)  // normalize to uppercase
    "R": arg_count <= 3;
    "N": arg_count <= 3;
    "P": arg_count <= 3;
    "S": arg_count <= 2;
    "U": arg_count <= 1;
    "G": arg_count <= 0;  // no args; go directly to RESET_GRUNDSTELLUNG
    "F": arg_count <= 0;  // no args; go directly to FACTORY_RESET
    "?": arg_count <= 0;  // no args; go directly to CMD_EXEC
    default: /* send ERR, return to IDLE */
endcase
```

Argument bytes are shifted into a fixed 3-byte register (`arg_buf[23:0]`). The command opcode is latched in a separate register (`cmd_reg[7:0]`). Validation and register updates all occur in a single clock cycle in `CMD_EXEC`, keeping the state machine compact and easily fittable within the iCE40-HX8K's 7,680 logic cells.

The estimated additional logic cost for the full command parser (all states, argument shift register, plugboard pair storage for up to 13 pairs as a 26×5-bit table, and UART response generation) is approximately **80–120 logic cells**, well within the available headroom after the cipher core and UART transceiver are placed.

## Character Handling and I/O Filtering

The FSM operates in one of two modes: **DATA MODE** (normal encipherment) and **COMMAND MODE** (accumulating a command following a `:` prefix). The mode determines which column of the table below applies to each received byte.

---

### ASCII-to-Index Conversion

All letter bytes are reduced to a cipher index in the range 0–25 before encipherment:

| Step | Formula | Example |
|------|---------|---------|
| Normalize lowercase to uppercase | `byte & 0x5F` | `'a'` (0x61) → `'A'` (0x41) |
| Convert uppercase to index | `byte - 0x41` | `'A'` (0x41) → 0, `'Z'` (0x5A) → 25 |

Combined single expression for a lowercase or uppercase letter byte `b`:

```
index = (b & 0x5F) - 0x41        // valid only when b is 0x41–0x5A or 0x61–0x7A
```

Ciphertext indices are converted back to uppercase ASCII for transmission:

```
output_byte = cipher_index + 0x41  // always 0x41–0x5A (A–Z)
```

---

### Input Byte Behavior Table

> **Note:** The FSM mode (DATA vs COMMAND) determines which row applies. A byte is interpreted according to the current mode at the instant it is received.

| Input byte class | Hex range / value | DATA MODE behavior | COMMAND MODE behavior |
|---|---|---|---|
| Uppercase letters A–Z | 0x41–0x5A | Convert to index, encipher, transmit uppercase result | Accumulate as command argument letter |
| Lowercase letters a–z | 0x61–0x7A | Normalize via `byte & 0x5F`, encipher, transmit uppercase result | Normalize via `byte & 0x5F`, accumulate as command argument letter |
| Colon `:` | 0x3A | Enter COMMAND MODE; begin accumulating command bytes | Restart command: discard current partial command, begin new command accumulation |
| CR | 0x0D | Silently discard | Terminate command; trigger parsing and execution; return to DATA MODE |
| LF | 0x0A | Silently discard | Terminate command; trigger parsing and execution; return to DATA MODE |
| Space | 0x20 | Silently discard | Silently discard; do not abort command |
| Backspace (BS) | 0x08 | Silently discard | Silently discard; do not abort command |
| Digits 0–9 | 0x30–0x39 | Silently discard; not valid plaintext in data mode | Accumulate as numeric argument byte (e.g., rotor selection in `:R245`) |
| Hyphen `-` | 0x2D | Silently discard | Accumulate as literal argument byte (used in `:S--` clear-plugboard command) |
| Other C0 control chars | 0x00–0x07, 0x09–0x0C, 0x0E–0x1F | Silently discard | Silently discard; do not abort command |
| DEL and high bytes | 0x7F–0xFF | Silently discard | Silently discard; do not abort command |
| Other punctuation / symbols | 0x21–0x2C, 0x2E–0x39 (non-letter, non-digit, non-special) | Silently discard | Silently discard; do not abort command |

**COMMAND MODE timeout:** If no byte is received within 3 seconds, the partial command is discarded and the FSM returns to DATA MODE.

---

### Output Encoding Rules

1. **Ciphertext characters** are always transmitted as uppercase ASCII (0x41–0x5A, A–Z). No CR or LF is appended; there is a strict one-to-one correspondence between plaintext input letters and ciphertext output letters.
2. **Non-letter bytes in DATA MODE** (CR, LF, space, backspace, digits, punctuation, control characters) are silently discarded — no echo, no encipherment. Only alphabetic characters (A–Z, a–z) produce output.
3. **Command responses** are transmitted as fixed ASCII strings followed by CR+LF:
   - Success: `OK\r\n` (0x4F 0x4B 0x0D 0x0A)
   - Failure (unknown command or invalid arguments): `ERR\r\n` (0x45 0x52 0x52 0x0D 0x0A)

---

### TX Buffer Overflow Specification

The UART transmitter includes a 1-character (1-byte) output queue beyond the shift register currently being transmitted:

- If a new output byte is generated while the TX shift register is busy **and** the 1-byte queue is empty, the new byte is placed in the queue and transmitted immediately after the current byte completes.
- If a new output byte is generated while both the TX shift register **and** the 1-byte queue are occupied, the new byte is **silently dropped**.
- At 115200 baud (8N1, 10 bit-times per byte), each byte takes approximately 87 µs to transmit. Because the Enigma step-and-encipher operation completes well within this window, back-to-back overflow is extremely rare in normal operation.

