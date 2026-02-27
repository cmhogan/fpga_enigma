// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// enigma_top_nexys.v
// Thin top-level for Nexys A7-100T board.
// ext_rst_n is wired to CPU_RESETN (N17), which is natively active-low;
// passed through directly to enigma_top_amd without inversion.

module enigma_top_nexys (
    input  wire clk_100mhz,
    input  wire ext_rst_n,   // Wired to CPU_RESETN (N17), active-low — no inversion needed
    input  wire uart_rx,
    output wire uart_tx,
    output wire led_d1,
    output wire led_d2,
    output wire led_d3,
    output wire led_d4,
    output wire led_d5
);

    enigma_top_amd u_amd (
        .clk_100mhz(clk_100mhz),
        .ext_rst_n (ext_rst_n),   // Pass through directly
        .uart_rx   (uart_rx),
        .uart_tx   (uart_tx),
        .led_d1    (led_d1),
        .led_d2    (led_d2),
        .led_d3    (led_d3),
        .led_d4    (led_d4),
        .led_d5    (led_d5)
    );

endmodule
