#!/usr/bin/env python3
"""Hardware integration tests for FPGA Enigma I on Nexys A7-100T.

Communicates with the live design over /dev/ttyUSB1 at 115200 baud 8N1.
Requires: pyserial (pip install pyserial)

Usage: python3 scripts/hw_test.py [--port /dev/ttyUSB1]
"""

import sys
import time
import argparse
import serial


class HWEnigma:
    """Helper class wrapping serial communication with the FPGA Enigma."""

    def __init__(self, port="/dev/ttyUSB1", baud=115200, timeout=3):
        self.ser = serial.Serial(port, baud, timeout=timeout)
        time.sleep(0.3)
        self.ser.read(self.ser.in_waiting)  # flush any buffered data

    def close(self):
        self.ser.close()

    def _read_until_ok_or_err(self):
        """Read lines until we see OK or ERR. Returns full response text."""
        lines = []
        deadline = time.time() + 5
        buf = b""
        while time.time() < deadline:
            chunk = self.ser.read(self.ser.in_waiting or 1)
            if not chunk:
                continue
            buf += chunk
            while b"\r\n" in buf:
                line, buf = buf.split(b"\r\n", 1)
                text = line.decode("ascii", errors="replace")
                lines.append(text)
                if text in ("OK", "ERR"):
                    return lines
        return lines  # timed out

    def send_cmd(self, cmd_str):
        """Send a command string and return list of response lines.

        For zero-arg commands (:G, :F, :?) do NOT append \\r.
        For commands with args (:R, :N, :P, :S, :U) append \\r.
        """
        self.ser.write(cmd_str.encode("ascii"))
        return self._read_until_ok_or_err()

    def factory_reset(self):
        """Send :F, consume banner + OK, flush any residual bytes."""
        resp = self.send_cmd(":F")
        time.sleep(0.1)
        self.ser.read(self.ser.in_waiting)  # flush residual
        return resp

    def query(self):
        """Send :?, parse response into a dict."""
        time.sleep(0.05)
        self.ser.read(self.ser.in_waiting)  # flush before query
        lines = self.send_cmd(":?")
        result = {}
        for line in lines:
            if ":" in line and line != "OK":
                key, _, val = line.partition(":")
                result[key.strip()] = val.strip()
        return result

    def grundstellung_reset(self):
        """Send :G, consume OK, flush residual."""
        resp = self.send_cmd(":G")
        time.sleep(0.05)
        self.ser.read(self.ser.in_waiting)
        return resp

    def encipher(self, plaintext):
        """Send plaintext letters one by one, collect ciphertext."""
        self.ser.read(self.ser.in_waiting)  # flush
        ciphertext = ""
        for ch in plaintext:
            self.ser.write(ch.encode("ascii"))
            resp = self.ser.read(1)
            if resp:
                ciphertext += resp.decode("ascii")
        return ciphertext

    def send_raw(self, data):
        """Send raw bytes without reading response."""
        self.ser.write(data if isinstance(data, bytes) else data.encode("ascii"))

    def read_available(self, wait=1.0):
        """Wait briefly, then return whatever is in the buffer."""
        time.sleep(wait)
        return self.ser.read(self.ser.in_waiting)


# =========================================================================
# Test runner
# =========================================================================

pass_count = 0
fail_count = 0


def check(condition, name):
    global pass_count, fail_count
    if condition:
        print(f"  PASS: {name}")
        pass_count += 1
    else:
        print(f"  FAIL: {name}")
        fail_count += 1


# =========================================================================
# Task 1: Cipher test vectors
# =========================================================================

def test_cipher_vectors(hw):
    print("\n=== Cipher Test Vectors ===\n")

    # --- Test 1: Ground settings ---
    print("--- Test 1: Ground settings (AAAAA -> BDZGO) ---")
    hw.factory_reset()
    ct = hw.encipher("AAAAA")
    check(ct == "BDZGO", f"Ground settings: AAAAA -> {ct} (expected BDZGO)")

    # --- Test 2: Barbarossa ---
    print("--- Test 2: Barbarossa (EDPUD -> AUFKL) ---")
    hw.factory_reset()
    hw.send_cmd(":R245\r")
    hw.send_cmd(":NBUL\r")
    hw.send_cmd(":PBLA\r")
    for pair in ["AV", "BS", "CG", "DL", "FU", "HZ", "IN", "KM", "OW", "RX"]:
        hw.send_cmd(f":S{pair}\r")
    hw.grundstellung_reset()
    ct = hw.encipher("EDPUD")
    check(ct == "AUFKL", f"Barbarossa: EDPUD -> {ct} (expected AUFKL)")

    # --- Test 3: Double-step anomaly ---
    print("--- Test 3: Double-step anomaly (ADQ -> AER -> BFS) ---")
    hw.factory_reset()
    hw.send_cmd(":R321\r")
    hw.send_cmd(":PADQ\r")
    hw.grundstellung_reset()
    # First keystroke
    hw.encipher("A")
    cfg1 = hw.query()
    pos1 = cfg1.get("POS", "")
    check(pos1 == "A E R", f"After 1st key: POS={pos1} (expected A E R)")
    # Second keystroke
    hw.encipher("A")
    cfg2 = hw.query()
    pos2 = cfg2.get("POS", "")
    check(pos2 == "B F S", f"After 2nd key: POS={pos2} (expected B F S)")

    # --- Test 4: Ring settings BBB ---
    print("--- Test 4: Ring BBB (AAAAA -> EWTYX) ---")
    hw.factory_reset()
    hw.send_cmd(":NBBB\r")
    hw.send_cmd(":PAAA\r")
    hw.grundstellung_reset()
    ct = hw.encipher("AAAAA")
    check(ct == "EWTYX", f"Ring BBB: AAAAA -> {ct} (expected EWTYX)")

    # --- Test 5: Triple-notch QEV ---
    print("--- Test 5: Triple-notch QEV (AAAAA -> LNPJG) ---")
    hw.factory_reset()
    hw.send_cmd(":PQEV\r")
    hw.grundstellung_reset()
    ct = hw.encipher("AAAAA")
    check(ct == "LNPJG", f"Triple-notch: AAAAA -> {ct} (expected LNPJG)")

    # --- Test 6: 26-char full cycle ---
    print("--- Test 6: 26-char full cycle ---")
    hw.factory_reset()
    ct = hw.encipher("A" * 26)
    expected = "BDZGOWCXLTKSBTMCDLPBMUQOFX"
    check(ct == expected, f"26-char: got {ct}")

    # --- Test 7: Self-reciprocal round-trip ---
    print("--- Test 7: Self-reciprocal round-trip (Barbarossa) ---")
    hw.factory_reset()
    hw.send_cmd(":R245\r")
    hw.send_cmd(":NBUL\r")
    hw.send_cmd(":PBLA\r")
    for pair in ["AV", "BS", "CG", "DL", "FU", "HZ", "IN", "KM", "OW", "RX"]:
        hw.send_cmd(f":S{pair}\r")
    hw.grundstellung_reset()
    ct = hw.encipher("THEQUICKBROWNFOX")
    check(ct == "NIBAJBTJDJGUHGVU", f"Encrypt: THEQUICKBROWNFOX -> {ct} (expected NIBAJBTJDJGUHGVU)")
    hw.grundstellung_reset()
    pt = hw.encipher("NIBAJBTJDJGUHGVU")
    check(pt == "THEQUICKBROWNFOX", f"Decrypt: NIBAJBTJDJGUHGVU -> {pt} (expected THEQUICKBROWNFOX)")


# =========================================================================
# Task 2: Command tests
# =========================================================================

def test_commands(hw):
    print("\n=== Command Tests ===\n")

    # --- C1: Factory reset ---
    print("--- C1: Factory reset ---")
    resp = hw.factory_reset()
    check("ENIGMA I READY" in resp and "OK" in resp,
          f"Factory reset response: {resp}")

    # --- C2: Status query defaults ---
    print("--- C2: Status query defaults ---")
    cfg = hw.query()
    check(cfg.get("UKW") == "B", f"UKW={cfg.get('UKW')} (expected B)")
    check(cfg.get("ROT") == "1 2 3", f"ROT={cfg.get('ROT')} (expected 1 2 3)")
    check(cfg.get("RNG") == "A A A", f"RNG={cfg.get('RNG')} (expected A A A)")
    check(cfg.get("GRD") == "A A A", f"GRD={cfg.get('GRD')} (expected A A A)")
    check(cfg.get("POS") == "A A A", f"POS={cfg.get('POS')} (expected A A A)")
    check(cfg.get("PLG") == "" or cfg.get("PLG") is None or cfg.get("PLG") == "",
          f"PLG='{cfg.get('PLG')}' (expected empty)")

    # --- C3: Set rotors ---
    print("--- C3: Set rotors ---")
    hw.factory_reset()
    resp = hw.send_cmd(":R245\r")
    check("OK" in resp, f"Set rotors: {resp}")
    cfg = hw.query()
    check(cfg.get("ROT") == "2 4 5", f"ROT={cfg.get('ROT')} (expected 2 4 5)")

    # --- C4: Set rings ---
    print("--- C4: Set rings ---")
    resp = hw.send_cmd(":NBUL\r")
    check("OK" in resp, f"Set rings: {resp}")
    cfg = hw.query()
    check(cfg.get("RNG") == "B U L", f"RNG={cfg.get('RNG')} (expected B U L)")

    # --- C5: Set positions + Grundstellung ---
    print("--- C5: Set positions + Grundstellung ---")
    resp = hw.send_cmd(":PBLA\r")
    check("OK" in resp, f"Set positions: {resp}")
    resp = hw.grundstellung_reset()
    check("OK" in resp, f"Grundstellung reset: {resp}")
    cfg = hw.query()
    check(cfg.get("GRD") == "B L A", f"GRD={cfg.get('GRD')} (expected B L A)")
    check(cfg.get("POS") == "B L A", f"POS={cfg.get('POS')} (expected B L A)")

    # --- C6: Add plugboard pair ---
    print("--- C6: Add plugboard pair ---")
    hw.factory_reset()
    resp = hw.send_cmd(":SAV\r")
    check("OK" in resp, f"Add plug AV: {resp}")
    cfg = hw.query()
    check("AV" in cfg.get("PLG", ""), f"PLG={cfg.get('PLG')} (expected AV)")

    # --- C7: Clear plugboard ---
    print("--- C7: Clear plugboard ---")
    resp = hw.send_cmd(":S--\r")
    check("OK" in resp, f"Clear plugboard: {resp}")
    cfg = hw.query()
    plg = cfg.get("PLG", "")
    check(plg == "" or plg.strip() == "", f"PLG='{plg}' (expected empty)")

    # --- C8: Confirm reflector ---
    print("--- C8: Confirm reflector ---")
    resp = hw.send_cmd(":UB\r")
    check("OK" in resp, f"Confirm UKW-B: {resp}")

    # --- C9: Grundstellung reset ---
    print("--- C9: Grundstellung reset ---")
    hw.factory_reset()
    hw.send_cmd(":PXYZ\r")
    hw.grundstellung_reset()
    cfg = hw.query()
    check(cfg.get("POS") == cfg.get("GRD"),
          f"POS={cfg.get('POS')} matches GRD={cfg.get('GRD')}")

    # --- C10: Lowercase normalization ---
    print("--- C10: Lowercase normalization ---")
    hw.factory_reset()
    ct = hw.encipher("hello")
    check(ct == "ILBDA", f"Lowercase hello -> {ct} (expected ILBDA)")

    # --- Error tests ---
    print("\n--- Error Path Tests ---\n")

    # E1: Duplicate rotor
    print("--- E1: Duplicate rotor ---")
    hw.factory_reset()
    resp = hw.send_cmd(":R112\r")
    check("ERR" in resp, f"Duplicate rotor :R112 -> {resp}")

    # E2: Out-of-range rotor
    print("--- E2: Out-of-range rotor ---")
    resp = hw.send_cmd(":R126\r")
    check("ERR" in resp, f"Out-of-range rotor :R126 -> {resp}")

    # E3: Self-pair plugboard
    print("--- E3: Self-pair plugboard ---")
    resp = hw.send_cmd(":SAA\r")
    check("ERR" in resp, f"Self-pair :SAA -> {resp}")

    # E4: Wrong reflector
    print("--- E4: Wrong reflector ---")
    resp = hw.send_cmd(":UC\r")
    check("ERR" in resp, f"Wrong reflector :UC -> {resp}")

    # E5: Unknown opcode
    print("--- E5: Unknown opcode ---")
    resp = hw.send_cmd(":X")
    check("ERR" in resp, f"Unknown opcode :X -> {resp}")

    # E6: Already-wired plugboard letter
    print("--- E6: Already-wired plugboard letter ---")
    hw.factory_reset()
    hw.send_cmd(":SAB\r")
    resp = hw.send_cmd(":SAC\r")
    check("ERR" in resp, f"Already-wired :SAC -> {resp}")

    # E7: Recovery after error
    print("--- E7: Recovery after error ---")
    hw.factory_reset()
    ct = hw.encipher("A")
    check(ct.isalpha() and len(ct) == 1, f"Recovery: A -> {ct} (expected one letter)")


# =========================================================================
# Task 3: Timeout tests
# =========================================================================

def test_timeout(hw):
    print("\n=== Command Timeout Tests ===\n")

    # Timeout should be >= 2 seconds — test at 0.5, 1.0, 2.0s delays
    for delay in [0.5, 1.0, 2.0]:
        print(f"--- Timeout test: {delay}s delay ---")
        hw.factory_reset()
        hw.ser.read(hw.ser.in_waiting)  # flush
        hw.ser.write(b":")
        time.sleep(delay)
        hw.ser.write(b"?")
        time.sleep(1)
        resp = hw.ser.read(hw.ser.in_waiting)
        ok = b"UKW" in resp
        check(ok, f":{delay}s delay:? -> {'got response' if ok else 'no response'}")

    # Verify timeout does fire: 5-second delay should fail
    print("--- Timeout test: 5s delay (should timeout) ---")
    hw.factory_reset()
    hw.ser.read(hw.ser.in_waiting)
    hw.ser.write(b":")
    time.sleep(5)
    hw.ser.write(b"?")
    time.sleep(1)
    resp = hw.ser.read(hw.ser.in_waiting)
    check(b"UKW" not in resp, f":5s delay:? -> {'timed out (correct)' if b'UKW' not in resp else 'still got response (wrong)'}")

    # Verify machine still works after timeout
    print("--- Recovery after timeout ---")
    hw.ser.read(hw.ser.in_waiting)
    ct = hw.encipher("A")
    check(ct.isalpha() and len(ct) == 1, f"Post-timeout recovery: A -> {ct}")


# =========================================================================
# Main
# =========================================================================

def main():
    parser = argparse.ArgumentParser(description="FPGA Enigma hardware integration tests")
    parser.add_argument("--port", default="/dev/ttyUSB1", help="Serial port (default: /dev/ttyUSB1)")
    args = parser.parse_args()

    print(f"Opening {args.port} at 115200 baud...")
    hw = HWEnigma(port=args.port)

    try:
        test_cipher_vectors(hw)
        test_commands(hw)
        test_timeout(hw)
    finally:
        hw.close()

    print(f"\n{'=' * 50}")
    print(f"Results: {pass_count} passed, {fail_count} failed")
    print(f"{'=' * 50}")
    sys.exit(0 if fail_count == 0 else 1)


if __name__ == "__main__":
    main()
