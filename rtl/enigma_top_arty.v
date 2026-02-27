// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// enigma_top_arty.v
// Thin top-level for Arty A7-100T board.
// ext_rst_n is wired to BTN0 (C2), which is active-high; inverted internally
// to produce active-low reset for enigma_top_amd.

module enigma_top_arty (
    input  wire clk_100mhz,
    input  wire ext_rst_n,   // Wired to BTN0 (active-high); inverted internally
    input  wire uart_rx,
    output wire uart_tx,
    output wire led_d1,
    output wire led_d2,
    output wire led_d3,
    output wire led_d4,
    output wire led_d5
);

    // BTN0 is active-high; invert so pressed = reset asserted (active-low to enigma_top_amd)
    enigma_top_amd u_amd (
        .clk_100mhz(clk_100mhz),
        .ext_rst_n (~ext_rst_n),
        .uart_rx   (uart_rx),
        .uart_tx   (uart_tx),
        .led_d1    (led_d1),
        .led_d2    (led_d2),
        .led_d3    (led_d3),
        .led_d4    (led_d4),
        .led_d5    (led_d5)
    );

endmodule
