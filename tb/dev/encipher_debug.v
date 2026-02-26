`timescale 1ns / 1ns
module encipher_debug;
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
    
    localparam BIT_NS = 104 * 83.333;
    
    task uart_send;
        input [7:0] data;
        integer i;
        begin
            uart_rx_pin = 1'b0; #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_pin = data[i]; #(BIT_NS);
            end
            uart_rx_pin = 1'b1; #(BIT_NS);
            #(BIT_NS);
        end
    endtask
    
    task uart_recv;
        output [7:0] data;
        integer i;
        reg [7:0] shift;
        begin
            shift = 8'd0;
            @(negedge uart_tx_pin);
            #(BIT_NS / 2);
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_NS);
                shift = {uart_tx_pin, shift[7:1]};
            end
            #(BIT_NS);
            data = shift;
        end
    endtask
    
    reg [7:0] ch;
    integer i;
    
    initial begin
        $dumpfile("encipher_debug.vcd");
        $dumpvars(0, encipher_debug);
        
        // Wait for banner (16 chars)
        for (i = 0; i < 16; i = i + 1) uart_recv(ch);
        $display("Banner done.");
        
        // Add a small delay
        #(BIT_NS * 2);
        
        // Monitor FSM state during encipher
        $display("Sending 'A'...");
        $monitor("t=%0t state=%0d pt_idx=%0d mid=%0d ct=%0d step=%b load=%b rx_valid=%b",
            $time, dut.u_fsm.state, dut.u_fsm.pt_index, dut.u_fsm.mid_letter_reg,
            dut.u_fwd.mid_letter, dut.u_fsm.step_pulse, dut.u_fsm.load_pulse,
            dut.u_uart_rx.rx_valid);
        uart_send("A");
        
        // Wait for response
        uart_recv(ch);
        $display("Received: 0x%02X = '%c'", ch, ch);
        
        #1000;
        $finish;
    end
    
    // Timeout
    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish(1);
    end
endmodule
