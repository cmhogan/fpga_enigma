`timescale 1ns / 1ps
// Minimal system-level test: send 'A' after banner, expect 'B' back
module system_test1;
    reg clk = 0;
    always #41.667 clk = ~clk;  // ~12 MHz

    reg  uart_rx_pin = 1'b1;  // idle HIGH
    wire uart_tx_pin;
    wire led_d1, led_d2, led_d3, led_d4, led_d5;

    enigma_top dut (
        .clk(clk), .ext_rst_n(1'b1), .uart_rx(uart_rx_pin), .uart_tx(uart_tx_pin),
        .led_d1(led_d1), .led_d2(led_d2), .led_d3(led_d3),
        .led_d4(led_d4), .led_d5(led_d5)
    );

    localparam BAUD_CLKS = 104;

    // ---- Clock-based UART send ----
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            @(posedge clk); #1;
            uart_rx_pin = 1'b0;  // start bit
            repeat(BAUD_CLKS) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                #1; uart_rx_pin = data[i];
                repeat(BAUD_CLKS) @(posedge clk);
            end
            #1; uart_rx_pin = 1'b1;  // stop bit
            repeat(BAUD_CLKS) @(posedge clk);
            // inter-byte gap
            repeat(BAUD_CLKS) @(posedge clk);
        end
    endtask

    // ---- Clock-based UART receive ----
    task uart_recv_byte;
        output [7:0] data;
        integer i;
        reg [7:0] shift;
        begin
            shift = 8'd0;
            // Wait for falling edge of tx pin
            @(negedge uart_tx_pin);
            // Wait 52 clocks to midpoint of start bit
            repeat(BAUD_CLKS / 2) @(posedge clk);
            if (uart_tx_pin !== 1'b0)
                $display("ERROR: start bit not low at midpoint");
            // Sample 8 data bits
            for (i = 0; i < 8; i = i + 1) begin
                repeat(BAUD_CLKS) @(posedge clk);
                shift = {uart_tx_pin, shift[7:1]};
            end
            // Stop bit
            repeat(BAUD_CLKS) @(posedge clk);
            data = shift;
        end
    endtask

    reg [7:0] rx_byte;
    integer i;

    initial begin
        $display("=== System Test 1: Banner + Encipher A ===");

        // Wait for and consume 16-byte banner "ENIGMA I READY\r\n"
        for (i = 0; i < 16; i = i + 1) begin
            uart_recv_byte(rx_byte);
            $write("%c", rx_byte);
        end
        $display("Banner done.");

        // Now send 'A' — expect 'B' (default config, first keystroke)
        $display("Sending 'A'...");
        uart_send_byte(8'h41);  // 'A'

        uart_recv_byte(rx_byte);
        $display("Received: 0x%02X ('%c') — expected 0x42 ('B')", rx_byte, rx_byte);
        if (rx_byte == 8'h42)
            $display("PASS");
        else
            $display("FAIL");

        #10000;
        $finish;
    end

    // Timeout
    initial begin
        #500_000_000; // 500ms
        $display("TIMEOUT");
        $finish(1);
    end
endmodule
