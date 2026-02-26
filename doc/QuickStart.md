# FPGA Enigma I — Quick Start Guide

## Requirements

- iCE40-HX8K Breakout Board (ICE40HX8K-B-EVN) programmed with the Enigma bitstream
- Serial terminal (minicom, screen, PuTTY, etc.)
- Connection: **115200 baud, 8N1, no local echo**

Example using minicom:

```
minicom -D /dev/ttyUSB1 -b 115200
```

On power-up you should see:

```
ENIGMA I READY
```

## Basic Operation

Type any letter and the machine immediately returns the enciphered letter. The rotors advance with every keypress, exactly like the original Wehrmacht Enigma I.

Commands start with `:` and configure the machine. Letters outside a command are enciphered.

## Round-Trip Example: Encrypting and Decrypting "HELLOWORLD"

The Enigma cannot process spaces — just like the original machine, only A–Z are valid. We'll encrypt `HELLOWORLD` as one block.

### 1. Configure the machine

```
:F
```
```
ENIGMA I READY
OK
```

Set rotors III-I-II, rings D-O-G, Grundstellung to C-A-T, and wire three plugboard pairs:

```
:R312
OK
:NDOG
OK
:PCAT
OK
:SHX
OK
:SLQ
OK
:SOB
OK
```

### 2. Load the starting position and encrypt

```
:G
OK
```

Now type the plaintext. Each letter you type returns one ciphertext letter:

```
HELLOWORLD
```

The machine responds (your terminal shows only the output):

```
DOIENGMSNC
```

### 3. Decrypt — reset and feed the ciphertext back

The Enigma is self-reciprocal: encrypting the ciphertext with the same settings recovers the plaintext. Reset the rotors to the same starting position:

```
:G
OK
```

Now type the ciphertext:

```
DOIENGMSNC
```

The machine responds:

```
HELLOWORLD
```

### 4. Verify configuration at any time

```
:?
```

```
UKW:B
ROT:3 1 2
RNG:D O G
GRD:C A T
POS:C A T
PLG:HX LQ BO
OK
```

## Command Summary

| Command | Example | Effect |
|---------|---------|--------|
| `:F` | `:F` | Factory reset (rotors I-II-III, rings AAA, pos AAA, no plugboard) |
| `:R` | `:R312` | Set rotor order (left-middle-right, digits 1–5) |
| `:N` | `:NDOG` | Set ring settings (three letters A–Z) |
| `:P` | `:PCAT` | Set Grundstellung / initial positions (three letters A–Z) |
| `:G` | `:G` | Reload positions from Grundstellung (begin new message) |
| `:S` | `:SHX` | Add plugboard pair (two letters); max 13 pairs |
| `:S--` | `:S--` | Clear all plugboard pairs |
| `:?` | `:?` | Show current configuration |
| `:UB` | `:UB` | Confirm reflector B (the only supported reflector) |

Notes:
- `:R`, `:N`, `:P`, `:S`, and `:U` require a CR/LF after the arguments.
- `:G`, `:F`, and `:?` execute immediately — no Enter key needed.
- All letter input is case-insensitive. Output is always uppercase.
- LED D1 blinks at ~1 Hz as a heartbeat. D5 flashes on errors.

## License

This documentation is licensed under the BSD 3-Clause License. See the [LICENSE](../LICENSE) file for the full license text.
