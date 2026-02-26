`timescale 1ns / 1ns
module debug_tb;
    reg clk = 0;
    always #41.667 clk = ~clk;
    
    reg uart_rx_pin = 1'b1;
    wire uart_tx_pin;
    wire led_d1, led_d2, led_d3, led_d4, led_d5;
    
    enigma_top dut (
        .clk(clk), .ext_rst_n(1'b1), .uart_rx(uart_rx_pin), .uart_tx(uart_tx_pin),
        .led_d1(led_d1), .led_d2(led_d2), .led_d3(led_d3),
        .led_d4(led_d4), .led_d5(led_d5)
    );
    
    initial begin
        $dumpfile("debug.vcd");
        $dumpvars(0, debug_tb);
        // Monitor FSM state
        $monitor("t=%0t state=%0d banner_idx=%0d tx_start=%b tx_busy=%b txd=%b delay=%0d",
            $time, dut.u_fsm.state, dut.u_fsm.banner_idx,
            dut.u_fsm.tx_start, dut.u_uart_tx.tx_busy, uart_tx_pin,
            dut.u_fsm.delay_cnt);
        #2_500_000;  // 2.5 ms - enough for delay + a few banner chars
        $display("DONE");
        $finish;
    end
endmodule
