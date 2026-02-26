// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// config_manager_tb.v
// — Unit testbench for config_manager module
// Tests configuration register updates, plugboard operations, and factory reset

`timescale 1ns / 1ps

module config_manager_tb;

    // =========================================================================
    // Clock and reset
    // =========================================================================
    reg clk = 1'b0;
    always #41.667 clk = ~clk;  // ~12 MHz (83.333 ns period)

    reg rst_n;

    // =========================================================================
    // DUT signals
    // =========================================================================
    reg wr_rotor;
    reg wr_ring;
    reg wr_grund;
    reg wr_plug_add;
    reg wr_plug_clr;
    reg wr_factory;
    reg [15:0] cfg_data;
    reg [4:0] pos_l;
    reg [4:0] pos_m;
    reg [4:0] pos_r;

    wire [2:0] rotor_sel_l;
    wire [2:0] rotor_sel_m;
    wire [2:0] rotor_sel_r;
    wire [4:0] ring_l;
    wire [4:0] ring_m;
    wire [4:0] ring_r;
    wire [4:0] grundstellung_l;
    wire [4:0] grundstellung_m;
    wire [4:0] grundstellung_r;
    wire [129:0] plug_map;
    wire [4:0] plug_pair_cnt;
    wire [63:0] cfg_status;

    // =========================================================================
    // Instantiate DUT
    // =========================================================================
    config_manager dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .wr_rotor        (wr_rotor),
        .wr_ring         (wr_ring),
        .wr_grund        (wr_grund),
        .wr_plug_add     (wr_plug_add),
        .wr_plug_clr     (wr_plug_clr),
        .wr_factory      (wr_factory),
        .cfg_data        (cfg_data),
        .pos_l           (pos_l),
        .pos_m           (pos_m),
        .pos_r           (pos_r),
        .rotor_sel_l     (rotor_sel_l),
        .rotor_sel_m     (rotor_sel_m),
        .rotor_sel_r     (rotor_sel_r),
        .ring_l          (ring_l),
        .ring_m          (ring_m),
        .ring_r          (ring_r),
        .grundstellung_l (grundstellung_l),
        .grundstellung_m (grundstellung_m),
        .grundstellung_r (grundstellung_r),
        .plug_map        (plug_map),
        .plug_pair_cnt   (plug_pair_cnt),
        .cfg_status      (cfg_status)
    );

    // =========================================================================
    // VCD dump for coverage
    // =========================================================================
    `ifdef VCD_DUMP
    initial begin
        $dumpfile("build/config_manager_tb.vcd");
        $dumpvars(0, config_manager_tb);
    end
    `endif

    // =========================================================================
    // Test counters
    // =========================================================================
    integer pass_count = 0;
    integer fail_count = 0;

    // =========================================================================
    // Helper: check plug_map entry
    // =========================================================================
    function [4:0] get_plug_entry;
        input [4:0] index;
        begin
            get_plug_entry = plug_map[index*5 +: 5];
        end
    endfunction

    // =========================================================================
    // Test tasks
    // =========================================================================

    // Apply single-cycle pulse to a write signal
    task pulse_write;
        input [2:0] sig_select;
        begin
            @(posedge clk);
            #1; // Delta delay to ensure signal change is captured
            case (sig_select)
                3'd0: wr_rotor = 1'b1;
                3'd1: wr_ring = 1'b1;
                3'd2: wr_grund = 1'b1;
                3'd3: wr_plug_add = 1'b1;
                3'd4: wr_plug_clr = 1'b1;
                3'd5: wr_factory = 1'b1;
            endcase
            @(posedge clk);
            #1; // Delta delay
            wr_rotor = 1'b0;
            wr_ring = 1'b0;
            wr_grund = 1'b0;
            wr_plug_add = 1'b0;
            wr_plug_clr = 1'b0;
            wr_factory = 1'b0;
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
        $display("=== config_manager Unit Testbench ===");
        $display("");

        // Initialize inputs
        rst_n = 1'b1;
        wr_rotor = 1'b0;
        wr_ring = 1'b0;
        wr_grund = 1'b0;
        wr_plug_add = 1'b0;
        wr_plug_clr = 1'b0;
        wr_factory = 1'b0;
        cfg_data = 16'd0;
        pos_l = 5'd0;
        pos_m = 5'd0;
        pos_r = 5'd0;

        // Wait for initial block to complete
        #10;

        // =====================================================================
        // Test 1: Factory defaults after reset
        // =====================================================================
        $display("--- Test 1: Factory defaults after reset ---");
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        @(posedge clk);

        // Check factory defaults: rotors I/II/III (0/1/2)
        if (rotor_sel_l === 3'd0 && rotor_sel_m === 3'd1 && rotor_sel_r === 3'd2) begin
            $display("PASS: Factory default rotors I/II/III");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected rotors 0/1/2, got %0d/%0d/%0d",
                     rotor_sel_l, rotor_sel_m, rotor_sel_r);
            fail_count = fail_count + 1;
        end

        // Check rings AAA (0/0/0)
        if (ring_l === 5'd0 && ring_m === 5'd0 && ring_r === 5'd0) begin
            $display("PASS: Factory default rings AAA");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected rings 0/0/0, got %0d/%0d/%0d",
                     ring_l, ring_m, ring_r);
            fail_count = fail_count + 1;
        end

        // Check grundstellung AAA (0/0/0)
        if (grundstellung_l === 5'd0 && grundstellung_m === 5'd0 && grundstellung_r === 5'd0) begin
            $display("PASS: Factory default grundstellung AAA");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected grundstellung 0/0/0, got %0d/%0d/%0d",
                     grundstellung_l, grundstellung_m, grundstellung_r);
            fail_count = fail_count + 1;
        end

        // Check plug_map identity (each entry N maps to N)
        begin : check_identity
            reg identity_ok;
            identity_ok = 1'b1;
            for (i = 0; i < 26; i = i + 1) begin
                if (get_plug_entry(i[4:0]) !== i[4:0]) begin
                    identity_ok = 1'b0;
                    $display("  plug_map[%0d] = %0d (expected %0d)", i, get_plug_entry(i[4:0]), i);
                end
            end
            if (identity_ok) begin
                $display("PASS: Factory default plug_map identity");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: plug_map not identity");
                fail_count = fail_count + 1;
            end
        end

        // Check plug_pair_cnt = 0
        if (plug_pair_cnt === 5'd0) begin
            $display("PASS: Factory default plug_pair_cnt = 0");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected plug_pair_cnt 0, got %0d", plug_pair_cnt);
            fail_count = fail_count + 1;
        end

        $display("");

        // =====================================================================
        // Test 2: Write rotors (IV-V-I = 3/4/0)
        // =====================================================================
        $display("--- Test 2: Write rotors IV-V-I ---");
        // cfg_data[8:6]=left=3, [5:3]=mid=4, [2:0]=right=0
        cfg_data = {7'd0, 3'd3, 3'd4, 3'd0};
        pulse_write(3'd0); // wr_rotor
        @(posedge clk);

        if (rotor_sel_l === 3'd3 && rotor_sel_m === 3'd4 && rotor_sel_r === 3'd0) begin
            $display("PASS: Rotors updated to IV-V-I (3/4/0)");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected rotors 3/4/0, got %0d/%0d/%0d",
                     rotor_sel_l, rotor_sel_m, rotor_sel_r);
            fail_count = fail_count + 1;
        end

        $display("");

        // =====================================================================
        // Test 3: Write rings (DOG = 3/14/6)
        // =====================================================================
        $display("--- Test 3: Write rings DOG (3/14/6) ---");
        // cfg_data[14:10]=left=3, [9:5]=mid=14, [4:0]=right=6
        cfg_data = {1'd0, 5'd3, 5'd14, 5'd6};
        pulse_write(3'd1); // wr_ring
        @(posedge clk);

        if (ring_l === 5'd3 && ring_m === 5'd14 && ring_r === 5'd6) begin
            $display("PASS: Rings updated to DOG (3/14/6)");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected rings 3/14/6, got %0d/%0d/%0d",
                     ring_l, ring_m, ring_r);
            fail_count = fail_count + 1;
        end

        $display("");

        // =====================================================================
        // Test 4: Write grundstellung (CAT = 2/0/19)
        // =====================================================================
        $display("--- Test 4: Write grundstellung CAT (2/0/19) ---");
        // cfg_data[14:10]=left=2, [9:5]=mid=0, [4:0]=right=19
        cfg_data = {1'd0, 5'd2, 5'd0, 5'd19};
        pulse_write(3'd2); // wr_grund
        @(posedge clk);

        if (grundstellung_l === 5'd2 && grundstellung_m === 5'd0 && grundstellung_r === 5'd19) begin
            $display("PASS: Grundstellung updated to CAT (2/0/19)");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected grundstellung 2/0/19, got %0d/%0d/%0d",
                     grundstellung_l, grundstellung_m, grundstellung_r);
            fail_count = fail_count + 1;
        end

        $display("");

        // =====================================================================
        // Test 5: Add plugboard pair A↔B (0↔1)
        // =====================================================================
        $display("--- Test 5: Add plugboard pair A↔B (0↔1) ---");
        // cfg_data[9:5]=letter_a=0, [4:0]=letter_b=1
        cfg_data = {6'd0, 5'd0, 5'd1};
        pulse_write(3'd3); // wr_plug_add
        @(posedge clk);

        if (get_plug_entry(5'd0) === 5'd1 && get_plug_entry(5'd1) === 5'd0) begin
            $display("PASS: Plugboard pair A↔B added (plug_map[0]=1, plug_map[1]=0)");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected plug_map[0]=1, plug_map[1]=0, got %0d, %0d",
                     get_plug_entry(5'd0), get_plug_entry(5'd1));
            fail_count = fail_count + 1;
        end

        if (plug_pair_cnt === 5'd1) begin
            $display("PASS: plug_pair_cnt = 1");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected plug_pair_cnt 1, got %0d", plug_pair_cnt);
            fail_count = fail_count + 1;
        end

        $display("");

        // =====================================================================
        // Test 6: Add second pair C↔D (2↔3)
        // =====================================================================
        $display("--- Test 6: Add second pair C↔D (2↔3) ---");
        // cfg_data[9:5]=letter_a=2, [4:0]=letter_b=3
        cfg_data = {6'd0, 5'd2, 5'd3};
        pulse_write(3'd3); // wr_plug_add
        @(posedge clk);

        if (get_plug_entry(5'd2) === 5'd3 && get_plug_entry(5'd3) === 5'd2) begin
            $display("PASS: Plugboard pair C↔D added");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected plug_map[2]=3, plug_map[3]=2, got %0d, %0d",
                     get_plug_entry(5'd2), get_plug_entry(5'd3));
            fail_count = fail_count + 1;
        end

        // Verify first pair still exists
        if (get_plug_entry(5'd0) === 5'd1 && get_plug_entry(5'd1) === 5'd0) begin
            $display("PASS: First pair A↔B still exists");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: First pair A↔B corrupted");
            fail_count = fail_count + 1;
        end

        if (plug_pair_cnt === 5'd2) begin
            $display("PASS: plug_pair_cnt = 2");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected plug_pair_cnt 2, got %0d", plug_pair_cnt);
            fail_count = fail_count + 1;
        end

        $display("");

        // =====================================================================
        // Test 7: Clear plugboard
        // =====================================================================
        $display("--- Test 7: Clear plugboard ---");
        pulse_write(3'd4); // wr_plug_clr
        @(posedge clk);

        // Check plug_map returns to identity
        begin : check_cleared
            reg cleared_ok;
            cleared_ok = 1'b1;
            for (i = 0; i < 26; i = i + 1) begin
                if (get_plug_entry(i[4:0]) !== i[4:0]) begin
                    cleared_ok = 1'b0;
                    $display("  plug_map[%0d] = %0d (expected %0d)", i, get_plug_entry(i[4:0]), i);
                end
            end
            if (cleared_ok) begin
                $display("PASS: Plugboard cleared to identity");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Plugboard not identity after clear");
                fail_count = fail_count + 1;
            end
        end

        if (plug_pair_cnt === 5'd0) begin
            $display("PASS: plug_pair_cnt = 0 after clear");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected plug_pair_cnt 0 after clear, got %0d", plug_pair_cnt);
            fail_count = fail_count + 1;
        end

        $display("");

        // =====================================================================
        // Test 8: Factory reset command
        // =====================================================================
        $display("--- Test 8: Factory reset command ---");
        // First, change all settings to non-default values

        // Set rotors to II-IV-V (1/3/4)
        cfg_data = {7'd0, 3'd1, 3'd3, 3'd4};
        pulse_write(3'd0); // wr_rotor
        @(posedge clk);

        // Set rings to XYZ (23/24/25)
        cfg_data = {1'd0, 5'd23, 5'd24, 5'd25};
        pulse_write(3'd1); // wr_ring
        @(posedge clk);

        // Set grundstellung to PQR (15/16/17)
        cfg_data = {1'd0, 5'd15, 5'd16, 5'd17};
        pulse_write(3'd2); // wr_grund
        @(posedge clk);

        // Add plugboard pair E↔F (4↔5)
        cfg_data = {6'd0, 5'd4, 5'd5};
        pulse_write(3'd3); // wr_plug_add
        @(posedge clk);

        // Verify settings changed
        if (rotor_sel_l === 3'd1 && ring_l === 5'd23 && grundstellung_l === 5'd15 &&
            get_plug_entry(5'd4) === 5'd5) begin
            $display("  Settings changed to non-default (verified)");
        end else begin
            $display("  WARNING: Could not verify non-default settings");
        end

        // Issue factory reset
        pulse_write(3'd5); // wr_factory
        @(posedge clk);

        // Verify everything returns to defaults
        if (rotor_sel_l === 3'd0 && rotor_sel_m === 3'd1 && rotor_sel_r === 3'd2) begin
            $display("PASS: Factory reset - rotors restored to I/II/III");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Factory reset - rotors not restored, got %0d/%0d/%0d",
                     rotor_sel_l, rotor_sel_m, rotor_sel_r);
            fail_count = fail_count + 1;
        end

        if (ring_l === 5'd0 && ring_m === 5'd0 && ring_r === 5'd0) begin
            $display("PASS: Factory reset - rings restored to AAA");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Factory reset - rings not restored");
            fail_count = fail_count + 1;
        end

        if (grundstellung_l === 5'd0 && grundstellung_m === 5'd0 && grundstellung_r === 5'd0) begin
            $display("PASS: Factory reset - grundstellung restored to AAA");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Factory reset - grundstellung not restored");
            fail_count = fail_count + 1;
        end

        begin : check_factory_identity
            reg factory_ok;
            factory_ok = 1'b1;
            for (i = 0; i < 26; i = i + 1) begin
                if (get_plug_entry(i[4:0]) !== i[4:0]) begin
                    factory_ok = 1'b0;
                end
            end
            if (factory_ok) begin
                $display("PASS: Factory reset - plug_map restored to identity");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Factory reset - plug_map not identity");
                fail_count = fail_count + 1;
            end
        end

        if (plug_pair_cnt === 5'd0) begin
            $display("PASS: Factory reset - plug_pair_cnt = 0");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Factory reset - plug_pair_cnt not 0, got %0d", plug_pair_cnt);
            fail_count = fail_count + 1;
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
