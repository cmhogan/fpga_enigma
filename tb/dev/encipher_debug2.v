`timescale 1ns / 1ns
module encipher_debug2;
    reg clk = 0;
    always #41.667 clk = ~clk;
    reg uart_rx_pin = 1'b1;
    wire uart_tx_pin;
    wire led_d1, led_d2, led_d3, led_d4, led_d5;
    enigma_top dut(
        .clk(clk), .ext_rst_n(1'b1), .uart_rx(uart_rx_pin), .uart_tx(uart_tx_pin),
        .led_d1(led_d1), .led_d2(led_d2), .led_d3(led_d3),
        .led_d4(led_d4), .led_d5(led_d5)
    );
    localparam BIT_NS = 104 * 83.333;
    task uart_send; input [7:0] data; integer i; begin
        uart_rx_pin = 1'b0; #(BIT_NS);
        for (i=0; i<8; i=i+1) begin uart_rx_pin = data[i]; #(BIT_NS); end
        uart_rx_pin = 1'b1; #(BIT_NS); #(BIT_NS);
    end endtask
    task uart_recv; output [7:0] data; integer i; reg [7:0] shift; begin
        shift = 8'd0; @(negedge uart_tx_pin); #(BIT_NS / 2);
        for (i=0; i<8; i=i+1) begin #(BIT_NS); shift = {uart_tx_pin, shift[7:1]}; end
        #(BIT_NS); data = shift;
    end endtask
    
    reg [7:0] ch;
    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1) uart_recv(ch);
        #(BIT_NS * 2);
        
        // Check positions before sending
        $display("Before send: pos_l=%0d pos_m=%0d pos_r=%0d", dut.pos_l, dut.pos_m, dut.pos_r);
        $display("Rotor sel: L=%0d M=%0d R=%0d", dut.rotor_sel_l, dut.rotor_sel_m, dut.rotor_sel_r);
        $display("Ring: L=%0d M=%0d R=%0d", dut.ring_l, dut.ring_m, dut.ring_r);
        
        uart_send("A");
        
        // Wait for tx response to start
        @(negedge uart_tx_pin);
        $display("After encipher: pos_l=%0d pos_m=%0d pos_r=%0d", dut.pos_l, dut.pos_m, dut.pos_r);
        $display("FSM pt_index=%0d mid_letter_reg=%0d", dut.u_fsm.pt_index, dut.u_fsm.mid_letter_reg);
        $display("Fwd mid_letter=%0d", dut.u_fwd.mid_letter);
        $display("Bwd ct_index=%0d", dut.u_bwd.ct_index);
        $display("tx_byte=0x%02X", dut.u_fsm.tx_byte);
        
        uart_recv(ch);
        // The recv will have consumed the byte from above negedge
        // Actually we already detected negedge, so recv starts fresh
        // Let me fix: just wait for complete byte
        $display("Received: 0x%02X = '%c'", ch, ch);
        
        $finish;
    end
    initial begin #50_000_000; $finish(1); end
endmodule
