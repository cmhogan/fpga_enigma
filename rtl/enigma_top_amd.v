// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// enigma_top_amd.v
// Shared AMD/Xilinx MMCM clock wrapper: 100 MHz -> 12 MHz via MMCME2_BASE.
// Instantiates enigma_top after generating a stable 12 MHz clock.

module enigma_top_amd (
    input  wire clk_100mhz,
    input  wire ext_rst_n,    // Active-low (board-specific polarity handled by caller)
    input  wire uart_rx,
    output wire uart_tx,
    output wire led_d1,
    output wire led_d2,
    output wire led_d3,
    output wire led_d4,
    output wire led_d5
);

    wire clkfb_out, clkfb_buf;
    wire clkout0;
    wire clk_12mhz;
    wire mmcm_locked;

    // MMCM: 100 MHz * 9.0 / 1 = 900 MHz VCO; 900 / 75.0 = 12 MHz output
    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (9.0),
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (10.0),      // 100 MHz = 10 ns
        .DIVCLK_DIVIDE      (1),
        .CLKOUT0_DIVIDE_F   (75.0),      // 900 / 75 = 12.000 MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_DIVIDE     (1),
        .CLKOUT2_DIVIDE     (1),
        .CLKOUT3_DIVIDE     (1),
        .CLKOUT4_DIVIDE     (1),
        .CLKOUT5_DIVIDE     (1),
        .CLKOUT6_DIVIDE     (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKIN1   (clk_100mhz),
        .CLKFBIN  (clkfb_buf),
        .CLKOUT0  (clkout0),
        /* verilator lint_off PINCONNECTEMPTY */
        .CLKOUT0B (),
        .CLKOUT1  (),
        .CLKOUT1B (),
        .CLKOUT2  (),
        .CLKOUT2B (),
        .CLKOUT3  (),
        .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .CLKFBOUTB(),
        /* verilator lint_on PINCONNECTEMPTY */
        .CLKFBOUT (clkfb_out),
        .LOCKED   (mmcm_locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    // Feedback path buffer
    BUFG u_bufg_fb (
        .I (clkfb_out),
        .O (clkfb_buf)
    );

    // Output clock buffer
    BUFG u_bufg_clk (
        .I (clkout0),
        .O (clk_12mhz)
    );

    // Hold enigma_top in reset until MMCM is locked
    // NOTE: ext_rst_n bypassed — on Nexys A7 Rev D, pin N17 reads as stuck low.
    // The design's internal POR generator handles power-on reset.
    wire combined_rst_n = mmcm_locked;

    enigma_top #(
        .CLK_FREQ  (12_000_000),
        .BAUD_RATE (115_200)
    ) u_enigma (
        .clk      (clk_12mhz),
        .ext_rst_n(combined_rst_n),
        .uart_rx  (uart_rx),
        .uart_tx  (uart_tx),
        .led_d1   (led_d1),
        .led_d2   (led_d2),
        .led_d3   (led_d3),
        .led_d4   (led_d4),
        .led_d5   (led_d5)
    );

endmodule
