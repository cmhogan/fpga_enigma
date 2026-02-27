// Copyright (c) 2026, Chad Hogan
// All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// fsm_controller.v
// — 13-state FSM for FPGA Enigma I
// Orchestrates startup, cipher, command parsing, and reset operations.

module fsm_controller #(
    parameter TIMEOUT_LIMIT = 36000000
) (
    input  wire        clk,
    input  wire        rst_n,
    // UART interface
    input  wire [7:0]  rx_byte,
    input  wire        rx_valid,
    input  wire        tx_busy,
    output wire [7:0]  tx_byte,
    output wire        tx_start,
    // Cipher path
    input  wire [4:0]  mid_letter_fwd,
    input  wire [4:0]  ct_index,
    output reg  [4:0]  pt_index       = 5'd0,
    output reg  [4:0]  mid_letter_reg = 5'd0,
    // Stepper control
    output reg         step_pulse     = 1'b0,
    output reg         load_pulse     = 1'b0,
    // Config manager control
    output reg         cfg_wr_rotor     = 1'b0,
    output reg         cfg_wr_ring      = 1'b0,
    output reg         cfg_wr_grund     = 1'b0,
    output reg         cfg_wr_plug_add  = 1'b0,
    output reg         cfg_wr_plug_clr  = 1'b0,
    output reg         cfg_wr_factory   = 1'b0,
    output reg  [15:0] cfg_data       = 16'd0,
    // Config status from config_manager (passed to response_generator)
    input  wire [63:0] cfg_status,
    // Live positions from stepper (for :? response)
    input  wire [4:0]  pos_l,
    input  wire [4:0]  pos_m,
    input  wire [4:0]  pos_r,
    // Plugboard map (for :? response and :S validation)
    input  wire [129:0] plug_map,
    input  wire [4:0]   plug_pair_cnt,
    // Error LED
    output reg         error_led      = 1'b0,
    // Command mode indicator
    output wire        cmd_mode
);

    // =========================================================================
    // State encodings
    // =========================================================================
    localparam [3:0] STARTUP_DELAY       = 4'b0000,
                     STARTUP             = 4'b0001,
                     IDLE                = 4'b0010,
                     STEP                = 4'b0011,
                     CIPHER_A            = 4'b0100,
                     TRANSMIT            = 4'b0101,
                     CMD_ARG             = 4'b0110,
                     CMD_EXEC            = 4'b0111,
                     CMD_RESP            = 4'b1000,
                     RESET_GRUNDSTELLUNG = 4'b1001,
                     FACTORY_RESET       = 4'b1010,
                     CIPHER_B            = 4'b1011,
                     CMD_OPCODE          = 4'b1100,
                     STEP_WAIT           = 4'b1101;

    reg [3:0] state = STARTUP_DELAY;

    // =========================================================================
    // Command mode indicator
    // =========================================================================
    assign cmd_mode = (state == CMD_OPCODE) || (state == CMD_ARG) ||
                      (state == CMD_EXEC) || (state == CMD_RESP);

    // =========================================================================
    // Startup delay counter
    // =========================================================================
    reg [13:0] delay_cnt = 14'd0;

    // =========================================================================
    // Startup banner ROM: "ENIGMA I READY\r\n" (16 bytes)
    // =========================================================================
    reg [4:0] banner_idx = 5'd0;
    reg send_banner_after = 1'b0;

    function [7:0] banner_char;
        input [4:0] idx;
        case (idx)
            5'd0:  banner_char = "E";  5'd1:  banner_char = "N";
            5'd2:  banner_char = "I";  5'd3:  banner_char = "G";
            5'd4:  banner_char = "M";  5'd5:  banner_char = "A";
            5'd6:  banner_char = " ";  5'd7:  banner_char = "I";
            5'd8:  banner_char = " ";  5'd9:  banner_char = "R";
            5'd10: banner_char = "E";  5'd11: banner_char = "A";
            5'd12: banner_char = "D";  5'd13: banner_char = "Y";
            5'd14: banner_char = 8'h0D; 5'd15: banner_char = 8'h0A;
            default: banner_char = 8'h00;
        endcase
    endfunction

    // =========================================================================
    // Command parsing registers
    // =========================================================================
    reg [7:0]  cmd_opcode    = 8'd0;
    reg [2:0]  arg_count     = 3'd0;
    /* verilator lint_off UNUSED */
    reg [23:0] arg_buf       = 24'd0;
    /* verilator lint_on UNUSED */
    /* verilator lint_off UNUSED */
    reg [4:0]  ct_latch      = 5'd0;
    /* verilator lint_on UNUSED */
    reg [3:0]  return_state  = IDLE;

    // Command timeout (default 3 seconds at 12 MHz = 36,000,000 clocks)
    reg [25:0] timeout_cnt   = 26'd0;

    // =========================================================================
    // Response registers
    // =========================================================================
    reg        resp_ok       = 1'b0;
    reg        is_query      = 1'b0;
    reg        resp_start    = 1'b0;
    wire       resp_done;

    // =========================================================================
    // Input classification (combinational)
    // =========================================================================
    wire is_upper = (rx_byte >= "A" && rx_byte <= "Z");
    wire is_lower = (rx_byte >= "a" && rx_byte <= "z");
    wire is_alpha = is_upper || is_lower;
    wire is_colon = (rx_byte == ":");
    wire is_crlf  = (rx_byte == 8'h0D) || (rx_byte == 8'h0A);
    wire is_hyphen = (rx_byte == "-");
    wire [7:0] rx_upper = rx_byte & 8'h5F;

    // =========================================================================
    // Response generator sub-module
    // =========================================================================
    wire [7:0] resp_tx_byte;
    wire       resp_tx_start;

    response_generator u_resp (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (resp_start),
        .resp_ok    (resp_ok),
        .is_query   (is_query),
        .done       (resp_done),
        .tx_busy    (tx_busy),
        .tx_byte    (resp_tx_byte),
        .tx_start   (resp_tx_start),
        .cfg_status (cfg_status),
        .pos_l      (pos_l),
        .pos_m      (pos_m),
        .pos_r      (pos_r),
        .plug_map   (plug_map)
    );

    // =========================================================================
    // TX output mux: FSM owns TX except during CMD_RESP (response_generator owns)
    // Since CMD_RESP is mutually exclusive with all other TX-driving states,
    // resp_tx_start is 0 when idle and fsm_tx_start is 0 during CMD_RESP.
    // =========================================================================
    reg  [7:0] fsm_tx_byte  = 8'd0;
    reg        fsm_tx_start = 1'b0;

    assign tx_start = fsm_tx_start | resp_tx_start;
    assign tx_byte  = resp_tx_start ? resp_tx_byte : fsm_tx_byte;

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STARTUP_DELAY;
            delay_cnt <= 14'd0;
            banner_idx <= 5'd0;
            fsm_tx_start <= 1'b0;
            step_pulse <= 1'b0;
            load_pulse <= 1'b0;
            cfg_wr_rotor <= 1'b0;
            cfg_wr_ring <= 1'b0;
            cfg_wr_grund <= 1'b0;
            cfg_wr_plug_add <= 1'b0;
            cfg_wr_plug_clr <= 1'b0;
            cfg_wr_factory <= 1'b0;
            error_led <= 1'b0;
            resp_start <= 1'b0;
        end else begin
            // Clear single-cycle pulses
            fsm_tx_start   <= 1'b0;
            step_pulse     <= 1'b0;
            load_pulse     <= 1'b0;
            cfg_wr_rotor   <= 1'b0;
            cfg_wr_ring    <= 1'b0;
            cfg_wr_grund   <= 1'b0;
            cfg_wr_plug_add <= 1'b0;
            cfg_wr_plug_clr <= 1'b0;
            cfg_wr_factory <= 1'b0;
            resp_start     <= 1'b0;

            case (state)
                STARTUP_DELAY: begin
                    if (delay_cnt == 14'd12000) begin
                        state <= STARTUP;
                        banner_idx <= 5'd0;
                    end else begin
                        delay_cnt <= delay_cnt + 14'd1;
                    end
                end

                STARTUP: begin
                    if (banner_idx == 5'd16) begin
                        if (send_banner_after) begin
                            send_banner_after <= 1'b0;
                            load_pulse <= 1'b1;  // reload positions from (now-reset) grundstellung
                            resp_ok <= 1'b1;
                            is_query <= 1'b0;
                            resp_start <= 1'b1;
                            state <= CMD_RESP;
                        end else begin
                            state <= IDLE;
                        end
                    end else if (!tx_busy) begin
                        fsm_tx_byte <= banner_char(banner_idx);
                        fsm_tx_start <= 1'b1;
                        banner_idx <= banner_idx + 5'd1;
                        // Stay in STARTUP; next cycle tx_busy goes high,
                        // so we wait until it clears before sending next char.
                    end
                end

                IDLE: begin
                    error_led <= 1'b0;
                    if (rx_valid) begin
                        if (is_alpha) begin
                            pt_index <= rx_upper[4:0] - 5'd1; // A=0x41&0x5F=0x41, -0x41 would be -65, but 0x41[4:0]=1, -1=0
                            state <= STEP;
                        end else if (is_colon) begin
                            state <= CMD_OPCODE;
                            timeout_cnt <= 26'd0;
                        end
                    end
                end

                STEP: begin
                    step_pulse <= 1'b1;
                    state <= STEP_WAIT;
                end

                // Wait one cycle for stepper positions to settle
                STEP_WAIT: begin
                    state <= CIPHER_A;
                end

                CIPHER_A: begin
                    mid_letter_reg <= mid_letter_fwd;
                    state <= CIPHER_B;
                end

                CIPHER_B: begin
                    ct_latch <= ct_index;
                    // Preload tx_byte, go to TRANSMIT which will wait for !tx_busy
                    fsm_tx_byte <= {3'd0, ct_index} + 8'h41;
                    return_state <= IDLE;
                    state <= TRANSMIT;
                end

                TRANSMIT: begin
                    // Wait for TX to be ready, then fire tx_start
                    if (!tx_busy) begin
                        fsm_tx_start <= 1'b1;
                        state <= return_state;
                    end
                end

                CMD_OPCODE: begin
                    if (rx_valid) begin
                        cmd_opcode <= rx_upper;
                        case (rx_upper)
                            "R", "N", "P": begin
                                arg_count <= 3'd3;
                                arg_buf <= 24'd0;
                                state <= CMD_ARG;
                                timeout_cnt <= 26'd0;
                            end
                            "S": begin
                                arg_count <= 3'd2;
                                arg_buf <= 24'd0;
                                state <= CMD_ARG;
                                timeout_cnt <= 26'd0;
                            end
                            "U": begin
                                arg_count <= 3'd1;
                                arg_buf <= 24'd0;
                                state <= CMD_ARG;
                                timeout_cnt <= 26'd0;
                            end
                            "G": state <= RESET_GRUNDSTELLUNG;
                            "F": state <= FACTORY_RESET;
                            default: begin
                                // "?" doesn't survive rx_upper masking, check rx_byte directly
                                if (rx_byte == "?") begin
                                    cmd_opcode <= 8'h3F;
                                    state <= CMD_EXEC;
                                end else begin
                                    error_led <= 1'b1;
                                    resp_ok <= 1'b0;
                                    is_query <= 1'b0;
                                    resp_start <= 1'b1;
                                    state <= CMD_RESP;
                                end
                            end
                        endcase
                    end else begin
                        if (timeout_cnt >= TIMEOUT_LIMIT)
                            state <= IDLE;
                        else
                            timeout_cnt <= timeout_cnt + 26'd1;
                    end
                end

                CMD_ARG: begin
                    if (rx_valid) begin
                        timeout_cnt <= 26'd0;
                        if (is_crlf) begin
                            state <= CMD_EXEC;
                        end else if (is_colon) begin
                            // New command abort
                            cmd_opcode <= 8'd0;
                            state <= CMD_OPCODE;
                            timeout_cnt <= 26'd0;
                        end else if (arg_count > 3'd0) begin
                            // Shift argument in
                            if (cmd_opcode == "R") begin
                                // Rotor digit: '1'->0 .. '5'->4
                                arg_buf <= {arg_buf[20:0], rx_byte[2:0] - 3'd1};
                            end else if (is_hyphen) begin
                                // Literal hyphen for :S--
                                arg_buf <= {arg_buf[15:0], 8'h2D};
                            end else begin
                                // Letter: convert to 0-25 index
                                arg_buf <= {arg_buf[18:0], rx_upper[4:0] - 5'd1};
                            end
                            arg_count <= arg_count - 3'd1;
                        end
                        // If arg_count == 0 and not CR/LF, wait for CR/LF
                    end else begin
                        if (timeout_cnt >= TIMEOUT_LIMIT)
                            state <= IDLE;
                        else
                            timeout_cnt <= timeout_cnt + 26'd1;
                    end
                end

                CMD_EXEC: begin
                    resp_ok <= 1'b0;
                    is_query <= 1'b0;
                    error_led <= 1'b0;

                    case (cmd_opcode)
                        "R": begin
                            if (arg_buf[8:6] < 3'd5 && arg_buf[5:3] < 3'd5 && arg_buf[2:0] < 3'd5 &&
                                arg_buf[8:6] != arg_buf[5:3] &&
                                arg_buf[8:6] != arg_buf[2:0] &&
                                arg_buf[5:3] != arg_buf[2:0]) begin
                                cfg_data <= {7'b0, arg_buf[8:0]};
                                cfg_wr_rotor <= 1'b1;
                                load_pulse <= 1'b1;
                                resp_ok <= 1'b1;
                            end else begin
                                error_led <= 1'b1;
                            end
                        end

                        "N": begin
                            if (arg_buf[14:10] < 5'd26 && arg_buf[9:5] < 5'd26 && arg_buf[4:0] < 5'd26) begin
                                cfg_data <= {1'b0, arg_buf[14:0]};
                                cfg_wr_ring <= 1'b1;
                                resp_ok <= 1'b1;
                            end else begin
                                error_led <= 1'b1;
                            end
                        end

                        "P": begin
                            if (arg_buf[14:10] < 5'd26 && arg_buf[9:5] < 5'd26 && arg_buf[4:0] < 5'd26) begin
                                cfg_data <= {1'b0, arg_buf[14:0]};
                                cfg_wr_grund <= 1'b1;
                                resp_ok <= 1'b1;
                            end else begin
                                error_led <= 1'b1;
                            end
                        end

                        "S": begin
                            // Check :S-- vs :SXY
                            if (arg_buf[15:8] == 8'h2D && arg_buf[7:0] == 8'h2D) begin
                                cfg_wr_plug_clr <= 1'b1;
                                resp_ok <= 1'b1;
                            end else begin
                                if (arg_buf[9:5] < 5'd26 && arg_buf[4:0] < 5'd26 &&
                                    arg_buf[9:5] != arg_buf[4:0] &&
                                    plug_map[arg_buf[9:5] * 5 +: 5] == arg_buf[9:5] &&
                                    plug_map[arg_buf[4:0] * 5 +: 5] == arg_buf[4:0] &&
                                    plug_pair_cnt < 5'd13) begin
                                    cfg_data <= {6'b0, arg_buf[9:0]};
                                    cfg_wr_plug_add <= 1'b1;
                                    resp_ok <= 1'b1;
                                end else begin
                                    error_led <= 1'b1;
                                end
                            end
                        end

                        "U": begin
                            if (arg_buf[4:0] == 5'd1) begin // 'B' -> index 1
                                resp_ok <= 1'b1;
                            end else begin
                                error_led <= 1'b1;
                            end
                        end

                        "?": begin
                            is_query <= 1'b1;
                            resp_ok <= 1'b1;
                        end

                        default: error_led <= 1'b1;
                    endcase

                    resp_start <= 1'b1;
                    state <= CMD_RESP;
                end

                CMD_RESP: begin
                    if (resp_done) begin
                        state <= IDLE;
                        is_query <= 1'b0;
                    end
                end

                RESET_GRUNDSTELLUNG: begin
                    load_pulse <= 1'b1;
                    resp_ok <= 1'b1;
                    is_query <= 1'b0;
                    resp_start <= 1'b1;
                    state <= CMD_RESP;
                end

                FACTORY_RESET: begin
                    cfg_wr_factory <= 1'b1;
                    banner_idx <= 5'd0;
                    send_banner_after <= 1'b1;
                    state <= STARTUP;
                end

                default: state <= IDLE;
            endcase
        end
    end

`ifdef SIMULATION
reg tx_start_prev;
initial tx_start_prev = 1'b0;

always @(posedge clk) begin
    if (!rst_n) begin
        tx_start_prev <= 1'b0;
    end else begin
        tx_start_prev <= tx_start;
    end
end

always @(posedge clk) begin
    if (rst_n) begin
        // Verify state is a valid encoding
        case (state)
            STARTUP_DELAY, STARTUP, IDLE, STEP, CIPHER_A, CIPHER_B,
            TRANSMIT, CMD_OPCODE, CMD_ARG, CMD_EXEC, CMD_RESP,
            RESET_GRUNDSTELLUNG, FACTORY_RESET, STEP_WAIT: ; // valid
            default: begin
                $display("ASSERTION FAIL: fsm_controller: invalid state=%b", state);
                $fatal(1);
            end
        endcase

        // Verify tx_start rising edge doesn't occur when tx_busy is high
        if (tx_start && !tx_start_prev && tx_busy) begin
            $display("ASSERTION FAIL: fsm_controller: tx_start rising edge while tx_busy");
            $fatal(1);
        end
    end
end
`endif

endmodule
