// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// stepper_tb.v
// Unit testbench for the stepper module
// Tests basic stepping, notch triggering, double-step anomaly, and all rotor notches

`timescale 1ns / 1ps

module stepper_tb;

    // =========================================================================
    // Clock and DUT signals
    // =========================================================================
    reg clk = 1'b0;
    always #41.667 clk = ~clk;  // ~12 MHz (83.333 ns period)

    reg rst_n = 1'b1;
    reg step_pulse = 1'b0;
    reg load_pulse = 1'b0;
    reg [2:0] rotor_sel_l = 3'd0;
    reg [2:0] rotor_sel_m = 3'd0;
    reg [2:0] rotor_sel_r = 3'd0;
    reg [4:0] grundstellung_l = 5'd0;
    reg [4:0] grundstellung_m = 5'd0;
    reg [4:0] grundstellung_r = 5'd0;
    wire [4:0] pos_l;
    wire [4:0] pos_m;
    wire [4:0] pos_r;

    stepper dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .step_pulse     (step_pulse),
        .load_pulse     (load_pulse),
        .rotor_sel_m    (rotor_sel_m),
        .rotor_sel_r    (rotor_sel_r),
        .grundstellung_l(grundstellung_l),
        .grundstellung_m(grundstellung_m),
        .grundstellung_r(grundstellung_r),
        .pos_l          (pos_l),
        .pos_m          (pos_m),
        .pos_r          (pos_r)
    );

    // =========================================================================
    // VCD dump for coverage
    // =========================================================================
    `ifdef VCD_DUMP
    initial begin
        $dumpfile("build/stepper_tb.vcd");
        $dumpvars(0, stepper_tb);
    end
    `endif

    // =========================================================================
    // Test counters
    // =========================================================================
    integer pass_count = 0;
    integer fail_count = 0;

    // =========================================================================
    // Helper: pulse step for one clock cycle
    // =========================================================================
    task pulse_step;
        begin
            @(posedge clk);
            #1;
            step_pulse = 1'b1;
            @(posedge clk);
            #1;
            step_pulse = 1'b0;
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // Helper: pulse load for one clock cycle
    // =========================================================================
    task pulse_load;
        begin
            @(posedge clk);
            #1;
            load_pulse = 1'b1;
            @(posedge clk);
            #1;
            load_pulse = 1'b0;
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // Helper: check positions
    // =========================================================================
    task check_positions;
        input [4:0] exp_l;
        input [4:0] exp_m;
        input [4:0] exp_r;
        input [8*60-1:0] label;
        begin
            if (pos_l === exp_l && pos_m === exp_m && pos_r === exp_r) begin
                $display("PASS: %0s (pos=%0d,%0d,%0d)", label, pos_l, pos_m, pos_r);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s expected (%0d,%0d,%0d) got (%0d,%0d,%0d)",
                         label, exp_l, exp_m, exp_r, pos_l, pos_m, pos_r);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #10_000_000; // 10 ms
        $display("TIMEOUT: simulation exceeded 10ms");
        $display("Results: %0d passed, %0d failed (TIMEOUT)", pass_count, fail_count);
        $finish(1);
    end

    // =========================================================================
    // Main test sequence
    // =========================================================================
    integer i;

    initial begin
        $display("=== Stepper Unit Testbench ===");
        $display("");

        // Initial reset
        @(posedge clk);
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // =====================================================================
        // Test 1: Basic stepping - right rotor wraps from Z to A
        // =====================================================================
        $display("--- Test 1: Basic stepping (26 steps) ---");

        // Set rotors I-II-V
        // Rotor V has notch at Z=25, so positions 0-24 won't trigger middle rotor
        rotor_sel_l = 3'd0;  // Rotor I
        rotor_sel_m = 3'd1;  // Rotor II
        rotor_sel_r = 3'd4;  // Rotor V (notch at Z=25)

        // Load AAA (0,0,0)
        grundstellung_l = 5'd0;
        grundstellung_m = 5'd0;
        grundstellung_r = 5'd0;
        pulse_load;

        // Verify initial positions
        check_positions(5'd0, 5'd0, 5'd0, "Test 1: Initial AAA");

        // Step 24 times (should go 0->1->...->24, no notch triggered)
        for (i = 0; i < 24; i = i + 1) begin
            pulse_step;
        end
        check_positions(5'd0, 5'd0, 5'd24, "Test 1: After 24 steps (right at Y, middle unchanged)");

        // One more step to position 25 (Z, the notch position)
        pulse_step;
        check_positions(5'd0, 5'd0, 5'd25, "Test 1: Right at Z (notch position)");

        // One more step: right wraps to 0, middle increments (was at notch)
        pulse_step;
        check_positions(5'd0, 5'd1, 5'd0, "Test 1: Right wraps Z->A, middle increments");

        $display("");

        // =====================================================================
        // Test 2: Right notch triggers middle rotor
        // =====================================================================
        $display("--- Test 2: Right notch triggers middle ---");

        // Reset
        @(posedge clk);
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // Set rotors I-II-III (III has notch at V=21)
        rotor_sel_l = 3'd0;
        rotor_sel_m = 3'd1;
        rotor_sel_r = 3'd2;

        // Load positions: left=0, middle=0, right=20 (one before notch)
        grundstellung_l = 5'd0;
        grundstellung_m = 5'd0;
        grundstellung_r = 5'd20;
        pulse_load;

        check_positions(5'd0, 5'd0, 5'd20, "Test 2: Initial (0,0,20)");

        // Step once: right goes to 21 (at notch)
        pulse_step;
        check_positions(5'd0, 5'd0, 5'd21, "Test 2: Right at notch position (0,0,21)");

        // Step again: right was at notch, so middle increments
        pulse_step;
        check_positions(5'd0, 5'd1, 5'd22, "Test 2: Notch triggered middle (0,1,22)");

        $display("");

        // =====================================================================
        // Test 3: Double-step anomaly
        // =====================================================================
        $display("--- Test 3: Double-step anomaly ---");

        // Reset
        @(posedge clk);
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // Set rotors I-II-III
        // Middle rotor II has notch at E=4
        // Right rotor III has notch at V=21
        rotor_sel_l = 3'd0;
        rotor_sel_m = 3'd1;
        rotor_sel_r = 3'd2;

        // Load positions: middle=3 (one before its notch), right=21 (at its notch)
        grundstellung_l = 5'd0;
        grundstellung_m = 5'd3;
        grundstellung_r = 5'd21;
        pulse_load;

        check_positions(5'd0, 5'd3, 5'd21, "Test 3: Initial (0,3,21)");

        // Step once: right at notch triggers middle
        // right: 21->22, middle: 3->4 (now at its notch), left: 0->0
        pulse_step;
        check_positions(5'd0, 5'd4, 5'd22, "Test 3: After first step (0,4,22)");

        // Step again: middle is at its notch (4), triggers double-step
        // right: 22->23, middle: 4->5 (steps itself), left: 0->1 (triggered by middle)
        pulse_step;
        check_positions(5'd1, 5'd5, 5'd23, "Test 3: Double-step anomaly (1,5,23)");

        $display("");

        // =====================================================================
        // Test 4: Load pulse has priority over step pulse
        // =====================================================================
        $display("--- Test 4: Load pulse priority ---");

        // Reset
        @(posedge clk);
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // Set rotors I-II-III
        rotor_sel_l = 3'd0;
        rotor_sel_m = 3'd1;
        rotor_sel_r = 3'd2;

        // Load initial positions (10,10,10)
        grundstellung_l = 5'd10;
        grundstellung_m = 5'd10;
        grundstellung_r = 5'd10;
        pulse_load;

        check_positions(5'd10, 5'd10, 5'd10, "Test 4: Initial (10,10,10)");

        // Assert both load_pulse and step_pulse simultaneously
        // Load should win, positions should become (5,5,5)
        grundstellung_l = 5'd5;
        grundstellung_m = 5'd5;
        grundstellung_r = 5'd5;

        @(posedge clk);
        #1;
        load_pulse = 1'b1;
        step_pulse = 1'b1;
        @(posedge clk);
        #1;
        load_pulse = 1'b0;
        step_pulse = 1'b0;
        @(posedge clk);

        check_positions(5'd5, 5'd5, 5'd5, "Test 4: Load wins over step (5,5,5)");

        $display("");

        // =====================================================================
        // Test 5: All 5 rotor notches
        // =====================================================================
        $display("--- Test 5: All rotor notches ---");

        // Test each rotor type in the right position

        // Rotor I: notch at Q=16
        @(posedge clk);
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        rotor_sel_l = 3'd0;
        rotor_sel_m = 3'd1;
        rotor_sel_r = 3'd0;  // Rotor I in right position

        grundstellung_l = 5'd0;
        grundstellung_m = 5'd0;
        grundstellung_r = 5'd16;  // At notch Q=16
        pulse_load;

        pulse_step;
        check_positions(5'd0, 5'd1, 5'd17, "Test 5a: Rotor I notch at Q=16 (0,1,17)");

        // Rotor II: notch at E=4
        @(posedge clk);
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        rotor_sel_l = 3'd0;
        rotor_sel_m = 3'd0;
        rotor_sel_r = 3'd1;  // Rotor II in right position

        grundstellung_l = 5'd0;
        grundstellung_m = 5'd0;
        grundstellung_r = 5'd4;  // At notch E=4
        pulse_load;

        pulse_step;
        check_positions(5'd0, 5'd1, 5'd5, "Test 5b: Rotor II notch at E=4 (0,1,5)");

        // Rotor III: notch at V=21
        @(posedge clk);
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        rotor_sel_l = 3'd0;
        rotor_sel_m = 3'd0;
        rotor_sel_r = 3'd2;  // Rotor III in right position

        grundstellung_l = 5'd0;
        grundstellung_m = 5'd0;
        grundstellung_r = 5'd21;  // At notch V=21
        pulse_load;

        pulse_step;
        check_positions(5'd0, 5'd1, 5'd22, "Test 5c: Rotor III notch at V=21 (0,1,22)");

        // Rotor IV: notch at J=9
        @(posedge clk);
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        rotor_sel_l = 3'd0;
        rotor_sel_m = 3'd0;
        rotor_sel_r = 3'd3;  // Rotor IV in right position

        grundstellung_l = 5'd0;
        grundstellung_m = 5'd0;
        grundstellung_r = 5'd9;  // At notch J=9
        pulse_load;

        pulse_step;
        check_positions(5'd0, 5'd1, 5'd10, "Test 5d: Rotor IV notch at J=9 (0,1,10)");

        // Rotor V: notch at Z=25
        @(posedge clk);
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        rotor_sel_l = 3'd0;
        rotor_sel_m = 3'd0;
        rotor_sel_r = 3'd4;  // Rotor V in right position

        grundstellung_l = 5'd0;
        grundstellung_m = 5'd0;
        grundstellung_r = 5'd25;  // At notch Z=25
        pulse_load;

        pulse_step;
        check_positions(5'd0, 5'd1, 5'd0, "Test 5e: Rotor V notch at Z=25 (0,1,0)");

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
