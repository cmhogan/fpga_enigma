`timescale 1ns / 1ps
// Debug: trace FSM states and UART TX activity during encipher
module system_test2;
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

    // Monitor FSM state transitions
    reg [3:0] prev_state = 4'hF;
    always @(posedge clk) begin
        if (dut.u_fsm.state !== prev_state) begin
            $display("T=%0t FSM: state %0d->%0d  tx_byte=0x%02X tx_start=%b tx_busy=%b",
                     $time, prev_state, dut.u_fsm.state,
                     dut.u_fsm.tx_byte, dut.u_fsm.tx_start, dut.u_uart_tx.tx_busy);
            prev_state <= dut.u_fsm.state;
        end
    end

    // Monitor UART TX transitions
    reg prev_txd = 1;
    always @(posedge clk) begin
        if (uart_tx_pin !== prev_txd) begin
            $display("T=%0t TXD: %b->%b", $time, prev_txd, uart_tx_pin);
            prev_txd <= uart_tx_pin;
        end
    end

    initial begin
        $display("=== System Test 2: Debug encipher ===");

        // Consume banner
        for (i = 0; i < 16; i = i + 1) begin
            uart_recv_byte(rx_byte);
        end
        $display("Banner consumed. FSM should be IDLE (state=2).");

        // Wait a bit for FSM to settle
        repeat(200) @(posedge clk);

        // Send 'A'
        $display("T=%0t Sending 'A'...", $time);
        uart_send_byte(8'h41);

        $display("T=%0t Waiting for response...", $time);
        uart_recv_byte(rx_byte);
        $display("Received: 0x%02X ('%c')", rx_byte, rx_byte);

        #10000;
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $finish(1);
    end
endmodule
