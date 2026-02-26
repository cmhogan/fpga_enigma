// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// uart_rx.v
// UART receiver module for iCE40-HX8K Breakout Board
// 115200 baud, 8N1, 12 MHz system clock
// Features: 2-FF metastability synchroniser, midpoint sampling, glitch rejection

module uart_rx #(
    parameter BAUD_DIV = 103,   // clk_freq / baud_rate - 1
    parameter HALF_BIT = 51     // (BAUD_DIV + 1) / 2 - 1
) (
    input  wire       clk,        // 12 MHz system clock
    input  wire       rst_n,      // Active-low synchronous reset
    input  wire       rxd,        // Raw UART RX line from pin
    output reg  [7:0] rx_byte = 8'd0,    // Received data byte
    output reg        rx_valid = 1'b0,   // Single-cycle pulse when byte ready
    output reg        rx_error = 1'b0,   // Framing error flag
    output reg        rx_active = 1'b0   // High while receiving
);

    // State machine encoding
    localparam [1:0] IDLE       = 2'd0,
                     START_WAIT = 2'd1,
                     RECEIVE    = 2'd2,
                     STOP       = 2'd3;

    // Two-FF synchroniser (initialized to idle HIGH)
    reg rx_sync1 = 1'b1;
    reg rx_sync2 = 1'b1;

    // State machine and counters
    reg [1:0]  state     = IDLE;
    reg [11:0] baud_cnt  = 12'd0;
    reg [3:0]  bit_cnt   = 4'd0;
    reg [7:0]  shift_reg = 8'd0;

    // Synchroniser: two-stage metastability protection
    always @(posedge clk) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rxd;
            rx_sync2 <= rx_sync1;
        end
    end

    // Main state machine and receiver logic
    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= IDLE;
            baud_cnt  <= 12'd0;
            bit_cnt   <= 4'd0;
            shift_reg <= 8'd0;
            rx_byte   <= 8'd0;
            rx_valid  <= 1'b0;
            rx_error  <= 1'b0;
            rx_active <= 1'b0;
        end else begin
            // Default: clear single-cycle pulse
            rx_valid <= 1'b0;

            case (state)
                IDLE: begin
                    rx_active <= 1'b0;
                    rx_error  <= 1'b0;
                    baud_cnt  <= 12'd0;
                    bit_cnt   <= 4'd0;

                    // Detect start bit (falling edge: HIGH → LOW)
                    if (rx_sync2 == 1'b0) begin
                        state    <= START_WAIT;
                        baud_cnt <= HALF_BIT;
                        rx_active <= 1'b1;
                    end
                end

                START_WAIT: begin
                    // Wait half a bit period to sample at midpoint
                    if (baud_cnt == 12'd0) begin
                        // Verify start bit is still LOW (glitch rejection)
                        if (rx_sync2 == 1'b0) begin
                            state    <= RECEIVE;
                            baud_cnt <= BAUD_DIV;
                            bit_cnt  <= 4'd0;
                        end else begin
                            // Glitch detected, abort to IDLE
                            state <= IDLE;
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 12'd1;
                    end
                end

                RECEIVE: begin
                    if (baud_cnt == 12'd0) begin
                        // Sample data bit (LSB first)
                        shift_reg <= {rx_sync2, shift_reg[7:1]};
                        bit_cnt   <= bit_cnt + 4'd1;

                        if (bit_cnt == 4'd7) begin
                            // All 8 bits received, move to stop bit
                            state    <= STOP;
                            baud_cnt <= BAUD_DIV;
                        end else begin
                            baud_cnt <= BAUD_DIV;
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 12'd1;
                    end
                end

                STOP: begin
                    if (baud_cnt == 12'd0) begin
                        // Sample stop bit
                        if (rx_sync2 == 1'b1) begin
                            // Valid stop bit: output byte
                            rx_byte  <= shift_reg;
                            rx_valid <= 1'b1;
                            rx_error <= 1'b0;
                        end else begin
                            // Framing error: stop bit not HIGH
                            rx_error <= 1'b1;
                        end
                        state <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt - 12'd1;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
