<!--
  spec_cipher_algorithm.md — Part 1 of 5
  Audience: anyone reasoning about cipher correctness, algorithm logic, or
  cryptographic fidelity (RTL developers, testbench authors, verification agents).

  Sibling documents (do NOT duplicate their content here):
    spec_rtl_modules.md       — Module hierarchy, port definitions, FSM, AMD support
    spec_uart_protocol.md     — UART protocol, command reference, character I/O
    spec_reset_init.md        — Reset mechanisms, power-on sequencing, LED diagnostics
    spec_verification.md      — Timing analysis, test vectors, toolchain, pin assignments
    spec_index.md             — Navigator: one-line description of each spec document
-->

# Technical Specification for FPGA Implementation of the Wehrmacht Enigma I Cipher Machine

The Enigma I cipher machine represents one of the most significant milestones in the history of electromechanical cryptography. Originally developed as a commercial device by Arthur Scherbius in 1918, the machine was adopted and modified by the German military, specifically the Reichswehr and later the Wehrmacht, to provide secure communications for ground forces and the Luftwaffe. The transition from a mechanical artifact to a digital hardware implementation on a Field-Programmable Gate Array (FPGA) requires a deep technical decomposition of its permutation-based logic, mechanical stepping dynamics, and electrical signal routing. This report provides a comprehensive engineering specification for synthesizing the Enigma I architecture on programmable logic hardware. The primary target is the Lattice Semiconductor iCE40-HX8K Breakout Board (ICE40HX8K-B-EVN), with additional support for the AMD/Digilent Arty A7-100T and Nexys A7-100T (Artix-7 XC7A100T). The primary objective is to define a high-efficiency hardware model that replicates the machine's cryptographic properties while adhering to the resource constraints of the target architectures and providing a robust UART-based interface for modern computational interaction.

## Mathematical Logic and Permutation Flow

The Enigma I operates as a polyalphabetic substitution cipher, characterized by a series of nested permutations that change dynamically with every character processed. The machine is fundamentally an electromechanical computer designed to perform a complex, symmetric encryption function. To implement this in an FPGA, one must first abstract the physical components into a coherent mathematical model. The encryption of a single letter can be represented as a composite permutation $E$ acting on a set of 26 elements, typically the Latin alphabet $\Sigma = \{A, B, C, \dots, Z\}$.

### The Circular Signal Path

The signal flow within the Enigma I is a closed-loop circuit. When a key is depressed, electrical current flows from a battery source through a series of components before illuminating a specific bulb on the lampboard. The sequence of transformations is rigorous and must be mirrored exactly in the FPGA's combinational logic. The path follows this specific trajectory:

- **Entry Wheel (Eintrittswalze - ETW):** The signal originates from the keyboard and enters the ETW. In the Wehrmacht Enigma I, the ETW is a static component that maps the alphabetical input (A-Z) to a fixed set of contacts. For the Enigma I, this mapping is an identity permutation ($A \to A, B \to B, \dots$).
- **Plugboard (Steckerbrett):** Before reaching the scrambler unit, the signal passes through the plugboard. This component allows for the reciprocal swapping of pairs of letters. If a cable connects 'A' and 'T', then an 'A' input becomes a 'T' signal, and a 'T' input becomes an 'A' signal. Up to 13 pairs can be swapped, though the German military standardly used 10 pairs.
- **Forward Scrambler Unit (Rotors):** The signal enters the rightmost (fast) rotor, proceeds through the middle rotor, and finally passes through the leftmost (slow) rotor. Each rotor applies a substitution based on its internal wiring and its current rotational position.
- **Reflector (Umkehrwalze - UKW):** At the end of the rotor stack, the signal enters the reflector. The UKW is a non-rotating component that connects pairs of contacts, essentially folding the circuit back on itself. This ensures the machine is self-reciprocal.
- **Reverse Scrambler Unit:** The signal travels backward through the rotors in reverse order: Left, Middle, then Right. In this pass, the signal undergoes the inverse of the permutation applied during the forward pass.
- **Reverse Plugboard:** The signal returns through the plugboard for a final reciprocal swap.
- **Lampboard Output:** Finally, the current illuminates a lamp, revealing the ciphertext character.

This sequence ensures that the encryption $E$ is its own inverse ($E = E^{-1}$), provided the machine's initial state is identical for both processes.

### Reciprocity and the Non-Self-Mapping Constraint

The architectural inclusion of the reflector defines the Enigma's primary cryptographic strength and its most notable weakness. Mathematically, the reflector $U$ is an involution with no fixed points, meaning $U(x) = y$ and $U(y) = x$, but $U(x) \neq x$ for all $x$. Because the signal must travel through the reflector and return through the same series of components, the entire machine acts as an involution. A consequence of this circuit design is that a letter can never be mapped to itself. Pressing 'A' can never illuminate the 'A' lamp. Allied cryptanalysts at Bletchley Park utilized this "no-self-coding" rule as a fundamental "crib," allowing them to discard millions of potential settings where a predicted plaintext letter matched the observed ciphertext letter. In the FPGA implementation, this property is preserved by ensuring that the reflector logic is an accurate mapping of the historical UKW-B wiring.

## The Mechanical Stepping Mechanism and the Double-Step Anomaly

The dynamic nature of the Enigma's polyalphabetic substitution is achieved through the mechanical rotation of its rotors. The stepping mechanism is modeled after a modified odometer, but with specific mechanical eccentricities caused by the interaction of spring-loaded pawls and notches on the rotor index rings.

Each rotor has a notched ring (Ringstellung). The pawl for each rotor rests on the shoulder of the rotor to its right. When a notch rotates under a pawl, the pawl drops in, allowing it to engage the ratchet of the next rotor on the subsequent keypress. While the right rotor (Rotor 1) steps with every keystroke, the middle (Rotor 2) and left (Rotor 3) rotors step conditionally.

The "Double-Stepping Anomaly" is a critical requirement for a faithful digital simulation. It occurs because the pawl for the left rotor can engage the notch of the middle rotor, pushing both the left rotor and the middle rotor simultaneously. When the middle rotor is in its turnover position, it will be advanced by the pawl from its right (the right rotor's pawl) on one keystroke, and then, because its own notch is now under the left rotor's pawl, it will be advanced again on the very next keystroke while the left rotor also advances. This reduces the total possible period of the machine from $26^3 = 17,576$ to $26 \times 25 \times 26 = 16,900$.

## Component Specifications for FPGA Realization

For an engineering specification targeting the iCE40-HX8K, the mechanical data must be translated into synthesizable Verilog arrays. The following tables provide the exact wiring sequences for the Wehrmacht Enigma I, which used a set of five standard rotors and a fixed Reflector B.

### Rotor Wiring and Notch Configurations

The wiring of an Enigma rotor is defined as the mapping from the right-hand contacts to the left-hand contacts when the rotor is in its 'A' position with a ring setting of 'A'.

| Component    | Internal Wiring Substitution String (A→Z) | Turnover Notch |
|--------------|-------------------------------------------|----------------|
| Rotor I      | EKMFLGDQVZNTOWYHXUSPAIBRCJ                | Q              |
| Rotor II     | AJDKSIRUXBLHWTMCQGZNPYFVOE                | E              |
| Rotor III    | BDFHJLCPRTXVZNYEIWGAKMUSQO                | V              |
| Rotor IV     | ESOVPZJAYQUIRHXLNFTGKDCMWB                | J              |
| Rotor V      | VZBRGITYUPSDNHLXAWMJQOFECK                | Z              |
| Reflector B  | YRUHQSLDPXNGOKMIEBFZCWVJAT                | N/A            |
| Entry Wheel  | ABCDEFGHIJKLMNOPQRSTUVWXYZ                | N/A            |

Table 1: Historical wiring and turnover positions for Enigma I.

> **Scope note:** This implementation supports **Reflector B (UKW-B) only**; Reflector C (UKW-C) has been excluded. The five standard Wehrmacht rotors (I–V) are included, of which any three are selected for the left, middle, and right positions.

In the FPGA, these should be stored as constant lookup tables. For efficiency, a forward table and an inverse table should be provided for each rotor to avoid the computational overhead of searching the array during the reverse pass.

### The Plugboard (Steckerbrett) Logical Model

The plugboard provides the most significant increase in the machine's keyspace, adding approximately 150 trillion possible configurations. For an FPGA implementation on the iCE40-HX8K Breakout Board, a simplified logical model is required to manage the 10 pairs of swaps without excessive logic usage.

The most efficient model is a 26-entry 5-bit wide distributed RAM or a large case statement that acts as a lookup table. Upon initialization, the table is set to identity ($f(x) = x$). For each configured plug (e.g., A-J), the values at indices 0 and 9 are swapped ($f(0)=9, f(9)=0$). Since the plugboard is reciprocal, the same table is used for both the input and output stages of the encryption cycle.

### Ring Settings (Ringstellung) and Operational Offsets

The Ringstellung is a static offset applied to the internal wiring relative to the rotor's external position and its turnover notch. While the rotor position (Grundstellung) changes with every step, the Ringstellung is set once during machine setup.

The mathematical offset used for the substitution calculation must account for both variables. If $P$ is the current rotor position ($0-25$) and $R$ is the ring setting ($0-25$), the effective offset $O$ for the rotor's wiring is:

$$O = (P - R + 26) \pmod{26}$$

When the signal enters a rotor at position $i$ ($0-25$), it is shifted by $O$, passed through the substitution table, and then shifted back by $O$. This ensures that the internal wiring of the rotor rotates physically relative to the stationary machine contacts while the turnover notch remains fixed to the alphabet ring.

## Rotor Substitution Algorithm

### 1. Wiring Tables

All indices are 0-based (A=0, B=1, …, Z=25).

#### 1.1 Forward Wiring (pre-computed ROM constants)

| Rotor | Wiring string (index 0→25) | Numeric values |
|-------|---------------------------|----------------|
| I     | EKMFLGDQVZNTOWYHXUSPAIBRCJ | 4,10,12,5,11,6,3,16,21,25,13,19,14,22,24,7,23,20,18,15,0,8,1,17,2,9 |
| II    | AJDKSIRUXBLHWTMCQGZNPYFVOE | 0,9,3,10,18,8,17,20,23,1,11,7,22,19,12,2,16,6,25,13,15,24,5,21,14,4 |
| III   | BDFHJLCPRTXVZNYEIWGAKMUSQO | 1,3,5,7,9,11,2,15,17,19,23,21,25,13,24,4,8,22,6,0,10,12,20,18,16,14 |
| IV    | ESOVPZJAYQUIRHXLNFTGKDCMWB | 4,18,14,21,15,25,9,0,24,16,20,8,17,7,23,11,13,5,19,6,10,3,2,12,22,1 |
| V     | VZBRGITYUPSDNHLXAWMJQOFECK | 21,25,1,17,6,8,19,24,20,15,18,3,13,7,11,23,0,22,12,9,16,14,5,4,2,10 |
| Refl B | YRUHQSLDPXNGOKMIEBFZCWVJAT | 24,17,20,7,16,18,11,3,15,23,13,6,14,10,12,8,4,1,5,25,2,22,21,9,0,19 |
| ETW   | ABCDEFGHIJKLMNOPQRSTUVWXYZ | 0,1,2,…,25 (identity) |

#### 1.2 Inverse Wiring (pre-computed ROM constants)

The inverse table `W_inv` satisfies `W_inv[W[x]] = x`. It is looked up at runtime — **no searching is performed**.

| Rotor | Inverse wiring string | Numeric values |
|-------|-----------------------|----------------|
| I     | UWYGADFPVZBECKMTHXSLRINQOJ | 20,22,24,6,0,3,5,15,21,25,1,4,2,10,12,19,7,23,18,11,17,8,13,16,14,9 |
| II    | AJPCZWRLFBDKOTYUQGENHXMIVS | 0,9,15,2,25,22,17,11,5,1,3,10,14,19,24,20,16,6,4,13,7,23,12,8,21,18 |
| III   | TAGBPCSDQEUFVNZHYIXJWLRKOM | 19,0,6,1,15,2,18,3,16,4,20,5,21,13,25,7,24,8,23,9,22,11,17,10,14,12 |
| IV    | HZWVARTNLGUPXQCEJMBSKDYOIF | 7,25,22,21,0,17,19,13,11,6,20,15,23,16,2,4,9,12,1,18,10,3,24,14,8,5 |
| V     | QCYLXWENFTZOSMVJUDKGIARPHB | 16,2,24,11,23,22,4,13,5,19,25,14,18,12,21,9,20,3,10,6,8,0,17,15,7,1 |

> **Note:** The reflector (B) is self-reciprocal: `W_refl[W_refl[x]] = x`. Its inverse table is identical to its forward table.

> **Implementation note:** Store all tables as Verilog `parameter` arrays or `case` statements in ROM modules. No runtime inversion is ever performed.

---

### 2. Forward-Pass Substitution Algorithm (single rotor)

**Inputs:**
- `s`  — 5-bit signal index entering this rotor's left face (0–25)
- `P`  — 5-bit rotor position (letter visible in window, 0=A … 25=Z)
- `R`  — 5-bit ring setting (Ringstellung, 0=A … 25=Z)

**Output:**
- `out` — 5-bit substituted signal index leaving this rotor's right face (0–25)

**Algorithm:**

```
// Step 1: Compute wiring offset
offset = (P - R + 26) mod 26          // 5-bit, always in [0,25]

// Step 2: Shift signal into core coordinate space
shifted_in = (s + offset) mod 26      // 5-bit

// Step 3: Table lookup in forward wiring ROM
out_core = W_forward[shifted_in]      // 5-bit, from pre-computed ROM

// Step 4: Shift signal back to alphabetic coordinate space
out = (out_core - offset + 26) mod 26 // 5-bit
```

**Verilog mapping:**
- All arithmetic is mod-26 and fits in 5 bits.
- `(a - b + 26) mod 26` is implemented as `(a + 26 - b) % 26` using a 6-bit intermediate to avoid underflow before the modulo.
- The ROM lookup is a 26-entry `case` block or an initialised register array.

---

### 3. Inverse-Pass Substitution Algorithm (single rotor)

The inverse pass uses the pre-computed `W_inv` table. The offset arithmetic is **identical** to the forward pass.

**Inputs/Output:** same types as forward pass.

```
// Step 1: Compute wiring offset (same formula)
offset = (P - R + 26) mod 26

// Step 2: Shift signal into core coordinate space
shifted_in = (s + offset) mod 26

// Step 3: Table lookup in INVERSE wiring ROM
out_core = W_inv[shifted_in]          // 5-bit, from pre-computed inverse ROM

// Step 4: Shift signal back
out = (out_core - offset + 26) mod 26
```

---

### 4. Full Cipher Path Chain

Notation: `fwd_R(s)`, `fwd_M(s)`, `fwd_L(s)` = forward pass through right/middle/left rotor; `inv_L(s)`, `inv_M(s)`, `inv_R(s)` = inverse pass; `refl(s)` = reflector substitution; `plug(s)` = plugboard (symmetric swap or identity).

The signal flows in this exact order:

```
1.  s0  = plaintext_index                        // input letter (0-25)
2.  s1  = plug(s0)                               // plugboard (pre-encryption)
3.  s2  = fwd_R(s1, P_R, R_R)                   // right rotor, forward
4.  s3  = fwd_M(s2, P_M, R_M)                   // middle rotor, forward
5.  s4  = fwd_L(s3, P_L, R_L)                   // left rotor, forward
6.  s5  = refl(s4)                               // reflector (no offset, fixed)
7.  s6  = inv_L(s5, P_L, R_L)                   // left rotor, inverse
8.  s7  = inv_M(s6, P_M, R_M)                   // middle rotor, inverse
9.  s8  = inv_R(s7, P_R, R_R)                   // right rotor, inverse
10. s9  = plug(s8)                               // plugboard (post-decryption, same swap)
11. out = s9                                     // ciphertext/plaintext index
```

**ETW:** The ETW (entry wheel) is the identity mapping and requires no hardware — it is implicit in the signal entering the right rotor at step 3.

**Reflector:** The reflector has no position or ring setting. It is a fixed 26-entry ROM lookup with no offset arithmetic:
```
s5 = W_refl[s4]
```

**Plugboard:** Each configured pair `(a, b)` swaps `a↔b`; unconfigured letters pass through. Implemented as a 26-entry case block.

---

### 5. Turnover Detection and Stepping

#### 5.1 Physical model

The notch is a physical cutout on the **alphabet ring** (Ringscheibe). The observation window shows the alphabet ring letter currently facing the window. The ring setting shifts the **wiring core** relative to the alphabet ring, but the notch remains fixed to the ring.

**Consequence:** The window always shows the alphabet ring letter. The notch position is therefore specified directly as an alphabet ring letter. Ring setting has **no effect** on notch detection.

#### 5.2 Notch positions (window letter that causes turnover of the next rotor)

| Rotor | Notch letter | Notch index |
|-------|-------------|-------------|
| I     | Q           | 16          |
| II    | E           | 4           |
| III   | V           | 21          |
| IV    | J           | 9           |
| V     | Z           | 25          |

#### 5.3 Turnover check formula

```
// Turnover of rotor X occurs when rotor X's position equals its notch index.
// Ring setting R is NOT used in this comparison.
turnover_R = (P_R == NOTCH_R)   // right rotor at notch → middle steps
turnover_M = (P_M == NOTCH_M)   // middle rotor at notch → left steps (+ double-step)
```

#### 5.4 Stepping logic (per keypress, before encryption)

```
// Evaluate notch conditions BEFORE advancing any rotor.
at_notch_R = (P_R == NOTCH_R)
at_notch_M = (P_M == NOTCH_M)

// Apply steps:
if (at_notch_M) P_L = (P_L + 1) mod 26   // left rotor steps
if (at_notch_M) P_M = (P_M + 1) mod 26   // middle rotor double-steps
if (at_notch_R) P_M = (P_M + 1) mod 26   // middle rotor steps when right at notch
P_R = (P_R + 1) mod 26                    // right rotor always steps
```

> **Critical:** The `at_notch_M` flag is sampled before `P_M` is modified. This correctly implements the Enigma double-stepping anomaly.

---

### 6. Worked Examples

#### Example 1 — Encrypt 'A' through Rotor I: P = 1 (B), R = 0 (A)

| Step | Operation | Value |
|------|-----------|-------|
| Input | signal `s` | 0 (A) |
| 1 | `offset = (P − R + 26) mod 26 = (1 − 0 + 26) mod 26` | **1** |
| 2 | `shifted_in = (s + offset) mod 26 = (0 + 1) mod 26` | **1 (B)** |
| 3 | `out_core = W_I[1]` (Rotor I wiring: index 1 → K) | **10 (K)** |
| 4 | `out = (out_core − offset + 26) mod 26 = (10 − 1 + 26) mod 26` | **9 (J)** |

**Result: A → J**

Inverse verification (J back through same rotor, same P and R):

| Step | Operation | Value |
|------|-----------|-------|
| Input | signal `s` | 9 (J) |
| 1 | `offset = 1` | 1 |
| 2 | `shifted_in = (9 + 1) mod 26` | **10 (K)** |
| 3 | `out_core = W_I_inv[10]` (inverse table: index 10 → B=1) | **1 (B)** |
| 4 | `out = (1 − 1 + 26) mod 26` | **0 (A)** ✓ |

---

#### Example 2 — Encrypt 'A' through Rotor I: P = 1 (B), R = 1 (B)

| Step | Operation | Value |
|------|-----------|-------|
| Input | signal `s` | 0 (A) |
| 1 | `offset = (P − R + 26) mod 26 = (1 − 1 + 26) mod 26` | **0** |
| 2 | `shifted_in = (0 + 0) mod 26` | **0 (A)** |
| 3 | `out_core = W_I[0]` (Rotor I wiring: index 0 → E) | **4 (E)** |
| 4 | `out = (4 − 0 + 26) mod 26` | **4 (E)** |

**Result: A → E**

**Interpretation:** With R=1, the ring setting exactly cancels the position offset (both are 1). The rotor behaves as if it were at position 0 (A) with ring setting 0, so the raw wiring is applied directly: W_I[0] = E.

Inverse verification (E back through same rotor, same P and R):

| Step | Operation | Value |
|------|-----------|-------|
| Input | signal `s` | 4 (E) |
| 1 | `offset = 0` | 0 |
| 2 | `shifted_in = (4 + 0) mod 26` | **4 (E)** |
| 3 | `out_core = W_I_inv[4]` (inverse table: index 4 → A=0) | **0 (A)** |
| 4 | `out = (0 − 0 + 26) mod 26` | **0 (A)** ✓ |

---

### 7. Summary: Key Design Rules for Verilog

1. **One offset formula, used everywhere:** `offset = (P - R + 26) % 26`. Apply it in both forward and inverse passes, for all five rotors.
2. **Reflector:** fixed 26-entry ROM, no offset arithmetic, no ring setting, no position.
3. **Inverse table:** pre-computed constant ROM. Never search the forward table at runtime.
4. **Turnover:** compare `P` directly to the notch index. Ring setting `R` plays **no role** in turnover detection.
5. **Stepping:** evaluate all notch conditions first, then update positions. Order within the update block: left, then middle (double-step), then middle (normal), then right.
6. **Modular arithmetic:** all values stay in [0, 25]. Use 6-bit intermediates before the `% 26` reduction to avoid underflow.

