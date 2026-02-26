`timescale 1ns / 1ps
// Debug: trace UART TX shift register and bit timing for cipher response
module system_test4;
    reg clk = 0;
    always #41.667 clk = ~clk;

    reg  uart_rx_pin = 1'b1;
    wire uart_tx_pin;
    wire led_d1, led_d2, led_d3, led_d4, led_d5;

    enigma_top dut (
        .clk(clk), .ext_rst_n(1'b1), .uart_rx(uart_rx_pin), .uart_tx(uart_tx_pin),
        .led_d1(led_d1), .led_d2(led_d2), .led_d3(led_d3),
        .led_d4(led_d4), .led_d5(led_d5)
    );

    localparam BAUD_CLKS = 104;

    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            @(posedge clk); #1;
            uart_rx_pin = 1'b0;
            repeat(BAUD_CLKS) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                #1; uart_rx_pin = data[i];
                repeat(BAUD_CLKS) @(posedge clk);
            end
            #1; uart_rx_pin = 1'b1;
            repeat(BAUD_CLKS) @(posedge clk);
            repeat(BAUD_CLKS) @(posedge clk);
        end
    endtask

    task uart_recv_byte;
        output [7:0] data;
        integer i;
        reg [7:0] shift;
        begin
            shift = 8'd0;
            @(negedge uart_tx_pin);
            repeat(BAUD_CLKS / 2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                repeat(BAUD_CLKS) @(posedge clk);
                shift = {uart_tx_pin, shift[7:1]};
            end
            repeat(BAUD_CLKS) @(posedge clk);
            data = shift;
        end
    endtask

    reg [7:0] rx_byte;
    integer i;

    // Track UART TX
    reg tx_start_prev = 0;
    always @(posedge clk) begin
        if (dut.u_uart_tx.tx_start && !tx_start_prev) begin
            $display("T=%0t UART_TX: tx_start asserted, tx_byte=0x%02X, state=%b, tx_busy=%b, queue_valid=%b",
                     $time, dut.u_uart_tx.tx_byte, dut.u_uart_tx.state,
                     dut.u_uart_tx.tx_busy, dut.u_uart_tx.queue_valid);
        end
        tx_start_prev <= dut.u_uart_tx.tx_start;
    end

    // Track when UART TX loads shift register
    reg [9:0] prev_shift = 10'h3FF;
    always @(posedge clk) begin
        if (dut.u_uart_tx.shift_reg !== prev_shift) begin
            $display("T=%0t UART_TX: shift_reg=0b%010b (new)", $time, dut.u_uart_tx.shift_reg);
            prev_shift <= dut.u_uart_tx.shift_reg;
        end
    end

    // Count clocks in UART TX TRANSMIT state
    integer tx_clk_count = 0;
    always @(posedge clk) begin
        if (dut.u_uart_tx.state == 1'b1) begin
            if (dut.u_uart_tx.baud_cnt == 12'd0) begin
                $display("T=%0t UART_TX: baud_cnt=0, bit_cnt=%0d, txd=%b, shift[0]=%b, shift[1]=%b",
                         $time, dut.u_uart_tx.bit_cnt, dut.u_uart_tx.txd,
                         dut.u_uart_tx.shift_reg[0], dut.u_uart_tx.shift_reg[1]);
            end
        end
    end

    // Wait flag: only trace after banner
    reg trace_active = 0;

    initial begin
        $display("=== System Test 4: UART TX shift register trace ===");

        // Consume banner
        for (i = 0; i < 16; i = i + 1) begin
            uart_recv_byte(rx_byte);
        end
        $display("Banner consumed.");

        repeat(200) @(posedge clk);
        trace_active = 1;

        // Send 'A'
        $display("T=%0t Sending 'A'...", $time);
        uart_send_byte(8'h41);

        $display("T=%0t Waiting for response...", $time);
        uart_recv_byte(rx_byte);
        $display("Received: 0x%02X ('%c') — expected 0x42 ('B')", rx_byte, rx_byte);

        #10000;
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $finish(1);
    end
endmodule
