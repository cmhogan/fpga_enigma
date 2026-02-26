// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// enigma_forward.v
// — Forward half of the Enigma I cipher path
// Purely combinational: plugboard → right rotor fwd → middle rotor fwd → left rotor fwd → reflector
// Produces mid_letter for the FSM to register between CIPHER_A and CIPHER_B.

module enigma_forward (
    input  wire [4:0]   pt_index,       // Plaintext letter index 0..25
    input  wire [2:0]   rotor_sel_l,    // Left rotor selection (0=I..4=V)
    input  wire [2:0]   rotor_sel_m,    // Middle rotor selection
    input  wire [2:0]   rotor_sel_r,    // Right rotor selection
    input  wire [4:0]   ring_l,         // Left rotor ring setting 0..25
    input  wire [4:0]   ring_m,         // Middle rotor ring setting
    input  wire [4:0]   ring_r,         // Right rotor ring setting
    input  wire [4:0]   pos_l,          // Left rotor current position 0..25
    input  wire [4:0]   pos_m,          // Middle rotor current position
    input  wire [4:0]   pos_r,          // Right rotor current position
    input  wire [129:0] plug_map,       // Plugboard wiring map (26 x 5-bit)
    output wire [4:0]   mid_letter      // Reflector output (intermediate result)
);

    // =========================================================================
    // Shared functions from enigma_common.vh
    // =========================================================================
    `include "enigma_common.vh"

    // =========================================================================
    // Forward rotor wiring lookup — case-based for correctness
    // Rotor I:   EKMFLGDQVZNTOWYHXUSPAIBRCJ
    // Rotor II:  AJDKSIRUXBLHWTMCQGZNPYFVOE
    // Rotor III: BDFHJLCPRTXVZNYEIWGAKMUSQO
    // Rotor IV:  ESOVPZJAYQUIRHXLNFTGKDCMWB
    // Rotor V:   VZBRGITYUPSDNHLXAWMJQOFECK
    // =========================================================================
    function [4:0] fwd_lookup;
        input [2:0] sel;
        input [4:0] idx;
        reg [4:0] r;
        begin
            case (sel)
                3'd0: // Rotor I forward
                    case (idx)
                        5'd0:  r=5'd4;  5'd1:  r=5'd10; 5'd2:  r=5'd12; 5'd3:  r=5'd5;
                        5'd4:  r=5'd11; 5'd5:  r=5'd6;  5'd6:  r=5'd3;  5'd7:  r=5'd16;
                        5'd8:  r=5'd21; 5'd9:  r=5'd25; 5'd10: r=5'd13; 5'd11: r=5'd19;
                        5'd12: r=5'd14; 5'd13: r=5'd22; 5'd14: r=5'd24; 5'd15: r=5'd7;
                        5'd16: r=5'd23; 5'd17: r=5'd20; 5'd18: r=5'd18; 5'd19: r=5'd15;
                        5'd20: r=5'd0;  5'd21: r=5'd8;  5'd22: r=5'd1;  5'd23: r=5'd17;
                        5'd24: r=5'd2;  5'd25: r=5'd9;  default: r=5'd0;
                    endcase
                3'd1: // Rotor II forward
                    case (idx)
                        5'd0:  r=5'd0;  5'd1:  r=5'd9;  5'd2:  r=5'd3;  5'd3:  r=5'd10;
                        5'd4:  r=5'd18; 5'd5:  r=5'd8;  5'd6:  r=5'd17; 5'd7:  r=5'd20;
                        5'd8:  r=5'd23; 5'd9:  r=5'd1;  5'd10: r=5'd11; 5'd11: r=5'd7;
                        5'd12: r=5'd22; 5'd13: r=5'd19; 5'd14: r=5'd12; 5'd15: r=5'd2;
                        5'd16: r=5'd16; 5'd17: r=5'd6;  5'd18: r=5'd25; 5'd19: r=5'd13;
                        5'd20: r=5'd15; 5'd21: r=5'd24; 5'd22: r=5'd5;  5'd23: r=5'd21;
                        5'd24: r=5'd14; 5'd25: r=5'd4;  default: r=5'd0;
                    endcase
                3'd2: // Rotor III forward
                    case (idx)
                        5'd0:  r=5'd1;  5'd1:  r=5'd3;  5'd2:  r=5'd5;  5'd3:  r=5'd7;
                        5'd4:  r=5'd9;  5'd5:  r=5'd11; 5'd6:  r=5'd2;  5'd7:  r=5'd15;
                        5'd8:  r=5'd17; 5'd9:  r=5'd19; 5'd10: r=5'd23; 5'd11: r=5'd21;
                        5'd12: r=5'd25; 5'd13: r=5'd13; 5'd14: r=5'd24; 5'd15: r=5'd4;
                        5'd16: r=5'd8;  5'd17: r=5'd22; 5'd18: r=5'd6;  5'd19: r=5'd0;
                        5'd20: r=5'd10; 5'd21: r=5'd12; 5'd22: r=5'd20; 5'd23: r=5'd18;
                        5'd24: r=5'd16; 5'd25: r=5'd14; default: r=5'd0;
                    endcase
                3'd3: // Rotor IV forward
                    case (idx)
                        5'd0:  r=5'd4;  5'd1:  r=5'd18; 5'd2:  r=5'd14; 5'd3:  r=5'd21;
                        5'd4:  r=5'd15; 5'd5:  r=5'd25; 5'd6:  r=5'd9;  5'd7:  r=5'd0;
                        5'd8:  r=5'd24; 5'd9:  r=5'd16; 5'd10: r=5'd20; 5'd11: r=5'd8;
                        5'd12: r=5'd17; 5'd13: r=5'd7;  5'd14: r=5'd23; 5'd15: r=5'd11;
                        5'd16: r=5'd13; 5'd17: r=5'd5;  5'd18: r=5'd19; 5'd19: r=5'd6;
                        5'd20: r=5'd10; 5'd21: r=5'd3;  5'd22: r=5'd2;  5'd23: r=5'd12;
                        5'd24: r=5'd22; 5'd25: r=5'd1;  default: r=5'd0;
                    endcase
                3'd4: // Rotor V forward
                    case (idx)
                        5'd0:  r=5'd21; 5'd1:  r=5'd25; 5'd2:  r=5'd1;  5'd3:  r=5'd17;
                        5'd4:  r=5'd6;  5'd5:  r=5'd8;  5'd6:  r=5'd19; 5'd7:  r=5'd24;
                        5'd8:  r=5'd20; 5'd9:  r=5'd15; 5'd10: r=5'd18; 5'd11: r=5'd3;
                        5'd12: r=5'd13; 5'd13: r=5'd7;  5'd14: r=5'd11; 5'd15: r=5'd23;
                        5'd16: r=5'd0;  5'd17: r=5'd22; 5'd18: r=5'd12; 5'd19: r=5'd9;
                        5'd20: r=5'd16; 5'd21: r=5'd14; 5'd22: r=5'd5;  5'd23: r=5'd4;
                        5'd24: r=5'd2;  5'd25: r=5'd10; default: r=5'd0;
                    endcase
                default: r = 5'd0;
            endcase
            fwd_lookup = r;
        end
    endfunction

    // =========================================================================
    // Reflector UKW-B lookup: YRUHQSLDPXNGOKMIEBFZCWVJAT
    // =========================================================================
    function [4:0] reflector_lookup;
        input [4:0] idx;
        reg [4:0] r;
        begin
            case (idx)
                5'd0:  r=5'd24; 5'd1:  r=5'd17; 5'd2:  r=5'd20; 5'd3:  r=5'd7;
                5'd4:  r=5'd16; 5'd5:  r=5'd18; 5'd6:  r=5'd11; 5'd7:  r=5'd3;
                5'd8:  r=5'd15; 5'd9:  r=5'd23; 5'd10: r=5'd13; 5'd11: r=5'd6;
                5'd12: r=5'd14; 5'd13: r=5'd10; 5'd14: r=5'd12; 5'd15: r=5'd8;
                5'd16: r=5'd4;  5'd17: r=5'd1;  5'd18: r=5'd5;  5'd19: r=5'd25;
                5'd20: r=5'd2;  5'd21: r=5'd22; 5'd22: r=5'd21; 5'd23: r=5'd9;
                5'd24: r=5'd0;  5'd25: r=5'd19; default: r=5'd0;
            endcase
            reflector_lookup = r;
        end
    endfunction

    // =========================================================================
    // Forward rotor substitution (single rotor stage)
    // =========================================================================
    function [4:0] rotor_fwd;
        input [4:0] signal_in;
        input [4:0] pos;
        input [4:0] ring;
        input [2:0] sel;
        reg [4:0] offset;
        reg [4:0] shifted_in;
        reg [4:0] out_core;
        begin
            offset     = mod26({1'b0, pos} + 6'd26 - {1'b0, ring});
            shifted_in = mod26({1'b0, signal_in} + {1'b0, offset});
            out_core   = fwd_lookup(sel, shifted_in);
            rotor_fwd  = mod26({1'b0, out_core} + 6'd26 - {1'b0, offset});
        end
    endfunction

    // =========================================================================
    // Plugboard instance (input side)
    // =========================================================================
    wire [4:0] after_plug;
    plugboard plug_fwd (
        .letter_in  (pt_index),
        .plug_map   (plug_map),
        .letter_out (after_plug)
    );

    // =========================================================================
    // Signal flow: plug → right fwd → middle fwd → left fwd → reflector
    // =========================================================================
    wire [4:0] after_right  = rotor_fwd(after_plug,   pos_r, ring_r, rotor_sel_r);
    wire [4:0] after_middle = rotor_fwd(after_right,  pos_m, ring_m, rotor_sel_m);
    wire [4:0] after_left   = rotor_fwd(after_middle, pos_l, ring_l, rotor_sel_l);
    assign mid_letter       = reflector_lookup(after_left);

endmodule
