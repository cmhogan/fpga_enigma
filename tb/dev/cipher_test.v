`timescale 1ns / 1ns
module cipher_test;
    // Test the forward/backward cipher path directly
    reg [4:0] pt_index;
    reg [2:0] rotor_sel_l, rotor_sel_m, rotor_sel_r;
    reg [4:0] ring_l, ring_m, ring_r;
    reg [4:0] pos_l, pos_m, pos_r;
    reg [129:0] plug_map;
    wire [4:0] mid_letter, ct_index;
    
    // Identity plugboard
    integer i;
    initial begin
        for (i = 0; i < 26; i = i + 1)
            plug_map[i*5 +: 5] = i[4:0];
    end
    
    enigma_forward fwd(
        .pt_index(pt_index), .rotor_sel_l(rotor_sel_l), .rotor_sel_m(rotor_sel_m),
        .rotor_sel_r(rotor_sel_r), .ring_l(ring_l), .ring_m(ring_m), .ring_r(ring_r),
        .pos_l(pos_l), .pos_m(pos_m), .pos_r(pos_r), .plug_map(plug_map),
        .mid_letter(mid_letter)
    );
    
    enigma_backward bwd(
        .mid_letter(mid_letter), .rotor_sel_l(rotor_sel_l), .rotor_sel_m(rotor_sel_m),
        .rotor_sel_r(rotor_sel_r), .ring_l(ring_l), .ring_m(ring_m), .ring_r(ring_r),
        .pos_l(pos_l), .pos_m(pos_m), .pos_r(pos_r), .plug_map(plug_map),
        .ct_index(ct_index)
    );
    
    initial begin
        // Ground settings: Rotors I-II-III, rings AAA, position AAB (after stepping from AAA)
        rotor_sel_l = 3'd0; rotor_sel_m = 3'd1; rotor_sel_r = 3'd2;
        ring_l = 5'd0; ring_m = 5'd0; ring_r = 5'd0;
        pos_l = 5'd0; pos_m = 5'd0; pos_r = 5'd1; // A-A-B (after first step)
        pt_index = 5'd0; // 'A'
        
        #10;
        $display("Test 1: A at pos AAB -> mid_letter=%0d ct_index=%0d (expected: ct=1=B)", mid_letter, ct_index);
        $display("  ct char = '%c'", ct_index + 8'h41);
        
        // Check forward path step by step
        $display("  fwd.after_plug = %0d", fwd.after_plug);
        $display("  fwd.after_right = %0d", fwd.after_right);
        $display("  fwd.after_middle = %0d", fwd.after_middle);
        $display("  fwd.after_left = %0d", fwd.after_left);
        $display("  fwd.mid_letter = %0d (reflector output)", fwd.mid_letter);
        $display("  bwd.after_left = %0d", bwd.after_left);
        $display("  bwd.after_middle = %0d", bwd.after_middle);
        $display("  bwd.before_plug = %0d", bwd.before_plug);
        $display("  bwd.ct_index = %0d", bwd.ct_index);
        
        $finish;
    end
endmodule
