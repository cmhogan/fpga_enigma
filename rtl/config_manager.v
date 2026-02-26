// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// config_manager.v
// Configuration Manager for FPGA Enigma I
//
// Holds all Enigma machine configuration registers:
//   - Rotor selection (3 rotors from set I-V)
//   - Ring settings (Ringstellung) for each rotor
//   - Initial positions (Grundstellung)
//   - Plugboard (Steckerbrett) mappings
//
// Exposes all settings as combinational outputs to cipher and stepper modules.
// Synchronous write ports driven by FSM for configuration updates.
//
// Factory defaults: Rotors I-II-III, rings AAA, grundstellung AAA, identity plugboard

module config_manager (
    // System signals
    input wire clk,
    input wire rst_n,

    // Write enables from FSM
    input wire wr_rotor,          // Update rotor selection
    input wire wr_ring,           // Update ring settings
    input wire wr_grund,          // Update Grundstellung
    input wire wr_plug_add,       // Add one stecker pair
    input wire wr_plug_clr,       // Clear plugboard to identity
    input wire wr_factory,        // Restore factory defaults

    // Configuration data input (packed by FSM)
    /* verilator lint_off UNUSED */
    input wire [15:0] cfg_data,
    /* verilator lint_on UNUSED */

    // Live rotor positions from stepper (for status reporting)
    input wire [4:0] pos_l,
    input wire [4:0] pos_m,
    input wire [4:0] pos_r,

    // Configuration outputs to cipher/stepper
    output wire [2:0] rotor_sel_l,
    output wire [2:0] rotor_sel_m,
    output wire [2:0] rotor_sel_r,
    output wire [4:0] ring_l,
    output wire [4:0] ring_m,
    output wire [4:0] ring_r,
    output wire [4:0] grundstellung_l,
    output wire [4:0] grundstellung_m,
    output wire [4:0] grundstellung_r,
    output wire [129:0] plug_map,   // Flat 26×5-bit plugboard map
    output wire [4:0] plug_pair_cnt,

    // Status output (packed for :? query response)
    output wire [63:0] cfg_status
);

    // ========================================================================
    // Factory Defaults
    // ========================================================================
    localparam [2:0] FACTORY_ROTOR_L = 3'd0;  // Rotor I
    localparam [2:0] FACTORY_ROTOR_M = 3'd1;  // Rotor II
    localparam [2:0] FACTORY_ROTOR_R = 3'd2;  // Rotor III
    localparam [4:0] FACTORY_RING    = 5'd0;  // Ring A (0)
    localparam [4:0] FACTORY_GRUND   = 5'd0;  // Position A (0)

    // ========================================================================
    // Configuration Registers
    // ========================================================================
    reg [2:0] rotor_sel_l_r;
    reg [2:0] rotor_sel_m_r;
    reg [2:0] rotor_sel_r_r;
    reg [4:0] ring_l_r;
    reg [4:0] ring_m_r;
    reg [4:0] ring_r_r;
    reg [4:0] grundstellung_l_r;
    reg [4:0] grundstellung_m_r;
    reg [4:0] grundstellung_r_r;
    reg [4:0] plug_pair_cnt_r;

    // Plugboard: 26 letters × 5 bits each
    reg [4:0] plugboard [0:25];

    // Loop variable (must be declared at module level for Verilog-2001)
    integer i;

    // ========================================================================
    // Initialize all registers for GSR compatibility (iCE40)
    // ========================================================================
    initial begin
        // Rotor selections
        rotor_sel_l_r = FACTORY_ROTOR_L;
        rotor_sel_m_r = FACTORY_ROTOR_M;
        rotor_sel_r_r = FACTORY_ROTOR_R;

        // Ring settings
        ring_l_r = FACTORY_RING;
        ring_m_r = FACTORY_RING;
        ring_r_r = FACTORY_RING;

        // Grundstellung
        grundstellung_l_r = FACTORY_GRUND;
        grundstellung_m_r = FACTORY_GRUND;
        grundstellung_r_r = FACTORY_GRUND;

        // Plugboard pair count
        plug_pair_cnt_r = 5'd0;

        // Plugboard identity mapping (each letter maps to itself)
        for (i = 0; i < 26; i = i + 1) begin
            plugboard[i] = i[4:0];
        end
    end

    // ========================================================================
    // Synchronous Register Update Logic
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            // Synchronous reset: restore factory defaults
            rotor_sel_l_r <= FACTORY_ROTOR_L;
            rotor_sel_m_r <= FACTORY_ROTOR_M;
            rotor_sel_r_r <= FACTORY_ROTOR_R;

            ring_l_r <= FACTORY_RING;
            ring_m_r <= FACTORY_RING;
            ring_r_r <= FACTORY_RING;

            grundstellung_l_r <= FACTORY_GRUND;
            grundstellung_m_r <= FACTORY_GRUND;
            grundstellung_r_r <= FACTORY_GRUND;

            plug_pair_cnt_r <= 5'd0;

            for (i = 0; i < 26; i = i + 1) begin
                plugboard[i] <= i[4:0];
            end
        end else begin
            // Factory reset command (same as rst_n)
            if (wr_factory) begin
                rotor_sel_l_r <= FACTORY_ROTOR_L;
                rotor_sel_m_r <= FACTORY_ROTOR_M;
                rotor_sel_r_r <= FACTORY_ROTOR_R;

                ring_l_r <= FACTORY_RING;
                ring_m_r <= FACTORY_RING;
                ring_r_r <= FACTORY_RING;

                grundstellung_l_r <= FACTORY_GRUND;
                grundstellung_m_r <= FACTORY_GRUND;
                grundstellung_r_r <= FACTORY_GRUND;

                plug_pair_cnt_r <= 5'd0;

                for (i = 0; i < 26; i = i + 1) begin
                    plugboard[i] <= i[4:0];
                end
            end else begin
                // Update rotor selections
                // cfg_data[8:0] = {rotor_l[2:0], rotor_m[2:0], rotor_r[2:0]}
                if (wr_rotor) begin
                    rotor_sel_r_r <= cfg_data[2:0];
                    rotor_sel_m_r <= cfg_data[5:3];
                    rotor_sel_l_r <= cfg_data[8:6];
                end

                // Update ring settings
                // cfg_data[14:0] = {ring_l[4:0], ring_m[4:0], ring_r[4:0]}
                if (wr_ring) begin
                    ring_r_r <= cfg_data[4:0];
                    ring_m_r <= cfg_data[9:5];
                    ring_l_r <= cfg_data[14:10];
                end

                // Update Grundstellung
                // cfg_data[14:0] = {grnd_l[4:0], grnd_m[4:0], grnd_r[4:0]}
                if (wr_grund) begin
                    grundstellung_r_r <= cfg_data[4:0];
                    grundstellung_m_r <= cfg_data[9:5];
                    grundstellung_l_r <= cfg_data[14:10];
                end

                // Add stecker pair (reciprocal mapping)
                // cfg_data[9:0] = {letter_a[4:0], letter_b[4:0]}
                if (wr_plug_add) begin
                    plugboard[cfg_data[9:5]] <= cfg_data[4:0];  // letter_a -> letter_b
                    plugboard[cfg_data[4:0]] <= cfg_data[9:5];  // letter_b -> letter_a
                    plug_pair_cnt_r <= plug_pair_cnt_r + 5'd1;
                end

                // Clear plugboard to identity
                if (wr_plug_clr) begin
                    plug_pair_cnt_r <= 5'd0;
                    for (i = 0; i < 26; i = i + 1) begin
                        plugboard[i] <= i[4:0];
                    end
                end
            end
        end
    end

    // ========================================================================
    // Combinational Outputs
    // ========================================================================

    // Direct register outputs
    assign rotor_sel_l = rotor_sel_l_r;
    assign rotor_sel_m = rotor_sel_m_r;
    assign rotor_sel_r = rotor_sel_r_r;
    assign ring_l = ring_l_r;
    assign ring_m = ring_m_r;
    assign ring_r = ring_r_r;
    assign grundstellung_l = grundstellung_l_r;
    assign grundstellung_m = grundstellung_m_r;
    assign grundstellung_r = grundstellung_r_r;
    assign plug_pair_cnt = plug_pair_cnt_r;

    // Flatten plugboard array into 130-bit bus (26 × 5 bits)
    // plug_map[4:0] = plugboard[0], plug_map[9:5] = plugboard[1], etc.
    assign plug_map = {
        plugboard[25], plugboard[24], plugboard[23], plugboard[22],
        plugboard[21], plugboard[20], plugboard[19], plugboard[18],
        plugboard[17], plugboard[16], plugboard[15], plugboard[14],
        plugboard[13], plugboard[12], plugboard[11], plugboard[10],
        plugboard[9],  plugboard[8],  plugboard[7],  plugboard[6],
        plugboard[5],  plugboard[4],  plugboard[3],  plugboard[2],
        plugboard[1],  plugboard[0]
    };

    // Pack configuration status for :? query
    // [63:61] rotor_sel_l, [60:58] rotor_sel_m, [57:55] rotor_sel_r
    // [54:50] ring_l, [49:45] ring_m, [44:40] ring_r
    // [39:35] grundstellung_l, [34:30] grundstellung_m, [29:25] grundstellung_r
    // [24:20] plug_pair_cnt
    // [19:15] pos_l (live), [14:10] pos_m (live), [9:5] pos_r (live)
    // [4:0] reserved (0)
    assign cfg_status = {
        rotor_sel_l_r,      // [63:61]
        rotor_sel_m_r,      // [60:58]
        rotor_sel_r_r,      // [57:55]
        ring_l_r,           // [54:50]
        ring_m_r,           // [49:45]
        ring_r_r,           // [44:40]
        grundstellung_l_r,  // [39:35]
        grundstellung_m_r,  // [34:30]
        grundstellung_r_r,  // [29:25]
        plug_pair_cnt_r,    // [24:20]
        pos_l,              // [19:15] live position from stepper
        pos_m,              // [14:10] live position from stepper
        pos_r,              // [9:5]   live position from stepper
        5'd0                // [4:0]   reserved
    };

`ifdef SIMULATION
always @(posedge clk) begin
    if (rst_n) begin
        if (plug_pair_cnt > 5'd13) begin
            $display("ASSERTION FAIL: config_manager: plug_pair_cnt=%0d exceeds 13", plug_pair_cnt);
            $fatal(1);
        end
    end
end
`endif

endmodule
