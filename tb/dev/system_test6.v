`timescale 1ns / 1ps
// Test :? response with FIFO-based receiver
module system_test6;
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

    // FIFO-based receiver
    reg [7:0] rx_fifo [0:255];
    integer rx_wr_ptr = 0;
    integer rx_rd_ptr = 0;

    initial begin : bg_receiver
        reg [7:0] shift;
        integer bi;
        forever begin
            @(negedge uart_tx_pin);
            repeat(BAUD_CLKS / 2) @(posedge clk);
            shift = 8'd0;
            for (bi = 0; bi < 8; bi = bi + 1) begin
                repeat(BAUD_CLKS) @(posedge clk);
                shift = {uart_tx_pin, shift[7:1]};
            end
            repeat(BAUD_CLKS) @(posedge clk);
            rx_fifo[rx_wr_ptr[7:0]] = shift;
            rx_wr_ptr = rx_wr_ptr + 1;
        end
    end

    task get_byte;
        output [7:0] data;
        begin
            wait(rx_rd_ptr < rx_wr_ptr);
            data = rx_fifo[rx_rd_ptr[7:0]];
            rx_rd_ptr = rx_rd_ptr + 1;
        end
    endtask

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

    reg [7:0] rx_byte;
    integer i;

    initial begin
        $display("=== System Test 6: :? response dump (FIFO) ===");

        // Consume banner
        for (i = 0; i < 16; i = i + 1) get_byte(rx_byte);
        $display("Banner consumed.");

        // Send ":"
        uart_send_byte(8'h3A);
        // Send "?"
        uart_send_byte(8'h3F);

        // Receive and print bytes until we get enough
        $display("Response:");
        for (i = 0; i < 100; i = i + 1) begin
            get_byte(rx_byte);
            if (rx_byte >= 8'h20 && rx_byte < 8'h7F)
                $display("  [%0d] 0x%02X '%c'", i, rx_byte, rx_byte);
            else if (rx_byte == 8'h0D)
                $display("  [%0d] 0x0D <CR>", i);
            else if (rx_byte == 8'h0A) begin
                $display("  [%0d] 0x0A <LF>", i);
            end else
                $display("  [%0d] 0x%02X", i, rx_byte);
        end

        #10000;
        $finish;
    end

    initial begin
        #100_000_000; // 100ms
        $display("TIMEOUT at byte %0d (wr=%0d rd=%0d)", i, rx_wr_ptr, rx_rd_ptr);
        $finish(1);
    end
endmodule
