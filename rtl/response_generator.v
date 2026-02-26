// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// response_generator.v
// Command response generation sub-module for FPGA Enigma I
// Handles OK/ERR string emission and :? multi-line query responses.
// Instantiated inside fsm_controller as a sub-module.

module response_generator (
    input  wire        clk,
    input  wire        rst_n,

    // Handshake with FSM
    input  wire        start,        // single-cycle pulse: begin response
    input  wire        resp_ok,      // 1 = OK response, 0 = ERR response
    input  wire        is_query,     // 1 = :? multi-line query response
    output reg         done,         // single-cycle pulse: response complete

    // UART TX interface
    input  wire        tx_busy,
    output reg  [7:0]  tx_byte,
    output reg         tx_start,

    // Configuration status (for :? query lines)
    /* verilator lint_off UNUSED */
    input  wire [63:0] cfg_status,
    /* verilator lint_on UNUSED */
    input  wire [4:0]  pos_l,
    input  wire [4:0]  pos_m,
    input  wire [4:0]  pos_r,
    input  wire [129:0] plug_map
);

    // =========================================================================
    // State encodings
    // =========================================================================
    localparam RESP_IDLE   = 1'b0,
               RESP_ACTIVE = 1'b1;

    reg resp_state = RESP_IDLE;

    // =========================================================================
    // Latched inputs (captured on start pulse)
    // =========================================================================
    reg        lat_resp_ok  = 1'b0;
    reg        lat_is_query = 1'b0;

    // =========================================================================
    // Response registers
    // =========================================================================
    reg [2:0]  resp_idx      = 3'd0;
    reg [2:0]  resp_phase    = 3'd0;   // 0=UKW,1=ROT,2=RNG,3=GRD,4=POS,5=PLG,6=OK
    reg [4:0]  resp_char     = 5'd0;
    reg [4:0]  plug_scan     = 5'd0;
    reg        first_pair    = 1'b1;
    // PLG sub-sub-state: 0=scanning, 1=emit space, 2=emit first letter, 3=emit second letter
    reg [1:0]  plg_substate  = 2'd0;

    // =========================================================================
    // Plugboard scan partner (combinational from plug_map)
    // =========================================================================
    wire [4:0] plug_partner = plug_map[plug_scan * 5 +: 5];

    // =========================================================================
    // :? response character generator (combinational)
    // =========================================================================
    reg [7:0] query_char;
    reg       query_done_line;
    reg       query_done_all;
    reg       query_no_emit;  // PLG scan: skip this cycle (no char to emit)

    always @(*) begin
        query_char = 8'd0;
        query_done_line = 1'b0;
        query_done_all = 1'b0;
        query_no_emit = 1'b0;

        case (resp_phase)
            3'd0: begin // "UKW:B\r\n"
                case (resp_char)
                    5'd0: query_char = "U"; 5'd1: query_char = "K";
                    5'd2: query_char = "W"; 5'd3: query_char = ":";
                    5'd4: query_char = "B"; 5'd5: query_char = 8'h0D;
                    5'd6: begin query_char = 8'h0A; query_done_line = 1'b1; end
                    default: query_done_line = 1'b1;
                endcase
            end
            3'd1: begin // "ROT:L M R\r\n"
                case (resp_char)
                    5'd0: query_char = "R"; 5'd1: query_char = "O";
                    5'd2: query_char = "T"; 5'd3: query_char = ":";
                    5'd4: query_char = {5'd0, cfg_status[63:61]} + 8'd49;
                    5'd5: query_char = " ";
                    5'd6: query_char = {5'd0, cfg_status[60:58]} + 8'd49;
                    5'd7: query_char = " ";
                    5'd8: query_char = {5'd0, cfg_status[57:55]} + 8'd49;
                    5'd9: query_char = 8'h0D;
                    5'd10: begin query_char = 8'h0A; query_done_line = 1'b1; end
                    default: query_done_line = 1'b1;
                endcase
            end
            3'd2: begin // "RNG:L M R\r\n"
                case (resp_char)
                    5'd0: query_char = "R"; 5'd1: query_char = "N";
                    5'd2: query_char = "G"; 5'd3: query_char = ":";
                    5'd4: query_char = {3'd0, cfg_status[54:50]} + 8'h41;
                    5'd5: query_char = " ";
                    5'd6: query_char = {3'd0, cfg_status[49:45]} + 8'h41;
                    5'd7: query_char = " ";
                    5'd8: query_char = {3'd0, cfg_status[44:40]} + 8'h41;
                    5'd9: query_char = 8'h0D;
                    5'd10: begin query_char = 8'h0A; query_done_line = 1'b1; end
                    default: query_done_line = 1'b1;
                endcase
            end
            3'd3: begin // "GRD:L M R\r\n"
                case (resp_char)
                    5'd0: query_char = "G"; 5'd1: query_char = "R";
                    5'd2: query_char = "D"; 5'd3: query_char = ":";
                    5'd4: query_char = {3'd0, cfg_status[39:35]} + 8'h41;
                    5'd5: query_char = " ";
                    5'd6: query_char = {3'd0, cfg_status[34:30]} + 8'h41;
                    5'd7: query_char = " ";
                    5'd8: query_char = {3'd0, cfg_status[29:25]} + 8'h41;
                    5'd9: query_char = 8'h0D;
                    5'd10: begin query_char = 8'h0A; query_done_line = 1'b1; end
                    default: query_done_line = 1'b1;
                endcase
            end
            3'd4: begin // "POS:L M R\r\n"
                case (resp_char)
                    5'd0: query_char = "P"; 5'd1: query_char = "O";
                    5'd2: query_char = "S"; 5'd3: query_char = ":";
                    5'd4: query_char = {3'd0, pos_l} + 8'h41;
                    5'd5: query_char = " ";
                    5'd6: query_char = {3'd0, pos_m} + 8'h41;
                    5'd7: query_char = " ";
                    5'd8: query_char = {3'd0, pos_r} + 8'h41;
                    5'd9: query_char = 8'h0D;
                    5'd10: begin query_char = 8'h0A; query_done_line = 1'b1; end
                    default: query_done_line = 1'b1;
                endcase
            end
            3'd5: begin // "PLG:..." with scan
                if (resp_char < 5'd4) begin
                    // Emit "PLG:"
                    case (resp_char)
                        5'd0: query_char = "P"; 5'd1: query_char = "L";
                        5'd2: query_char = "G"; 5'd3: query_char = ":";
                        default: query_char = 8'd0;
                    endcase
                end else if (resp_char == 5'd4) begin
                    // Scanning/emitting pairs
                    case (plg_substate)
                        2'd0: begin
                            // Scanning: check current plug_scan entry
                            if (plug_scan > 5'd25) begin
                                // Done scanning; emit CR
                                query_char = 8'h0D;
                                // Move to CR/LF state
                            end else if (plug_partner > plug_scan) begin
                                // Found a pair
                                if (first_pair) begin
                                    // No space needed, emit first letter
                                    query_char = {3'd0, plug_scan} + 8'h41;
                                end else begin
                                    // Need space first
                                    query_char = " ";
                                end
                            end else begin
                                // Skip: not a pair or already emitted
                                query_no_emit = 1'b1;
                            end
                        end
                        2'd1: begin
                            // Emit first letter (after space for non-first pair)
                            query_char = {3'd0, plug_scan} + 8'h41;
                        end
                        2'd2: begin
                            // Emit second letter
                            query_char = {3'd0, plug_partner} + 8'h41;
                        end
                        default: query_no_emit = 1'b1;
                    endcase
                end else if (resp_char == 5'd5) begin
                    query_char = 8'h0A; // LF
                    query_done_line = 1'b1;
                end else begin
                    query_done_line = 1'b1;
                end
            end
            3'd6: begin // "OK\r\n"
                case (resp_char)
                    5'd0: query_char = "O"; 5'd1: query_char = "K";
                    5'd2: query_char = 8'h0D;
                    5'd3: query_char = 8'h0A;
                    default: query_done_all = 1'b1;
                endcase
            end
            default: query_done_all = 1'b1;
        endcase
    end

    // =========================================================================
    // Response state machine (sequential)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            resp_state   <= RESP_IDLE;
            done         <= 1'b0;
            tx_byte      <= 8'd0;
            tx_start     <= 1'b0;
            resp_idx     <= 3'd0;
            resp_phase   <= 3'd0;
            resp_char    <= 5'd0;
            plug_scan    <= 5'd0;
            first_pair   <= 1'b1;
            plg_substate <= 2'd0;
            lat_resp_ok  <= 1'b0;
            lat_is_query <= 1'b0;
        end else begin
            // Clear single-cycle pulses
            done     <= 1'b0;
            tx_start <= 1'b0;

            case (resp_state)
                RESP_IDLE: begin
                    if (start) begin
                        // Latch inputs and initialize registers
                        lat_resp_ok  <= resp_ok;
                        lat_is_query <= is_query;
                        resp_idx     <= 3'd0;
                        resp_phase   <= 3'd0;
                        resp_char    <= 5'd0;
                        plug_scan    <= 5'd0;
                        first_pair   <= 1'b1;
                        plg_substate <= 2'd0;
                        resp_state   <= RESP_ACTIVE;
                    end
                end

                RESP_ACTIVE: begin
                    if (lat_is_query) begin
                        // :? multi-line response
                        if (query_done_all) begin
                            done <= 1'b1;
                            resp_state <= RESP_IDLE;
                        end else if (query_no_emit) begin
                            // PLG scan: no pair at this index, advance scan
                            plug_scan <= plug_scan + 5'd1;
                            // Stay in RESP_ACTIVE, don't transmit
                        end else if (!tx_busy) begin
                            tx_byte <= query_char;
                            tx_start <= 1'b1;

                            // Advance state
                            if (query_done_line) begin
                                resp_phase <= resp_phase + 3'd1;
                                resp_char <= 5'd0;
                                plg_substate <= 2'd0;
                                plug_scan <= 5'd0;
                                first_pair <= 1'b1;
                            end else if (resp_phase == 3'd5 && resp_char == 5'd4) begin
                                // PLG scanning phase: advance sub-state
                                case (plg_substate)
                                    2'd0: begin
                                        if (plug_scan > 5'd25) begin
                                            // CR was emitted, go to LF
                                            resp_char <= 5'd5;
                                        end else if (first_pair) begin
                                            // First letter emitted (no space needed), go to second
                                            first_pair <= 1'b0;
                                            plg_substate <= 2'd2;
                                        end else begin
                                            // Space emitted, go to first letter
                                            plg_substate <= 2'd1;
                                        end
                                    end
                                    2'd1: begin
                                        // First letter emitted, go to second
                                        plg_substate <= 2'd2;
                                    end
                                    2'd2: begin
                                        // Second letter emitted, advance scan, back to scanning
                                        plug_scan <= plug_scan + 5'd1;
                                        plg_substate <= 2'd0;
                                    end
                                    default: plg_substate <= 2'd0;
                                endcase
                            end else begin
                                resp_char <= resp_char + 5'd1;
                            end
                        end
                    end else begin
                        // Simple OK or ERR
                        if (!tx_busy) begin
                            if (lat_resp_ok) begin
                                if (resp_idx < 3'd4) begin
                                    case (resp_idx)
                                        3'd0: tx_byte <= "O";
                                        3'd1: tx_byte <= "K";
                                        3'd2: tx_byte <= 8'h0D;
                                        3'd3: tx_byte <= 8'h0A;
                                        default: tx_byte <= 8'd0;
                                    endcase
                                    tx_start <= 1'b1;
                                    resp_idx <= resp_idx + 3'd1;
                                end else begin
                                    done <= 1'b1;
                                    resp_state <= RESP_IDLE;
                                end
                            end else begin
                                if (resp_idx < 3'd5) begin
                                    case (resp_idx)
                                        3'd0: tx_byte <= "E";
                                        3'd1: tx_byte <= "R";
                                        3'd2: tx_byte <= "R";
                                        3'd3: tx_byte <= 8'h0D;
                                        3'd4: tx_byte <= 8'h0A;
                                        default: tx_byte <= 8'd0;
                                    endcase
                                    tx_start <= 1'b1;
                                    resp_idx <= resp_idx + 3'd1;
                                end else begin
                                    done <= 1'b1;
                                    resp_state <= RESP_IDLE;
                                end
                            end
                        end
                    end
                end

                default: resp_state <= RESP_IDLE;
            endcase
        end
    end

endmodule
