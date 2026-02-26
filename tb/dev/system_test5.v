`timescale 1ns / 1ps
// Test: send :? and dump the full response
module system_test5;
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

    initial begin
        $display("=== System Test 5: :? response dump ===");

        // Consume banner
        for (i = 0; i < 16; i = i + 1) begin
            uart_recv_byte(rx_byte);
        end
        $display("Banner consumed.");

        // Send ":"
        uart_send_byte(8'h3A);
        // Send "?"
        uart_send_byte(8'h3F);

        // Receive and print all bytes until we see "OK\r\n"
        $display("Response:");
        for (i = 0; i < 200; i = i + 1) begin
            uart_recv_byte(rx_byte);
            if (rx_byte >= 8'h20 && rx_byte < 8'h7F)
                $display("  [%0d] 0x%02X '%c'", i, rx_byte, rx_byte);
            else if (rx_byte == 8'h0D)
                $display("  [%0d] 0x%02X <CR>", i, rx_byte);
            else if (rx_byte == 8'h0A)
                $display("  [%0d] 0x%02X <LF>", i, rx_byte);
            else
                $display("  [%0d] 0x%02X", i, rx_byte);

            // Stop after OK\r\n
            if (rx_byte == 8'h0A && i > 0) begin
                // Check if previous chars were "OK\r"
                // Just stop after we see LF after what should be the OK line
            end
        end

        #10000;
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $finish(1);
    end
endmodule
