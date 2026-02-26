#!/bin/bash
# Copyright (c) 2026, Chad Hogan
# All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.
# verify_pyenigma.sh — cross-validate spec test vectors against pyenigma
PASS=0; FAIL=0

check() {
    local label="$1" expected="$2"; shift 2
    actual=$(pyenigma "$@" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $label"
        ((PASS++))
    else
        echo "FAIL: $label — expected '$expected', got '$actual'"
        ((FAIL++))
    fi
}

check "Case 1: Ground"      "BDZGO"                          -r I II III -i A A A -u B -s AAA -t AAAAA
check "Case 2: Barbarossa"   "AUFKL"                          -r II IV V -i B U L -u B -p AV BS CG DL FU HZ IN KM OW RX -s BLA -t EDPUD
check "Case 3: Double-step"  "ZG"                             -r III II I -i A A A -u B -s ADQ -t AA
check "Case 4: Ring BBB"     "EWTYX"                          -r I II III -i B B B -u B -s AAA -t AAAAA
check "Case 5: Triple-notch" "LNPJG"                          -r I II III -i A A A -u B -s QEV -t AAAAA
check "Case 6: 26-char"      "BDZGOWCXLTKSBTMCDLPBMUQOFX"    -r I II III -i A A A -u B -s AAA -t AAAAAAAAAAAAAAAAAAAAAAAAAA
check "Case 7: Reciprocal"   "NIBAJBTJDJGUHGVU"               -r II IV V -i B U L -u B -p AV BS CG DL FU HZ IN KM OW RX -s BLA -t THEQUICKBROWNFOX

# Round-trip check for Case 7
CT=$(pyenigma -r II IV V -i B U L -u B -p AV BS CG DL FU HZ IN KM OW RX -s BLA -t THEQUICKBROWNFOX)
check "Case 7: Round-trip"   "THEQUICKBROWNFOX"               -r II IV V -i B U L -u B -p AV BS CG DL FU HZ IN KM OW RX -s BLA -t "$CT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
