`timescale 1ns / 1ps
module uart_test3;
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
    
    integer clk_count = 0;
    always @(posedge clk) clk_count = clk_count + 1;
    
    // Track all txd transitions
    reg prev_txd = 1;
    integer start_clk;
    always @(posedge clk) begin
        if (txd !== prev_txd) begin
            $display("CLK %0d: txd %b->%b (state=%b bit_cnt=%0d baud=%0d shift=0b%010b)",
                clk_count, prev_txd, txd, uut.state, uut.bit_cnt, uut.baud_cnt, uut.shift_reg);
        end
        prev_txd <= txd;
    end
    
    initial begin
        #100;
        tx_byte = 8'h42;
        @(posedge clk);
        $display("CLK %0d: tx_start asserted, tx_byte=0x%02X", clk_count, tx_byte);
        tx_start = 1;
        @(posedge clk);
        tx_start = 0;
        
        // Wait for tx to finish
        @(negedge tx_busy);
        @(posedge clk);
        $display("CLK %0d: tx_busy deasserted", clk_count);
        
        #1000;
        $finish;
    end
endmodule
