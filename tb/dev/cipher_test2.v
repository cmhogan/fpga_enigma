`timescale 1ns / 1ns
module cipher_test2;
    reg [4:0] pt_index;
    reg [2:0] rotor_sel_l, rotor_sel_m, rotor_sel_r;
    reg [4:0] ring_l, ring_m, ring_r;
    reg [4:0] pos_l, pos_m, pos_r;
    reg [129:0] plug_map;
    wire [4:0] mid_letter, ct_index;
    
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
        rotor_sel_l = 3'd0; rotor_sel_m = 3'd1; rotor_sel_r = 3'd2;
        ring_l = 5'd0; ring_m = 5'd0; ring_r = 5'd0;
        pt_index = 5'd0;
        
        // AAAAA -> BDZGO, positions AAB, AAC, AAD, AAE, AAF
        pos_l=0; pos_m=0; pos_r=1; #10;
        $display("Char 1: A at AAB -> %c (expect B)", ct_index + 8'h41);
        pos_l=0; pos_m=0; pos_r=2; #10;
        $display("Char 2: A at AAC -> %c (expect D)", ct_index + 8'h41);
        pos_l=0; pos_m=0; pos_r=3; #10;
        $display("Char 3: A at AAD -> %c (expect Z)", ct_index + 8'h41);
        pos_l=0; pos_m=0; pos_r=4; #10;
        $display("Char 4: A at AAE -> %c (expect G)", ct_index + 8'h41);
        pos_l=0; pos_m=0; pos_r=5; #10;
        $display("Char 5: A at AAF -> %c (expect O)", ct_index + 8'h41);
        
        $finish;
    end
endmodule
