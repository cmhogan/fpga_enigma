// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// enigma_common.vh
// — Shared RTL functions for Enigma cipher modules
// Include this file inside module scope (Verilog functions must be module-local)
// Note: No header guard is used because each module needs its own copy of these functions

// =========================================================================
// mod26 helper: reduce a 6-bit value to [0,25]
// =========================================================================
function [4:0] mod26;
    input [5:0] val;
    /* verilator lint_off UNUSED */
    reg [5:0] tmp;
    /* verilator lint_on UNUSED */
    begin
        tmp = (val >= 6'd26) ? (val - 6'd26) : val;
        mod26 = tmp[4:0];
    end
endfunction
