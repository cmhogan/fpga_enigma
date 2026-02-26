`timescale 1ns / 1ps
module uart_test4;
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
    
    integer i;
    reg [7:0] received;
    
    initial begin
        #100;
        tx_byte = 8'h42;
        @(posedge clk); #1;
        tx_start = 1;
        @(posedge clk); #1;
        tx_start = 0;
        
        // Wait for start bit to appear
        wait(txd == 0);
        
        // From here, count exactly 52 posedges to get to midpoint of start bit
        for (i = 0; i < 52; i = i + 1) @(posedge clk);
        $display("Midpoint start bit: txd=%b (expect 0)", txd);
        
        // Sample 8 data bits at 104-clock intervals
        for (i = 0; i < 8; i = i + 1) begin
            repeat(104) @(posedge clk);
            received[i] = txd;
            $display("Data[%0d] = %b", i, txd);
        end
        
        // Stop bit
        repeat(104) @(posedge clk);
        $display("Stop bit: txd=%b (expect 1)", txd);
        
        $display("Received: 0x%02X (expected 0x42 = '%c')", received, received);
        
        #1000;
        $finish;
    end
endmodule
