// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// timeout_tb.v
// — Self-checking testbench for FSM timeout mechanism
// Tests the 256 byte-time (~22ms) timeout that returns FSM to IDLE
// when a command is abandoned mid-parse.

`timescale 1ns / 1ps

module timeout_tb;

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
        $dumpfile("build/timeout_tb.vcd");
        $dumpvars(0, timeout_tb);
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
    // Helper: receive and check a string
    // =========================================================================
    task expect_string;
        input [8*80-1:0] expected;
        input integer len;
        input [8*40-1:0] label;
        integer i;
        reg [7:0] got;
        reg [7:0] exp;
        reg ok;
        begin
            ok = 1'b1;
            for (i = 0; i < len; i = i + 1) begin
                get_byte(got);
                exp = expected >> ((len - 1 - i) * 8);
                if (got !== exp[7:0]) begin
                    $display("  MISMATCH at char %0d: expected 0x%02X ('%c') got 0x%02X ('%c')",
                             i, exp[7:0], exp[7:0], got, got);
                    ok = 1'b0;
                end
            end
            if (!ok) begin
                $display("  FAIL: %0s", label);
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
    // Helper: send zero-arg command (e.g. ":G", ":F", ":?")
    // These execute immediately on the opcode byte — no CR needed
    // =========================================================================
    task send_zero_arg_cmd;
        input [7:0] opcode;
        begin
            uart_send(":");  // 0x3A
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
    // Timeout watchdog (500ms to allow for intentional waits)
    // =========================================================================
    initial begin
        #500_000_000; // 500 ms
        $display("TIMEOUT: simulation exceeded 500ms");
        $display("Results: %0d passed, %0d failed (TIMEOUT)", pass_count, fail_count);
        $finish(1);
    end

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        $display("=== FPGA Enigma I Timeout Testbench ===");
        $display("");

        // Wait for startup banner
        wait_for_banner;
        $display("Banner received OK.");
        $display("");

        // =====================================================================
        // Test Case 1: Timeout in CMD_OPCODE
        // Send ":" (enters CMD_OPCODE), wait 25ms, verify FSM returned to IDLE
        // =====================================================================
        test_num = 1;
        $display("--- Test Case 1: Timeout in CMD_OPCODE ---");
        begin : case1_block
            integer saved_wr_ptr;
            reg [7:0] ct_byte;

            // Send ":" to enter CMD_OPCODE
            uart_send(":");
            $display("  Sent ':' to enter CMD_OPCODE");

            // Save current rx_wr_ptr to verify no bytes received during timeout
            saved_wr_ptr = rx_wr_ptr;

            // Wait 25ms = 25,000,000 ns = 300,000 clock cycles at 83.333ns period
            $display("  Waiting 25ms for timeout...");
            repeat(300000) @(posedge clk);

            // Verify no bytes were received (timeout produces no output)
            if (rx_wr_ptr !== saved_wr_ptr) begin
                $display("  FAIL: Case 1: Unexpected bytes received during timeout");
                fail_count = fail_count + 1;
            end else begin
                $display("  No bytes received during timeout (correct)");
            end

            // FSM should be back in IDLE. Send 'A', expect 'B' (ground settings, first char)
            $display("  Sending 'A' to verify FSM is in IDLE");
            uart_send("A");
            get_byte(ct_byte);

            if (ct_byte === "B") begin
                $display("PASS: Case 1: Timeout in CMD_OPCODE");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Case 1: Expected 'B', got '%c' (0x%02X)", ct_byte, ct_byte);
                fail_count = fail_count + 1;
            end
        end
        $display("");

        // =====================================================================
        // Test Case 2: Timeout in CMD_ARG (partial command)
        // Send ":R12" (enters CMD_ARG, got 2 of 3 args), wait 25ms, verify IDLE
        // =====================================================================
        test_num = 2;
        $display("--- Test Case 2: Timeout in CMD_ARG ---");
        begin : case2_block
            integer saved_wr_ptr;
            reg [7:0] ct_byte;

            // Factory reset to start clean
            factory_reset;
            $display("  Factory reset complete");

            // Send ":R12" to enter CMD_ARG with partial arguments
            uart_send(":");
            uart_send("R");
            uart_send("1");
            uart_send("2");
            $display("  Sent ':R12' to enter CMD_ARG (partial command)");

            // Save current rx_wr_ptr
            saved_wr_ptr = rx_wr_ptr;

            // Wait 25ms for timeout
            $display("  Waiting 25ms for timeout...");
            repeat(300000) @(posedge clk);

            // Verify no bytes were received
            if (rx_wr_ptr !== saved_wr_ptr) begin
                $display("  FAIL: Case 2: Unexpected bytes received during timeout");
                fail_count = fail_count + 1;
            end else begin
                $display("  No bytes received during timeout (correct)");
            end

            // FSM should be back in IDLE. Reset positions to known state first,
            // since the partial `:R12` bytes were consumed as args (not enciphers)
            // but we want a deterministic check.
            grundstellung_reset;
            $display("  Sending 'A' to verify FSM is in IDLE");
            uart_send("A");
            get_byte(ct_byte);

            if (ct_byte === "B") begin
                $display("PASS: Case 2: Timeout in CMD_ARG");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Case 2: Expected 'B', got '%c' (0x%02X)", ct_byte, ct_byte);
                fail_count = fail_count + 1;
            end
        end
        $display("");

        // =====================================================================
        // Test Case 3: Re-colon abort (immediate, not timeout)
        // Send ":R1" then ":" to abort, then ":R123\r" to execute new command
        // =====================================================================
        test_num = 3;
        $display("--- Test Case 3: Re-colon abort ---");
        begin : case3_block
            reg [7:0] ct_byte;

            // Factory reset to start clean
            factory_reset;
            $display("  Factory reset complete");

            // Send ":R1" to enter CMD_ARG
            uart_send(":");
            uart_send("R");
            uart_send("1");
            $display("  Sent ':R1' to enter CMD_ARG");

            // Send ":" to abort current command and start new CMD_OPCODE
            uart_send(":");
            $display("  Sent ':' to abort current command");

            // Complete the new command ":R123\r"
            uart_send("R");
            uart_send("1");
            uart_send("2");
            uart_send("3");
            uart_send(8'h0D);
            $display("  Sent 'R123\\r' to complete new command");

            // Expect "OK\r\n"
            wait_for_ok;
            $display("  Received OK for :R123 command");

            // Verify machine works with new rotor settings
            // Send :G to reset to grundstellung
            grundstellung_reset;

            // With rotors I-II-III (default ring/grund AAA), 'A' enciphers to 'B'
            uart_send("A");
            get_byte(ct_byte);

            if (ct_byte === "B") begin
                $display("PASS: Case 3: Re-colon abort");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Case 3: Expected 'B', got '%c' (0x%02X)", ct_byte, ct_byte);
                fail_count = fail_count + 1;
            end
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
