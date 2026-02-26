// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// uart_tx.v
// — UART Transmitter for iCE40-HX8K Breakout Board
// 115200 baud, 8N1, 1-byte output queue
// Target: ~45 LCs

module uart_tx #(
    parameter BAUD_DIV = 103    // clk_freq / baud_rate - 1
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_byte,
    input  wire       tx_start,
    output reg        txd     = 1'b1,
    output wire       tx_busy
);

    // State
    localparam IDLE     = 1'b0;
    localparam TRANSMIT = 1'b1;

    reg        state     = IDLE;
    reg [11:0] baud_cnt  = 12'd0;
    reg [3:0]  bit_cnt   = 4'd0;    // 0..9: start + 8 data + stop
    /* verilator lint_off UNUSED */
    reg [9:0]  shift_reg = 10'h3FF;
    /* verilator lint_on UNUSED */
    reg [7:0]  queue_byte  = 8'd0;
    reg        queue_valid = 1'b0;

    assign tx_busy = (state == TRANSMIT) || queue_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= IDLE;
            baud_cnt   <= 12'd0;
            bit_cnt    <= 4'd0;
            shift_reg  <= 10'h3FF;
            txd        <= 1'b1;
            queue_byte  <= 8'd0;
            queue_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    txd <= 1'b1;
                    if (tx_start) begin
                        shift_reg <= {1'b1, tx_byte, 1'b0};  // {stop, data, start}
                        baud_cnt  <= BAUD_DIV - 1;  // will count down to 0
                        bit_cnt   <= 4'd0;
                        txd       <= 1'b0;  // drive start bit immediately
                        state     <= TRANSMIT;
                    end else if (queue_valid) begin
                        shift_reg  <= {1'b1, queue_byte, 1'b0};
                        queue_valid <= 1'b0;
                        baud_cnt   <= BAUD_DIV - 1;
                        bit_cnt    <= 4'd0;
                        txd        <= 1'b0;
                        state      <= TRANSMIT;
                    end
                end

                TRANSMIT: begin
                    // Accept one queued byte
                    if (tx_start && !queue_valid) begin
                        queue_byte  <= tx_byte;
                        queue_valid <= 1'b1;
                    end

                    if (baud_cnt == 12'd0) begin
                        // Current bit period complete; shift to next bit
                        shift_reg <= {1'b1, shift_reg[9:1]};
                        bit_cnt   <= bit_cnt + 4'd1;
                        if (bit_cnt == 4'd9) begin
                            // Stop bit was just output; frame done
                            state <= IDLE;
                            txd   <= 1'b1;
                        end else begin
                            // Drive next bit
                            txd      <= shift_reg[1]; // next bit after shift
                            baud_cnt <= BAUD_DIV - 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 12'd1;
                    end
                end
            endcase
        end
    end

endmodule
