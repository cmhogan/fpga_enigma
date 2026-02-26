// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// plugboard_tb_unit.v
// Unit testbench for the plugboard module
// Tests identity mapping, single swap, full 13 pairs, and reciprocity

`timescale 1ns / 1ps

module plugboard_tb_unit;

    // =========================================================================
    // DUT signals
    // =========================================================================
    reg [4:0] letter_in = 5'd0;
    reg [129:0] plug_map = 130'd0;
    wire [4:0] letter_out;

    plugboard dut (
        .letter_in  (letter_in),
        .plug_map   (plug_map),
        .letter_out (letter_out)
    );

    // =========================================================================
    // VCD dump for coverage
    // =========================================================================
    `ifdef VCD_DUMP
    initial begin
        $dumpfile("build/plugboard_tb_unit.vcd");
        $dumpvars(0, plugboard_tb_unit);
    end
    `endif

    // =========================================================================
    // Test counters
    // =========================================================================
    integer pass_count = 0;
    integer fail_count = 0;

    // =========================================================================
    // Helper: set one entry in plug_map
    // =========================================================================
    task set_plug_entry;
        input [4:0] index;
        input [4:0] value;
        begin
            plug_map[index * 5 +: 5] = value;
        end
    endtask

    // =========================================================================
    // Helper: get one entry from plug_map
    // =========================================================================
    function [4:0] get_plug_entry;
        input [4:0] index;
        begin
            get_plug_entry = plug_map[index * 5 +: 5];
        end
    endfunction

    // =========================================================================
    // Helper: check output
    // =========================================================================
    task check_output;
        input [4:0] input_letter;
        input [4:0] expected_output;
        input [8*60-1:0] label;
        begin
            letter_in = input_letter;
            #10;  // Combinational delay
            if (letter_out === expected_output) begin
                $display("PASS: %0s (in=%0d out=%0d)", label, input_letter, letter_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s input=%0d expected=%0d got=%0d",
                         label, input_letter, expected_output, letter_out);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    integer i;

    initial begin
        $display("=== Plugboard Unit Testbench ===");
        $display("");

        // =====================================================================
        // Test 1: Identity mapping (every letter maps to itself)
        // =====================================================================
        $display("--- Test 1: Identity mapping ---");

        // Initialize plug_map with identity: 0->0, 1->1, ..., 25->25
        plug_map = 130'd0;
        for (i = 0; i < 26; i = i + 1) begin
            set_plug_entry(i, i);
        end

        // Test all 26 letters
        for (i = 0; i < 26; i = i + 1) begin
            letter_in = i;
            #10;
            if (letter_out !== i) begin
                $display("FAIL: Test 1: Identity mapping failed for letter %0d (got %0d)",
                         i, letter_out);
                fail_count = fail_count + 1;
            end
        end

        $display("PASS: Test 1: All 26 letters map to themselves");
        pass_count = pass_count + 1;

        $display("");

        // =====================================================================
        // Test 2: Single swap (A<->B)
        // =====================================================================
        $display("--- Test 2: Single swap A<->B ---");

        // Set A->B (0->1), B->A (1->0), rest identity
        plug_map = 130'd0;
        for (i = 0; i < 26; i = i + 1) begin
            set_plug_entry(i, i);
        end
        set_plug_entry(0, 1);  // A->B
        set_plug_entry(1, 0);  // B->A

        check_output(5'd0, 5'd1, "Test 2: A->B");
        check_output(5'd1, 5'd0, "Test 2: B->A");
        check_output(5'd2, 5'd2, "Test 2: C->C (identity)");
        check_output(5'd25, 5'd25, "Test 2: Z->Z (identity)");

        $display("");

        // =====================================================================
        // Test 3: Full 13 pairs
        // =====================================================================
        $display("--- Test 3: Full 13 pairs ---");

        // Set up 13 pairs:
        // A<->N (0<->13), B<->O (1<->14), C<->P (2<->15), D<->Q (3<->16),
        // E<->R (4<->17), F<->S (5<->18), G<->T (6<->19), H<->U (7<->20),
        // I<->V (8<->21), J<->W (9<->22), K<->X (10<->23), L<->Y (11<->24),
        // M<->Z (12<->25)
        plug_map = 130'd0;
        for (i = 0; i < 13; i = i + 1) begin
            set_plug_entry(i, i + 13);
            set_plug_entry(i + 13, i);
        end

        // Verify all mappings
        for (i = 0; i < 13; i = i + 1) begin
            letter_in = i;
            #10;
            if (letter_out !== (i + 13)) begin
                $display("FAIL: Test 3: Letter %0d expected %0d got %0d",
                         i, i + 13, letter_out);
                fail_count = fail_count + 1;
            end
        end

        for (i = 13; i < 26; i = i + 1) begin
            letter_in = i;
            #10;
            if (letter_out !== (i - 13)) begin
                $display("FAIL: Test 3: Letter %0d expected %0d got %0d",
                         i, i - 13, letter_out);
                fail_count = fail_count + 1;
            end
        end

        // Verify no letter maps to itself
        for (i = 0; i < 26; i = i + 1) begin
            letter_in = i;
            #10;
            if (letter_out === i) begin
                $display("FAIL: Test 3: Letter %0d maps to itself (should be swapped)",
                         i);
                fail_count = fail_count + 1;
            end
        end

        $display("PASS: Test 3: All 13 pairs verified, no self-mapping");
        pass_count = pass_count + 1;

        $display("");

        // =====================================================================
        // Test 4: Reciprocity check
        // =====================================================================
        $display("--- Test 4: Reciprocity check ---");

        // Use the Barbarossa plugboard from the main testbench:
        // AV BS CG DL FU HZ IN KM OW RX
        plug_map = 130'd0;
        // Start with identity
        for (i = 0; i < 26; i = i + 1) begin
            set_plug_entry(i, i);
        end

        // A<->V (0<->21)
        set_plug_entry(0, 21);
        set_plug_entry(21, 0);
        // B<->S (1<->18)
        set_plug_entry(1, 18);
        set_plug_entry(18, 1);
        // C<->G (2<->6)
        set_plug_entry(2, 6);
        set_plug_entry(6, 2);
        // D<->L (3<->11)
        set_plug_entry(3, 11);
        set_plug_entry(11, 3);
        // F<->U (5<->20)
        set_plug_entry(5, 20);
        set_plug_entry(20, 5);
        // H<->Z (7<->25)
        set_plug_entry(7, 25);
        set_plug_entry(25, 7);
        // I<->N (8<->13)
        set_plug_entry(8, 13);
        set_plug_entry(13, 8);
        // K<->M (10<->12)
        set_plug_entry(10, 12);
        set_plug_entry(12, 10);
        // O<->W (14<->22)
        set_plug_entry(14, 22);
        set_plug_entry(22, 14);
        // R<->X (17<->23)
        set_plug_entry(17, 23);
        set_plug_entry(23, 17);

        // Verify reciprocity for all configured pairs
        for (i = 0; i < 26; i = i + 1) begin
            letter_in = i;
            #10;
            // letter_out should map back to letter_in
            letter_in = letter_out;
            #10;
            if (letter_out !== i) begin
                $display("FAIL: Test 4: Reciprocity failed for letter %0d", i);
                fail_count = fail_count + 1;
            end
        end

        $display("PASS: Test 4: Reciprocity verified for all letters");
        pass_count = pass_count + 1;

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
