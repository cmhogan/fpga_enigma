`timescale 1ns / 1ps
// Debug: manually receive byte from UART TX with per-bit trace
module system_test3;
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

    // Verbose recv with per-bit trace
    task uart_recv_verbose;
        output [7:0] data;
        integer i;
        reg [7:0] shift;
        begin
            shift = 8'd0;
            @(negedge uart_tx_pin);
            $display("T=%0t Start bit edge detected (txd=%b)", $time, uart_tx_pin);
            repeat(BAUD_CLKS / 2) @(posedge clk);
            $display("T=%0t Mid start bit: txd=%b (expect 0)", $time, uart_tx_pin);
            for (i = 0; i < 8; i = i + 1) begin
                repeat(BAUD_CLKS) @(posedge clk);
                $display("T=%0t Data[%0d] = %b", $time, i, uart_tx_pin);
                shift = {uart_tx_pin, shift[7:1]};
            end
            repeat(BAUD_CLKS) @(posedge clk);
            $display("T=%0t Stop bit: txd=%b (expect 1)", $time, uart_tx_pin);
            data = shift;
        end
    endtask

    reg [7:0] rx_byte;
    integer i;

    initial begin
        $display("=== System Test 3: Verbose receive ===");

        // Consume banner
        for (i = 0; i < 16; i = i + 1) begin
            uart_recv_verbose(rx_byte);
            $display("  Banner byte %0d: 0x%02X '%c'", i, rx_byte, rx_byte);
            $display("");
        end
        $display("Banner done.");

        repeat(200) @(posedge clk);

        // Send 'A'
        $display("=== Sending 'A' ===");
        uart_send_byte(8'h41);

        $display("=== Receiving cipher response ===");
        uart_recv_verbose(rx_byte);
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
