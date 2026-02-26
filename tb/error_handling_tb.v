// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// error_handling_tb.v
// — Self-checking testbench for FPGA Enigma I error paths
// Tests error/rejection scenarios in the FSM that are NOT covered by enigma_tb.v
// Architecture: Follows EXACT patterns from enigma_tb.v with background UART receiver + FIFO

`timescale 1ns / 1ps

module error_handling_tb;

    // =========================================================================
    // Clock and DUT
    // =========================================================================
    reg clk = 1'b0;
    always #41.667 clk = ~clk;  // ~12 MHz (83.333 ns period)

    reg  uart_rx_pin = 1'b1;    // idle HIGH
    wire uart_tx_pin;
    wire led_d1, led_d2, led_d3, led_d4, led_d5;

    enigma_top dut (
        .clk       (clk),
        .ext_rst_n (1'b1),
        .uart_rx   (uart_rx_pin),
        .uart_tx   (uart_tx_pin),
        .led_d1    (led_d1),
        .led_d2    (led_d2),
        .led_d3    (led_d3),
        .led_d4    (led_d4),
        .led_d5    (led_d5)
    );

    // =========================================================================
    // VCD dump for coverage
    // =========================================================================
    `ifdef VCD_DUMP
    initial begin
        $dumpfile("build/error_handling_tb.vcd");
        $dumpvars(0, error_handling_tb);
    end
    `endif

    // =========================================================================
    // Baud rate constants
    // =========================================================================
    localparam BAUD_CLKS = 104;  // 12MHz / 115200 ≈ 104

    // =========================================================================
    // Background UART receiver → byte FIFO
    // =========================================================================
    reg [7:0] rx_fifo [0:255];
    integer   rx_wr_ptr = 0;
    integer   rx_rd_ptr = 0;

    // Continuous receiver: runs forever, depositing bytes into rx_fifo
    initial begin : bg_receiver
        reg [7:0] shift;
        integer bi;
        forever begin
            @(negedge uart_tx_pin);   // wait for start bit
            repeat(BAUD_CLKS / 2) @(posedge clk);  // midpoint of start bit
            shift = 8'd0;
            for (bi = 0; bi < 8; bi = bi + 1) begin
                repeat(BAUD_CLKS) @(posedge clk);
                shift = {uart_tx_pin, shift[7:1]};
            end
            repeat(BAUD_CLKS) @(posedge clk);  // stop bit
            rx_fifo[rx_wr_ptr[7:0]] = shift;
            rx_wr_ptr = rx_wr_ptr + 1;
        end
    end

    // get_byte: blocks until a byte is available, then returns it
    task get_byte;
        output [7:0] data;
        begin
            wait(rx_rd_ptr < rx_wr_ptr);
            data = rx_fifo[rx_rd_ptr[7:0]];
            rx_rd_ptr = rx_rd_ptr + 1;
        end
    endtask

    // =========================================================================
    // Test counters
    // =========================================================================
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    // =========================================================================
    // UART send task: bit-bang one byte LSB-first (clock-based timing)
    // =========================================================================
    task uart_send;
        input [7:0] data;
        integer i;
        begin
            @(posedge clk); #1;
            uart_rx_pin = 1'b0;  // start bit
            repeat(BAUD_CLKS) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                #1;
                uart_rx_pin = data[i];
                repeat(BAUD_CLKS) @(posedge clk);
            end
            #1;
            uart_rx_pin = 1'b1;  // stop bit
            repeat(BAUD_CLKS) @(posedge clk);
        end
    endtask

    // =========================================================================
    // Helper: send a string
    // =========================================================================
    task send_string;
        input [8*80-1:0] str;  // up to 80 chars
        input integer len;
        integer i;
        reg [7:0] ch;
        begin
            for (i = 0; i < len; i = i + 1) begin
                ch = str >> ((len - 1 - i) * 8);
                uart_send(ch[7:0]);
            end
        end
    endtask

    // =========================================================================
    // Helper: send command with CR, expect OK\r\n
    // =========================================================================
    task send_command;
        input [8*20-1:0] cmd;
        input integer len;
        reg [7:0] r0, r1, r2, r3;
        begin
            send_string(cmd, len);
            uart_send(8'h0D);  // CR
            // Expect "OK\r\n"
            get_byte(r0);
            get_byte(r1);
            get_byte(r2);
            get_byte(r3);
            if (r0 !== "O" || r1 !== "K" || r2 !== 8'h0D || r3 !== 8'h0A) begin
                $display("  ERROR: expected OK\\r\\n, got 0x%02X 0x%02X 0x%02X 0x%02X",
                         r0, r1, r2, r3);
            end
        end
    endtask

    // =========================================================================
    // Helper: send zero-arg command (e.g. ":G", ":F", ":?")
    // These execute immediately on the opcode byte — no CR needed
    // =========================================================================
    task send_zero_arg_cmd;
        input [7:0] opcode;
        begin
            uart_send(":"); // 0x3A
            uart_send(opcode);
        end
    endtask

    // =========================================================================
    // Helper: wait for and consume banner "ENIGMA I READY\r\n"
    // =========================================================================
    task wait_for_banner;
        reg [7:0] ch;
        integer i;
        begin
            for (i = 0; i < 14; i = i + 1) begin
                get_byte(ch);
            end
            // CR
            get_byte(ch);
            if (ch !== 8'h0D) $display("  WARNING: expected CR in banner, got 0x%02X", ch);
            // LF
            get_byte(ch);
            if (ch !== 8'h0A) $display("  WARNING: expected LF in banner, got 0x%02X", ch);
        end
    endtask

    // =========================================================================
    // Helper: wait for OK\r\n
    // =========================================================================
    task wait_for_ok;
        reg [7:0] r0, r1, r2, r3;
        begin
            get_byte(r0); get_byte(r1); get_byte(r2); get_byte(r3);
            if (r0 !== "O" || r1 !== "K" || r2 !== 8'h0D || r3 !== 8'h0A)
                $display("  ERROR: expected OK, got 0x%02X('%c') 0x%02X('%c') 0x%02X 0x%02X",
                         r0, r0, r1, r1, r2, r3);
        end
    endtask

    // =========================================================================
    // Helper: expect ERR\r\n (5 bytes: E, R, R, 0x0D, 0x0A)
    // =========================================================================
    task expect_err;
        input [8*40-1:0] label;
        reg [7:0] e0, e1, e2, e3, e4;
        reg ok;
        begin
            ok = 1'b1;
            get_byte(e0); get_byte(e1); get_byte(e2); get_byte(e3); get_byte(e4);
            if (e0 !== "E" || e1 !== "R" || e2 !== "R" || e3 !== 8'h0D || e4 !== 8'h0A) begin
                $display("  ERROR: expected ERR\\r\\n, got 0x%02X('%c') 0x%02X('%c') 0x%02X('%c') 0x%02X 0x%02X",
                         e0, e0, e1, e1, e2, e2, e3, e4);
                ok = 1'b0;
            end
            if (ok) begin
                $display("PASS: %0s", label);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s", label);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // Helper: send :F (factory reset), consume banner + OK
    // =========================================================================
    task factory_reset;
        begin
            send_zero_arg_cmd("F");
            wait_for_banner;
            wait_for_ok;
        end
    endtask

    // =========================================================================
    // Helper: send :G (grundstellung reset), consume OK
    // =========================================================================
    task grundstellung_reset;
        begin
            send_zero_arg_cmd("G");
            wait_for_ok;
        end
    endtask

    // =========================================================================
    // Helper: encipher a string and check output
    // =========================================================================
    task encipher_and_check;
        input [8*40-1:0] plaintext;
        input integer pt_len;
        input [8*40-1:0] expected_ct;
        input [8*40-1:0] label;
        integer i;
        reg [7:0] pt_ch, ct_ch, exp_ch;
        reg ok;
        begin
            ok = 1'b1;
            for (i = 0; i < pt_len; i = i + 1) begin
                pt_ch = plaintext >> ((pt_len - 1 - i) * 8);
                uart_send(pt_ch[7:0]);
                get_byte(ct_ch);
                exp_ch = expected_ct >> ((pt_len - 1 - i) * 8);
                if (ct_ch !== exp_ch[7:0]) begin
                    $display("  MISMATCH at char %0d: sent '%c', expected '%c' got '%c' (0x%02X)",
                             i, pt_ch[7:0], exp_ch[7:0], ct_ch, ct_ch);
                    ok = 1'b0;
                end
            end
            if (ok) begin
                $display("PASS: %0s", label);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s", label);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #200_000_000_000; // 200 ms
        $display("TIMEOUT: simulation exceeded 200ms");
        $display("Results: %0d passed, %0d failed (TIMEOUT)", pass_count, fail_count);
        $finish(1);
    end

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        $display("=== FPGA Enigma I Error Handling Testbench ===");
        $display("");

        // Wait for startup banner
        wait_for_banner;
        $display("Banner received OK.");
        $display("");

        // =====================================================================
        // Test 1: Duplicate rotor rejection
        // =====================================================================
        test_num = 1;
        $display("--- Test 1: Duplicate rotor rejection (:R112) ---");
        send_string(":R112", 5);
        uart_send(8'h0D);  // CR
        expect_err("Test 1: Duplicate rotor (1,1,2) rejected");
        // Verify machine still works (reset positions so we know expected output)
        grundstellung_reset;
        encipher_and_check("A", 1, "B", "Test 1: Recovery check");
        $display("");

        // =====================================================================
        // Test 2: Out-of-range rotor
        // =====================================================================
        test_num = 2;
        $display("--- Test 2: Out-of-range rotor (:R126) ---");
        factory_reset;
        send_string(":R126", 5);
        uart_send(8'h0D);  // CR
        expect_err("Test 2: Out-of-range rotor (6) rejected");
        grundstellung_reset;
        encipher_and_check("A", 1, "B", "Test 2: Recovery check");
        $display("");

        // =====================================================================
        // Test 3: Self-pair plugboard
        // =====================================================================
        test_num = 3;
        $display("--- Test 3: Self-pair plugboard (:SAA) ---");
        factory_reset;
        send_string(":SAA", 4);
        uart_send(8'h0D);  // CR
        expect_err("Test 3: Self-pair plugboard (A-A) rejected");
        grundstellung_reset;
        encipher_and_check("A", 1, "B", "Test 3: Recovery check");
        $display("");

        // =====================================================================
        // Test 4: Wrong reflector
        // =====================================================================
        test_num = 4;
        $display("--- Test 4: Wrong reflector (:UC) ---");
        factory_reset;
        send_string(":UC", 3);
        uart_send(8'h0D);  // CR
        expect_err("Test 4: Wrong reflector (C) rejected");
        grundstellung_reset;
        encipher_and_check("A", 1, "B", "Test 4: Recovery check");
        $display("");

        // =====================================================================
        // Test 5: Unknown opcode
        // Note: ":X" — unknown opcode triggers ERR immediately in CMD_OPCODE.
        // Do NOT send CR after, since FSM already moved to CMD_RESP and the
        // CR would arrive in IDLE and be silently ignored (is_crlf, not alpha).
        // =====================================================================
        test_num = 5;
        $display("--- Test 5: Unknown opcode (:X) ---");
        factory_reset;
        uart_send(":");
        uart_send("X");
        expect_err("Test 5: Unknown opcode (X) rejected");
        grundstellung_reset;
        encipher_and_check("A", 1, "B", "Test 5: Recovery check");
        $display("");

        // =====================================================================
        // Test 6: Lowercase normalization
        // =====================================================================
        test_num = 6;
        $display("--- Test 6: Lowercase normalization ---");
        factory_reset;
        grundstellung_reset;
        // Send lowercase "hello" and expect same output as uppercase "HELLO"
        // At ground settings (AAA, rotors I-II-III, no plugboard):
        // pyenigma: HELLO -> ILBDA
        encipher_and_check("hello", 5, "ILBDA", "Test 6: Lowercase normalized to uppercase");
        $display("");

        // =====================================================================
        // Test 7: Non-alpha ignored in IDLE
        // =====================================================================
        test_num = 7;
        $display("--- Test 7: Non-alpha ignored in IDLE ---");
        factory_reset;
        grundstellung_reset;
        // Send digit '1', wait briefly, then send 'A'
        // Digit produces no response; 'A' -> 'B' (first char at AAA)
        uart_send("1");
        repeat(5000) @(posedge clk);  // wait briefly
        uart_send("A");
        begin : test7_check
            reg [7:0] response;
            get_byte(response);
            if (response == "B") begin
                $display("PASS: Test 7: Non-alpha (1) ignored, A->B");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Test 7: expected 'B', got 0x%02X ('%c')", response, response);
                fail_count = fail_count + 1;
            end
        end
        $display("");

        // =====================================================================
        // Test 8: Already-wired letter in plugboard
        // =====================================================================
        test_num = 8;
        $display("--- Test 8: Already-wired letter ---");
        factory_reset;
        // Add pair A-B
        send_command(":SAB", 4);
        // Try to add A-C (A already wired to B)
        send_string(":SAC", 4);
        uart_send(8'h0D);
        expect_err("Test 8: Already-wired letter (A) rejected");
        // Verify machine still works (use known vector: AAAAA at ground+AB plug)
        grundstellung_reset;
        uart_send("C");
        begin : test8_recovery
            reg [7:0] response;
            get_byte(response);
            if (response >= "A" && response <= "Z") begin
                $display("PASS: Test 8: Recovery check (enciphered C -> '%c')", response);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Test 8: Recovery check (got 0x%02X)", response);
                fail_count = fail_count + 1;
            end
        end
        $display("");

        // =====================================================================
        // Test 9: Plugboard full (attempt 14th pair when all letters used)
        // =====================================================================
        test_num = 9;
        $display("--- Test 9: Plugboard full (14th pair) ---");
        factory_reset;
        // Add 13 pairs (AB, CD, EF, GH, IJ, KL, MN, OP, QR, ST, UV, WX, YZ)
        // This uses all 26 letters
        send_command(":SAB", 4);
        send_command(":SCD", 4);
        send_command(":SEF", 4);
        send_command(":SGH", 4);
        send_command(":SIJ", 4);
        send_command(":SKL", 4);
        send_command(":SMN", 4);
        send_command(":SOP", 4);
        send_command(":SQR", 4);
        send_command(":SST", 4);
        send_command(":SUV", 4);
        send_command(":SWX", 4);
        send_command(":SYZ", 4);
        // Now all 26 letters are wired. Attempt to add any pair -> ERR
        send_string(":SAB", 4);  // both A and B are already wired
        uart_send(8'h0D);
        expect_err("Test 9: Plugboard full (A,B both wired) rejected");
        // Verify machine still works (send a letter, any letter)
        // With full plugboard, cipher output will be different, but should still respond
        uart_send("A");
        begin : test9_recovery
            reg [7:0] response;
            get_byte(response);
            // We don't care what the output is, just that we get a response
            $display("PASS: Test 9: Recovery check (got response 0x%02X)", response);
            pass_count = pass_count + 1;
        end
        $display("");

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
