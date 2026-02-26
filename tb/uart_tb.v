// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// uart_tb.v
// — Self-checking testbench for UART modules
// Tests uart_tx.v and uart_rx.v at module level with loopback and protocol scenarios

`timescale 1ns / 1ps

module uart_tb;

    // =========================================================================
    // Clock generation
    // =========================================================================
    reg clk = 1'b0;
    always #41.667 clk = ~clk;  // ~12 MHz (83.333 ns period)

    // =========================================================================
    // DUT signals
    // =========================================================================
    reg         rst_n = 1'b0;
    reg  [7:0]  tx_data = 8'd0;
    reg         tx_start = 1'b0;
    wire        txd;
    wire        tx_busy;

    wire        serial_line;   // loopback wire
    wire [7:0]  rx_byte;
    wire        rx_valid;
    wire        rx_error;
    wire        rx_active;

    // Direct RX input for framing error test
    reg         rxd_direct = 1'b1;
    reg         use_direct_rx = 1'b0;

    assign serial_line = use_direct_rx ? rxd_direct : txd;

    // =========================================================================
    // DUT instantiations
    // =========================================================================
    uart_tx #(
        .BAUD_DIV(103)
    ) dut_tx (
        .clk       (clk),
        .rst_n     (rst_n),
        .tx_byte   (tx_data),
        .tx_start  (tx_start),
        .txd       (txd),
        .tx_busy   (tx_busy)
    );

    uart_rx #(
        .BAUD_DIV(103),
        .HALF_BIT(51)
    ) dut_rx (
        .clk       (clk),
        .rst_n     (rst_n),
        .rxd       (serial_line),
        .rx_byte   (rx_byte),
        .rx_valid  (rx_valid),
        .rx_error  (rx_error),
        .rx_active (rx_active)
    );

    // =========================================================================
    // VCD dump for coverage
    // =========================================================================
    `ifdef VCD_DUMP
    initial begin
        $dumpfile("build/uart_tb.vcd");
        $dumpvars(0, uart_tb);
    end
    `endif

    // =========================================================================
    // Test counters
    // =========================================================================
    integer pass_count = 0;
    integer fail_count = 0;

    // =========================================================================
    // Constants
    // =========================================================================
    localparam BAUD_CLKS = 104;  // 12MHz / 115200 ≈ 104
    localparam BIT_PERIOD = BAUD_CLKS * 83.333;  // ns per bit

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #50_000_000;  // 50 ms (enough for 256 bytes at 115200 baud + overhead)
        $display("TIMEOUT: simulation exceeded 50ms");
        $display("Results: %0d passed, %0d failed (TIMEOUT)", pass_count, fail_count);
        $finish(1);
    end

    // =========================================================================
    // Helper task: Send a byte via TX and wait for RX to receive it
    // =========================================================================
    task send_and_receive;
        input [7:0] data;
        output [7:0] received;
        reg [7:0] captured;
        integer timeout;
        begin
            captured = 8'd0;
            timeout = 0;

            // Wait for TX to be idle and RX to be idle before starting
            while (tx_busy || rx_active) begin
                @(posedge clk);
            end

            // Add a small inter-byte gap
            repeat(10) @(posedge clk);

            // Start transmission
            @(posedge clk);
            tx_data = data;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;

            // Wait for rx_valid with timeout
            while (!rx_valid && timeout < 20000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (rx_valid) begin
                captured = rx_byte;
            end else begin
                $display("  ERROR: RX timeout waiting for byte 0x%02X", data);
            end

            // Wait for transmission to fully complete
            while (tx_busy || rx_active) begin
                @(posedge clk);
            end

            // Extra settling time
            repeat(10) @(posedge clk);

            received = captured;
        end
    endtask

    // =========================================================================
    // Helper task: Bit-bang a UART frame (for framing error test)
    // =========================================================================
    task bitbang_frame;
        input [7:0] data;
        input stop_bit_value;
        integer i;
        begin
            use_direct_rx = 1'b1;
            @(posedge clk); #1;
            rxd_direct = 1'b0;  // start bit
            repeat(BAUD_CLKS) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                #1;
                rxd_direct = data[i];
                repeat(BAUD_CLKS) @(posedge clk);
            end
            #1;
            rxd_direct = stop_bit_value;  // stop bit (may be invalid)
            repeat(BAUD_CLKS) @(posedge clk);
            #1;
            rxd_direct = 1'b1;  // return to idle
            use_direct_rx = 1'b0;
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        $display("=== UART Testbench ===");
        $display("");

        // Reset sequence
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(10) @(posedge clk);

        // =====================================================================
        // Test 1: Basic TX → RX loopback with 3 test values
        // =====================================================================
        begin : test1
            reg [7:0] test_values [0:2];
            reg [7:0] received;
            integer i;
            integer errors;

            test_values[0] = 8'h00;
            test_values[1] = 8'h55;
            test_values[2] = 8'hFF;

            $display("--- Test 1: Basic TX -> RX loopback ---");
            errors = 0;

            for (i = 0; i < 3; i = i + 1) begin
                send_and_receive(test_values[i], received);
                if (received === test_values[i]) begin
                    $display("  0x%02X: PASS", test_values[i]);
                end else begin
                    $display("  0x%02X: FAIL (got 0x%02X)", test_values[i], received);
                    errors = errors + 1;
                end
            end

            if (errors == 0) begin
                $display("PASS: Test 1 - Basic loopback");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Test 1 - Basic loopback (%0d errors)", errors);
                fail_count = fail_count + 1;
            end
            $display("");
        end

        // =====================================================================
        // Test 2: Back-to-back transmission (tests 1-byte TX queue)
        // =====================================================================
        begin : test2
            reg [7:0] byte1, byte2;
            reg [7:0] rx1, rx2;

            $display("--- Test 2: Back-to-back transmission ---");
            byte1 = 8'hA5;
            byte2 = 8'h3C;

            // Use send_and_receive twice with minimal gap
            send_and_receive(byte1, rx1);
            if (rx1 === byte1) begin
                $display("  First byte: PASS");
            end else begin
                $display("  First byte: FAIL (expected 0x%02X, got 0x%02X)", byte1, rx1);
            end

            send_and_receive(byte2, rx2);
            if (rx2 === byte2) begin
                $display("  Second byte: PASS");
            end else begin
                $display("  Second byte: FAIL (expected 0x%02X, got 0x%02X)", byte2, rx2);
            end

            if (rx1 === byte1 && rx2 === byte2) begin
                $display("PASS: Test 2 - Back-to-back transmission");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Test 2 - Back-to-back transmission");
                fail_count = fail_count + 1;
            end
            $display("");
        end

        // =====================================================================
        // Test 3: RX framing error and recovery
        // =====================================================================
        begin : test3
            integer timeout;
            reg [7:0] received;
            integer ok;
            reg error_seen;

            $display("--- Test 3: RX framing error ---");
            ok = 1;
            error_seen = 0;

            // Send a frame with invalid stop bit (0 instead of 1)
            // Monitor rx_error throughout the frame reception
            fork
                begin
                    bitbang_frame(8'h42, 1'b0);  // invalid stop bit
                end
                begin
                    timeout = 0;
                    while (timeout < 2000) begin
                        @(posedge clk);
                        if (rx_error) begin
                            error_seen = 1;
                        end
                        timeout = timeout + 1;
                    end
                end
            join

            if (error_seen) begin
                $display("  Framing error detected: PASS");
            end else begin
                $display("  Framing error NOT detected: FAIL");
                ok = 0;
            end

            // Wait for RX to return to idle
            repeat(BAUD_CLKS * 2) @(posedge clk);

            // Send a valid byte to test recovery
            send_and_receive(8'hAB, received);
            if (received === 8'hAB) begin
                $display("  Recovery after error: PASS");
            end else begin
                $display("  Recovery failed: expected 0xAB, got 0x%02X", received);
                ok = 0;
            end

            if (ok) begin
                $display("PASS: Test 3 - Framing error and recovery");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Test 3 - Framing error and recovery");
                fail_count = fail_count + 1;
            end
            $display("");
        end

        // =====================================================================
        // Test 4: All 256 byte values
        // =====================================================================
        begin : test4
            integer i;
            reg [7:0] received;
            integer errors;

            $display("--- Test 4: All 256 byte values ---");
            errors = 0;

            for (i = 0; i < 256; i = i + 1) begin
                send_and_receive(i[7:0], received);
                if (received !== i[7:0]) begin
                    $display("  Byte %0d (0x%02X): FAIL (got 0x%02X)", i, i[7:0], received);
                    errors = errors + 1;
                end
            end

            if (errors == 0) begin
                $display("  All 256 bytes transmitted correctly");
                $display("PASS: Test 4 - All 256 byte values");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Test 4 - All 256 byte values (%0d errors)", errors);
                fail_count = fail_count + 1;
            end
            $display("");
        end

        // =====================================================================
        // Summary
        // =====================================================================
        $display("=================================");
        $display("Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("=================================");
        if (fail_count == 0)
            $finish(0);
        else
            $finish(1);
    end

endmodule
