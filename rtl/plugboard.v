// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// plugboard.v
// Enigma I plugboard (Steckerbrett) - 26-entry reciprocal substitution table
//
// Pure combinational module implementing the plugboard as a configurable
// letter-to-letter mapping. Each input letter (0..25) is substituted with
// an output letter (0..25) according to the plug_map configuration.
//
// The plugboard is reciprocal: if A maps to B, then B maps to A.
// This reciprocity must be enforced by the configuration logic, not here.
//
// Usage: One instance before rotors (enigma_forward), one after (enigma_backward)
// Target: ~30 LCs per instance

module plugboard (
    input  wire [4:0]   letter_in,   // Input letter index 0..25
    input  wire [129:0] plug_map,    // Flat wiring map: 26 entries × 5 bits each
    output wire [4:0]   letter_out   // Substituted output letter index 0..25
);

    // Combinational lookup: select 5-bit slice from plug_map based on letter_in
    // plug_map[letter_in * 5 +: 5] extracts bits [letter_in*5 + 4 : letter_in*5]
    assign letter_out = plug_map[letter_in * 5 +: 5];

endmodule
