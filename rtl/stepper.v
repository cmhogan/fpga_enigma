// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// stepper.v
// Rotor stepping module for FPGA Enigma I
// Implements the double-stepping anomaly of the middle rotor

module stepper (
    input wire clk,
    input wire rst_n,
    input wire step_pulse,
    input wire load_pulse,
    input wire [2:0] rotor_sel_m,
    input wire [2:0] rotor_sel_r,
    input wire [4:0] grundstellung_l,
    input wire [4:0] grundstellung_m,
    input wire [4:0] grundstellung_r,
    output reg [4:0] pos_l = 5'd0,
    output reg [4:0] pos_m = 5'd0,
    output reg [4:0] pos_r = 5'd0
);

    // Notch positions for each rotor
    // I=16(Q), II=4(E), III=21(V), IV=9(J), V=25(Z)
    localparam [4:0] NOTCH_I   = 5'd16;
    localparam [4:0] NOTCH_II  = 5'd4;
    localparam [4:0] NOTCH_III = 5'd21;
    localparam [4:0] NOTCH_IV  = 5'd9;
    localparam [4:0] NOTCH_V   = 5'd25;

    // Notch decode for middle and right rotors
    reg [4:0] notch_m;
    reg [4:0] notch_r;

    always @(*) begin
        case (rotor_sel_m)
            3'd0: notch_m = NOTCH_I;
            3'd1: notch_m = NOTCH_II;
            3'd2: notch_m = NOTCH_III;
            3'd3: notch_m = NOTCH_IV;
            3'd4: notch_m = NOTCH_V;
            default: notch_m = NOTCH_I;
        endcase

        case (rotor_sel_r)
            3'd0: notch_r = NOTCH_I;
            3'd1: notch_r = NOTCH_II;
            3'd2: notch_r = NOTCH_III;
            3'd3: notch_r = NOTCH_IV;
            3'd4: notch_r = NOTCH_V;
            default: notch_r = NOTCH_I;
        endcase
    end

    // Stepping logic - evaluate notch conditions BEFORE updating
    wire at_notch_r = (pos_r == notch_r);
    wire at_notch_m = (pos_m == notch_m);

    wire step_l = at_notch_m;
    wire step_m = at_notch_r || at_notch_m;  // Double-step anomaly
    wire step_r = 1'b1;                       // Always steps

    // Next position calculation (modulo 26)
    wire [4:0] next_pos_l = (pos_l == 5'd25) ? 5'd0 : pos_l + 5'd1;
    wire [4:0] next_pos_m = (pos_m == 5'd25) ? 5'd0 : pos_m + 5'd1;
    wire [4:0] next_pos_r = (pos_r == 5'd25) ? 5'd0 : pos_r + 5'd1;

    // Position registers with synchronous reset and load/step logic
    always @(posedge clk) begin
        if (!rst_n) begin
            pos_l <= 5'd0;
            pos_m <= 5'd0;
            pos_r <= 5'd0;
        end else if (load_pulse) begin
            // load_pulse has priority
            pos_l <= grundstellung_l;
            pos_m <= grundstellung_m;
            pos_r <= grundstellung_r;
        end else if (step_pulse) begin
            // Step rotors according to stepping logic
            if (step_l) begin
                pos_l <= next_pos_l;
            end
            if (step_m) begin
                pos_m <= next_pos_m;
            end
            if (step_r) begin
                pos_r <= next_pos_r;
            end
        end
    end

`ifdef SIMULATION
always @(posedge clk) begin
    if (rst_n) begin
        if (pos_l >= 5'd26) begin
            $display("ASSERTION FAIL: stepper: pos_l=%0d out of range", pos_l);
            $fatal(1);
        end
        if (pos_m >= 5'd26) begin
            $display("ASSERTION FAIL: stepper: pos_m=%0d out of range", pos_m);
            $fatal(1);
        end
        if (pos_r >= 5'd26) begin
            $display("ASSERTION FAIL: stepper: pos_r=%0d out of range", pos_r);
            $fatal(1);
        end
    end
end
`endif

endmodule
