// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// enigma_tb.v
// — Self-checking testbench for FPGA Enigma I
// Runs all 7 test cases at UART interface level under Icarus Verilog.
// Architecture: A continuous background UART receiver deposits bytes into
// a FIFO. The main test sequence pulls bytes via get_byte. This avoids
// send/receive timing overlap issues.

`timescale 1ns / 1ps

module enigma_tb;

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
        $dumpfile("build/enigma_tb.vcd");
        $dumpvars(0, enigma_tb);
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
    // Helper: send :? and receive/parse POS line
    // =========================================================================
    task query_positions;
        output [7:0] p_l;
        output [7:0] p_m;
        output [7:0] p_r;
        reg [7:0] ch;
        integer i;
        begin
            send_zero_arg_cmd("?");
            // Consume lines until POS:
            // UKW:B\r\n (7 chars)
            for (i = 0; i < 7; i = i + 1) get_byte(ch);
            // ROT:L M R\r\n (11 chars)
            for (i = 0; i < 11; i = i + 1) get_byte(ch);
            // RNG:L M R\r\n (11 chars)
            for (i = 0; i < 11; i = i + 1) get_byte(ch);
            // GRD:L M R\r\n (11 chars)
            for (i = 0; i < 11; i = i + 1) get_byte(ch);
            // POS:L M R\r\n (11 chars)
            get_byte(ch); // P
            get_byte(ch); // O
            get_byte(ch); // S
            get_byte(ch); // :
            get_byte(p_l); // left position letter
            get_byte(ch); // space
            get_byte(p_m); // mid position letter
            get_byte(ch); // space
            get_byte(p_r); // right position letter
            get_byte(ch); // CR
            get_byte(ch); // LF
            // PLG:...\r\n — variable length; consume until \n
            get_byte(ch);
            while (ch != 8'h0A) begin
                get_byte(ch);
            end
            // OK\r\n
            wait_for_ok;
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
    reg [7:0] pos_l_ch, pos_m_ch, pos_r_ch;

    initial begin
        $display("=== FPGA Enigma I Testbench ===");
        $display("");

        // Wait for startup banner
        wait_for_banner;
        $display("Banner received OK.");
        $display("");

        // =====================================================================
        // Test Case 1: Ground settings (AAAAA → BDZGO)
        // =====================================================================
        test_num = 1;
        $display("--- Test Case 1: Ground settings ---");
        encipher_and_check("AAAAA", 5, "BDZGO", "Case 1: Ground");
        $display("");

        // =====================================================================
        // Test Case 2: Barbarossa (EDPUD → AUFKL)
        // =====================================================================
        test_num = 2;
        $display("--- Test Case 2: Barbarossa ---");
        factory_reset;
        send_command(":R245", 5);
        send_command(":NBUL", 5);
        send_command(":PBLA", 5);
        // Plugboard pairs
        send_command(":SAV", 4);
        send_command(":SBS", 4);
        send_command(":SCG", 4);
        send_command(":SDL", 4);
        send_command(":SFU", 4);
        send_command(":SHZ", 4);
        send_command(":SIN", 4);
        send_command(":SKM", 4);
        send_command(":SOW", 4);
        send_command(":SRX", 4);
        // Load positions
        grundstellung_reset;
        encipher_and_check("EDPUD", 5, "AUFKL", "Case 2: Barbarossa");
        $display("");

        // =====================================================================
        // Test Case 3: Double-step anomaly (ADQ → AER → BFS)
        // =====================================================================
        test_num = 3;
        $display("--- Test Case 3: Double-step ---");
        factory_reset;
        send_command(":R321", 5);
        send_command(":PADQ", 5);
        grundstellung_reset;
        // First keystroke: don't care about cipher output
        begin : case3_block
            reg [7:0] dummy_ct;
            uart_send("A");
            get_byte(dummy_ct);
            // Check positions via :?
            query_positions(pos_l_ch, pos_m_ch, pos_r_ch);
            if (pos_l_ch == "A" && pos_m_ch == "E" && pos_r_ch == "R") begin
                $display("  Step 1 positions: A E R (correct)");
            end else begin
                $display("  FAIL: Step 1 expected A E R, got %c %c %c",
                         pos_l_ch, pos_m_ch, pos_r_ch);
                fail_count = fail_count + 1;
            end
            // Second keystroke
            uart_send("A");
            get_byte(dummy_ct);
            query_positions(pos_l_ch, pos_m_ch, pos_r_ch);
            if (pos_l_ch == "B" && pos_m_ch == "F" && pos_r_ch == "S") begin
                $display("PASS: Case 3: Double-step (ADQ->AER->BFS)");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Case 3: Step 2 expected B F S, got %c %c %c",
                         pos_l_ch, pos_m_ch, pos_r_ch);
                fail_count = fail_count + 1;
            end
        end
        $display("");

        // =====================================================================
        // Test Case 4: Ring settings BBB (AAAAA → EWTYX)
        // =====================================================================
        test_num = 4;
        $display("--- Test Case 4: Ring BBB ---");
        factory_reset;
        send_command(":NBBB", 5);
        send_command(":PAAA", 5);
        grundstellung_reset;
        encipher_and_check("AAAAA", 5, "EWTYX", "Case 4: Ring BBB");
        $display("");

        // =====================================================================
        // Test Case 5: Triple-notch QEV (AAAAA → LNPJG)
        // =====================================================================
        test_num = 5;
        $display("--- Test Case 5: Triple-notch ---");
        factory_reset;
        send_command(":PQEV", 5);
        grundstellung_reset;
        encipher_and_check("AAAAA", 5, "LNPJG", "Case 5: Triple-notch");
        // Verify final positions
        query_positions(pos_l_ch, pos_m_ch, pos_r_ch);
        if (pos_l_ch !== "R" || pos_m_ch !== "F" || pos_r_ch !== "A") begin
            $display("  WARNING: Case 5 final pos expected R F A, got %c %c %c",
                     pos_l_ch, pos_m_ch, pos_r_ch);
        end
        $display("");

        // =====================================================================
        // Test Case 6: 26-char full cycle (AAAAA...A → BDZGOWCXLTKSBTMCDLPBMUQOFX)
        // =====================================================================
        test_num = 6;
        $display("--- Test Case 6: 26-char full cycle ---");
        factory_reset;
        grundstellung_reset;
        encipher_and_check(
            "AAAAAAAAAAAAAAAAAAAAAAAAAA", 26,
            "BDZGOWCXLTKSBTMCDLPBMUQOFX", "Case 6: 26-char");
        query_positions(pos_l_ch, pos_m_ch, pos_r_ch);
        if (pos_l_ch !== "A" || pos_m_ch !== "B" || pos_r_ch !== "A") begin
            $display("  WARNING: Case 6 final pos expected A B A, got %c %c %c",
                     pos_l_ch, pos_m_ch, pos_r_ch);
        end
        $display("");

        // =====================================================================
        // Test Case 7: Self-reciprocal round-trip
        // =====================================================================
        test_num = 7;
        $display("--- Test Case 7: Self-reciprocal ---");
        // Configure Barbarossa settings again
        factory_reset;
        send_command(":R245", 5);
        send_command(":NBUL", 5);
        send_command(":PBLA", 5);
        send_command(":SAV", 4);
        send_command(":SBS", 4);
        send_command(":SCG", 4);
        send_command(":SDL", 4);
        send_command(":SFU", 4);
        send_command(":SHZ", 4);
        send_command(":SIN", 4);
        send_command(":SKM", 4);
        send_command(":SOW", 4);
        send_command(":SRX", 4);
        grundstellung_reset;
        // Encrypt
        encipher_and_check("THEQUICKBROWNFOX", 16, "NIBAJBTJDJGUHGVU",
                           "Case 7a: Encrypt");
        // Decrypt (reset to same starting position)
        grundstellung_reset;
        encipher_and_check("NIBAJBTJDJGUHGVU", 16, "THEQUICKBROWNFOX",
                           "Case 7b: Decrypt (round-trip)");
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
