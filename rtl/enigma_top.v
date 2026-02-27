// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// enigma_top.v
// — Top-level integration for FPGA Enigma I on iCE40-HX8K Breakout Board (ICE40HX8K-B-EVN)
// Structural instantiation of all sub-modules with LED drivers.

module enigma_top #(
    parameter CLK_FREQ    = 12_000_000,
    parameter BAUD_RATE   = 115_200,
    parameter CMD_TIMEOUT = 0            // 0 = use default (CLK_FREQ * 3)
) (
    input  wire clk,        // 12 MHz oscillator
    input  wire ext_rst_n,  // External reset (active-low), tie to 1'b1 if unused
    input  wire uart_rx,    // UART receive (from FTDI)
    output wire uart_tx,    // UART transmit (to FTDI)
    output wire led_d1,     // Heartbeat
    output wire led_d2,     // RX activity
    output wire led_d3,     // TX activity
    output wire led_d4,     // Mode indicator (command mode)
    output wire led_d5      // Error indicator
);

    // Power-on reset generator: hold reset for 1024 clocks after GSR
    reg [9:0] por_cnt = 10'd0;
    reg       por_done = 1'b0;
    always @(posedge clk) begin
        if (!por_done) begin
            if (por_cnt == 10'd1023)
                por_done <= 1'b1;
            else
                por_cnt <= por_cnt + 10'd1;
        end
    end

    // Synchronize external reset (2-FF metastability protection)
    reg ext_rst_sync1 = 1'b0;
    reg ext_rst_sync2 = 1'b0;
    always @(posedge clk) begin
        ext_rst_sync1 <= ext_rst_n;
        ext_rst_sync2 <= ext_rst_sync1;
    end

    wire rst_n = por_done & ext_rst_sync2;

    // Derived timing parameters
    /* verilator lint_off WIDTH */
    localparam [11:0] BAUD_DIV_VAL = CLK_FREQ / BAUD_RATE - 1;
    localparam [11:0] HALF_BIT_VAL = (CLK_FREQ / BAUD_RATE) / 2 - 1;
    localparam [25:0] TIMEOUT_LIMIT_VAL = (CMD_TIMEOUT != 0) ? CMD_TIMEOUT : CLK_FREQ * 3;
    localparam [22:0] HEARTBEAT_MAX_VAL = CLK_FREQ / 2 - 1;
    /* verilator lint_on WIDTH */

    // =========================================================================
    // UART RX
    // =========================================================================
    wire [7:0] rx_byte;
    wire       rx_valid;
    /* verilator lint_off UNUSED */
    wire       rx_error;
    wire       rx_active;
    /* verilator lint_on UNUSED */

    uart_rx #(
        .BAUD_DIV(BAUD_DIV_VAL),
        .HALF_BIT(HALF_BIT_VAL)
    ) u_uart_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rxd      (uart_rx),
        .rx_byte  (rx_byte),
        .rx_valid (rx_valid),
        .rx_error (rx_error),
        .rx_active(rx_active)
    );

    // =========================================================================
    // UART TX
    // =========================================================================
    wire [7:0] tx_byte;
    wire       tx_start;
    wire       tx_busy;

    uart_tx #(
        .BAUD_DIV(BAUD_DIV_VAL)
    ) u_uart_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_byte  (tx_byte),
        .tx_start (tx_start),
        .txd      (uart_tx),
        .tx_busy  (tx_busy)
    );

    // =========================================================================
    // Configuration Manager
    // =========================================================================
    wire [2:0]   rotor_sel_l, rotor_sel_m, rotor_sel_r;
    wire [4:0]   ring_l, ring_m, ring_r;
    wire [4:0]   grundstellung_l, grundstellung_m, grundstellung_r;
    wire [129:0] plug_map;
    wire [4:0]   plug_pair_cnt;
    wire [63:0]  cfg_status;
    wire         cfg_wr_rotor, cfg_wr_ring, cfg_wr_grund;
    wire         cfg_wr_plug_add, cfg_wr_plug_clr, cfg_wr_factory;
    wire [15:0]  cfg_data;
    wire [4:0]   pos_l, pos_m, pos_r;

    config_manager u_config (
        .clk             (clk),
        .rst_n           (rst_n),
        .wr_rotor        (cfg_wr_rotor),
        .wr_ring         (cfg_wr_ring),
        .wr_grund        (cfg_wr_grund),
        .wr_plug_add     (cfg_wr_plug_add),
        .wr_plug_clr     (cfg_wr_plug_clr),
        .wr_factory      (cfg_wr_factory),
        .cfg_data        (cfg_data),
        .pos_l           (pos_l),
        .pos_m           (pos_m),
        .pos_r           (pos_r),
        .rotor_sel_l     (rotor_sel_l),
        .rotor_sel_m     (rotor_sel_m),
        .rotor_sel_r     (rotor_sel_r),
        .ring_l          (ring_l),
        .ring_m          (ring_m),
        .ring_r          (ring_r),
        .grundstellung_l (grundstellung_l),
        .grundstellung_m (grundstellung_m),
        .grundstellung_r (grundstellung_r),
        .plug_map        (plug_map),
        .plug_pair_cnt   (plug_pair_cnt),
        .cfg_status      (cfg_status)
    );

    // =========================================================================
    // Stepper
    // =========================================================================
    wire step_pulse, load_pulse;

    stepper u_stepper (
        .clk             (clk),
        .rst_n           (rst_n),
        .step_pulse      (step_pulse),
        .load_pulse      (load_pulse),
        .rotor_sel_m     (rotor_sel_m),
        .rotor_sel_r     (rotor_sel_r),
        .grundstellung_l (grundstellung_l),
        .grundstellung_m (grundstellung_m),
        .grundstellung_r (grundstellung_r),
        .pos_l           (pos_l),
        .pos_m           (pos_m),
        .pos_r           (pos_r)
    );

    // =========================================================================
    // Cipher path: Forward half (plugboard → rotors fwd → reflector)
    // =========================================================================
    wire [4:0] pt_index;
    wire [4:0] mid_letter_fwd;

    enigma_forward u_fwd (
        .pt_index    (pt_index),
        .rotor_sel_l (rotor_sel_l),
        .rotor_sel_m (rotor_sel_m),
        .rotor_sel_r (rotor_sel_r),
        .ring_l      (ring_l),
        .ring_m      (ring_m),
        .ring_r      (ring_r),
        .pos_l       (pos_l),
        .pos_m       (pos_m),
        .pos_r       (pos_r),
        .plug_map    (plug_map),
        .mid_letter  (mid_letter_fwd)
    );

    // =========================================================================
    // Cipher path: Backward half (rotors inv → plugboard)
    // =========================================================================
    wire [4:0] mid_letter_reg;
    wire [4:0] ct_index;

    enigma_backward u_bwd (
        .mid_letter  (mid_letter_reg),
        .rotor_sel_l (rotor_sel_l),
        .rotor_sel_m (rotor_sel_m),
        .rotor_sel_r (rotor_sel_r),
        .ring_l      (ring_l),
        .ring_m      (ring_m),
        .ring_r      (ring_r),
        .pos_l       (pos_l),
        .pos_m       (pos_m),
        .pos_r       (pos_r),
        .plug_map    (plug_map),
        .ct_index    (ct_index)
    );

    // =========================================================================
    // FSM Controller
    // =========================================================================
    wire error_led;
    wire cmd_mode;

    fsm_controller #(
        .TIMEOUT_LIMIT(TIMEOUT_LIMIT_VAL)
    ) u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        // UART
        .rx_byte         (rx_byte),
        .rx_valid        (rx_valid),
        .tx_busy         (tx_busy),
        .tx_byte         (tx_byte),
        .tx_start        (tx_start),
        // Cipher
        .mid_letter_fwd  (mid_letter_fwd),
        .ct_index        (ct_index),
        .pt_index        (pt_index),
        .mid_letter_reg  (mid_letter_reg),
        // Stepper
        .step_pulse      (step_pulse),
        .load_pulse      (load_pulse),
        // Config manager
        .cfg_wr_rotor    (cfg_wr_rotor),
        .cfg_wr_ring     (cfg_wr_ring),
        .cfg_wr_grund    (cfg_wr_grund),
        .cfg_wr_plug_add (cfg_wr_plug_add),
        .cfg_wr_plug_clr (cfg_wr_plug_clr),
        .cfg_wr_factory  (cfg_wr_factory),
        .cfg_data        (cfg_data),
        .cfg_status      (cfg_status),
        .pos_l           (pos_l),
        .pos_m           (pos_m),
        .pos_r           (pos_r),
        .plug_map        (plug_map),
        .plug_pair_cnt   (plug_pair_cnt),
        .error_led       (error_led),
        .cmd_mode        (cmd_mode)
    );

    // =========================================================================
    // LED Drivers
    // =========================================================================

    // D1: Heartbeat — toggle at ~1 Hz (divide 12 MHz by 12,000,000)
    reg [22:0] heartbeat_cnt = 23'd0;
    reg        heartbeat_led = 1'b0;
    always @(posedge clk) begin
        if (heartbeat_cnt == HEARTBEAT_MAX_VAL) begin
            heartbeat_cnt <= 23'd0;
            heartbeat_led <= ~heartbeat_led;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 23'd1;
        end
    end
    assign led_d1 = heartbeat_led;

    // D2: RX activity — pulse ~100ms on each received byte
    reg [20:0] rx_led_cnt = 21'd0;
    reg        rx_led     = 1'b0;
    always @(posedge clk) begin
        if (rx_valid) begin
            rx_led_cnt <= 21'd1_199_999;
            rx_led <= 1'b1;
        end else if (rx_led_cnt > 0) begin
            rx_led_cnt <= rx_led_cnt - 21'd1;
        end else begin
            rx_led <= 1'b0;
        end
    end
    assign led_d2 = rx_led;

    // D3: TX activity — pulse ~100ms on each transmitted byte
    reg [20:0] tx_led_cnt = 21'd0;
    reg        tx_led     = 1'b0;
    always @(posedge clk) begin
        if (tx_start) begin
            tx_led_cnt <= 21'd1_199_999;
            tx_led <= 1'b1;
        end else if (tx_led_cnt > 0) begin
            tx_led_cnt <= tx_led_cnt - 21'd1;
        end else begin
            tx_led <= 1'b0;
        end
    end
    assign led_d3 = tx_led;

    // D4: Mode indicator — HIGH during command mode
    assign led_d4 = cmd_mode;

    // D5: Error indicator — pulse ~200ms on error
    reg [21:0] err_led_cnt = 22'd0;
    reg        err_led     = 1'b0;
    always @(posedge clk) begin
        if (error_led) begin
            err_led_cnt <= 22'd2_399_999;
            err_led <= 1'b1;
        end else if (err_led_cnt > 0) begin
            err_led_cnt <= err_led_cnt - 22'd1;
        end else begin
            err_led <= 1'b0;
        end
    end
    assign led_d5 = err_led;

endmodule
