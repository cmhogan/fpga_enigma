`timescale 1ns / 1ps
module uart_test2;
    reg clk = 0;
    always #41.667 clk = ~clk;
    
    reg rst_n = 1'b1;
    reg [7:0] tx_byte;
    reg tx_start = 0;
    wire txd, tx_busy;
    
    uart_tx uut(
        .clk(clk), .rst_n(rst_n), .tx_byte(tx_byte),
        .tx_start(tx_start), .txd(txd), .tx_busy(tx_busy)
    );
    
    // Receive using clock-based sampling instead of time delays
    task uart_recv_clk;
        output [7:0] data;
        integer i, j;
        reg [7:0] shift;
        begin
            shift = 8'd0;
            // Wait for falling edge of txd (start bit)
            @(negedge txd);
            // Wait 52 clocks to midpoint of start bit
            for (j = 0; j < 52; j = j + 1) @(posedge clk);
            // Sample 8 data bits
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 104; j = j + 1) @(posedge clk);
                shift = {txd, shift[7:1]};
                $display("  bit %0d: txd=%b", i, txd);
            end
            // Stop bit
            for (j = 0; j < 104; j = j + 1) @(posedge clk);
            data = shift;
        end
    endtask
    
    reg [7:0] received;
    initial begin
        #100;
        tx_byte = 8'h42; // 'B' = 01000010
        @(posedge clk);
        tx_start = 1;
        @(posedge clk);
        tx_start = 0;
        
        uart_recv_clk(received);
        $display("Sent 0x42 ('B'), Received 0x%02X ('%c')", received, received);
        
        // Test another byte
        tx_byte = 8'h41; // 'A' = 01000001
        @(posedge clk);
        tx_start = 1;
        @(posedge clk);
        tx_start = 0;
        
        uart_recv_clk(received);
        $display("Sent 0x41 ('A'), Received 0x%02X ('%c')", received, received);
        
        #1000;
        $finish;
    end
endmodule
