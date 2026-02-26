`timescale 1ns / 1ns
module uart_test;
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
    
    // Monitor txd transitions
    reg prev_txd = 1;
    always @(posedge clk) begin
        if (txd !== prev_txd) begin
            $display("t=%0t txd changed to %b (bit_cnt=%0d baud_cnt=%0d)", 
                $time, txd, uut.bit_cnt, uut.baud_cnt);
        end
        prev_txd <= txd;
    end
    
    // Receive task
    localparam BIT_NS = 104 * 83.333;
    task uart_recv;
        output [7:0] data;
        integer i;
        reg [7:0] shift;
        begin
            shift = 8'd0;
            @(negedge txd);
            #(BIT_NS / 2);
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_NS);
                shift = {txd, shift[7:1]};
                $display("  sample bit %0d: txd=%b shift=0x%02X", i, txd, shift);
            end
            #(BIT_NS);
            data = shift;
        end
    endtask
    
    reg [7:0] received;
    initial begin
        #100;
        tx_byte = 8'h42; // 'B'
        @(posedge clk);
        tx_start = 1;
        @(posedge clk);
        tx_start = 0;
        
        uart_recv(received);
        $display("Sent 0x42, Received 0x%02X ('%c')", received, received);
        
        #1000;
        $finish;
    end
endmodule
