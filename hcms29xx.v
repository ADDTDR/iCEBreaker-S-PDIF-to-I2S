// HCMS-29xx four-character display controller.
// DATA is stable while CLOCK is low and sampled on CLOCK rising edges.
module hcms29xx #(
    parameter integer CLOCK_DIVIDER = 12,
    parameter integer RESET_TICKS = 36
) (
    input wire i_clk,
    input wire [159:0] i_frame,
    input [3:0] i_pwm,
    input [1:0] i_current,
    input i_sleep,
    output reg o_data = 1'b0,
    output reg o_clock = 1'b0,
    output reg o_regsel = 1'b0,
    output reg o_ncs = 1'b1,
    output reg o_reset = 1'b0
);

    localparam [3:0] ST_RESET = 4'd0;
    localparam [3:0] ST_CFG0_START = 4'd1;
    localparam [3:0] ST_CFG0_SEND = 4'd2;
    localparam [3:0] ST_CFG0_END = 4'd3;
    localparam [3:0] ST_CFG1_START = 4'd4;
    localparam [3:0] ST_CFG1_SEND = 4'd5;
    localparam [3:0] ST_CFG1_END = 4'd6;
    localparam [3:0] ST_DATA_START = 4'd7;
    localparam [3:0] ST_DATA_SEND = 4'd8;
    localparam [3:0] ST_DATA_END = 4'd9;


    localparam CFG_WORD_0_SEL = 1'b0;
    localparam CFG_WORD_1_SEL = 1'b1;


    reg [3:0] state = ST_RESET;
    reg [31:0] divider = 0;
    reg [31:0] reset_count = 0;
    reg [7:0] shift_register = 0;
    reg [2:0] bit_index = 0;
    reg [1:0] phase = 0;
    reg [4:0] frame_index = 0;


    wire [7:0] w_control_word_0 = {CFG_WORD_0_SEL, i_sleep, i_current, i_pwm};
    wire [7:0] w_control_word_1 = {CFG_WORD_1_SEL, 5'b00000, 1'b0, 1'b1};

    function [7:0] frame_byte;
        input [159:0] frame;
        input [4:0] index;
        begin
            frame_byte = frame >> ((19 - index) * 8);
        end
    endfunction

    always @(posedge i_clk) begin
        if (divider == CLOCK_DIVIDER - 1) begin
            divider <= 0;
            case (state)
                ST_RESET: begin
                    o_reset <= 1'b0;
                    o_ncs <= 1'b1;
                    o_clock <= 1'b0;
                    if (reset_count == RESET_TICKS - 1) begin
                        o_reset <= 1'b1;
                        state <= ST_CFG0_START;
                    end else begin
                        reset_count <= reset_count + 1'b1;
                    end
                end

                ST_CFG0_START: begin
                    o_regsel <= 1'b1;
                    o_ncs <= 1'b1;
                    o_clock <= 1'b1;
                    // set 8'h4d in binary form  
                    shift_register <= w_control_word_1;
                    bit_index <= 0;
                    phase <= 0;
                    state <= ST_CFG0_SEND;
                end

                ST_CFG0_SEND: begin
                    case (phase)
                        0: begin o_ncs <= 1'b0; phase <= 1; end
                        1: begin o_data <= shift_register[7]; o_clock <= 1'b0; phase <= 2; end
                        2: begin o_clock <= 1'b1; phase <= 3; end
                        default: begin
                            if (bit_index == 7) begin
                                o_ncs <= 1'b1;
                                state <= ST_CFG0_END;
                            end else begin
                                shift_register <= {shift_register[6:0], 1'b0};
                                bit_index <= bit_index + 1'b1;
                                phase <= 1;
                            end
                        end
                    endcase
                end

                ST_CFG0_END: begin
                    o_clock <= 1'b0;
                    state <= ST_CFG1_START;
                end

                ST_CFG1_START: begin
                    o_regsel <= 1'b1;
                    o_ncs <= 1'b1;
                    o_clock <= 1'b1;
                    shift_register <= w_control_word_0;
                    bit_index <= 0;
                    phase <= 0;
                    state <= ST_CFG1_SEND;
                end

                ST_CFG1_SEND: begin
                    case (phase)
                        0: begin o_ncs <= 1'b0; phase <= 1; end
                        1: begin o_data <= shift_register[7]; o_clock <= 1'b0; phase <= 2; end
                        2: begin o_clock <= 1'b1; phase <= 3; end
                        default: begin
                            if (bit_index == 7) begin
                                o_ncs <= 1'b1;
                                state <= ST_CFG1_END;
                            end else begin
                                shift_register <= {shift_register[6:0], 1'b0};
                                bit_index <= bit_index + 1'b1;
                                phase <= 1;
                            end
                        end
                    endcase
                end

                ST_CFG1_END: begin
                    o_clock <= 1'b0;
                    frame_index <= 0;
                    state <= ST_DATA_START;
                end

                ST_DATA_START: begin
                    o_regsel <= 1'b0;
                    o_ncs <= 1'b1;
                    o_clock <= 1'b1;
                    shift_register <= frame_byte(i_frame, frame_index);
                    bit_index <= 0;
                    phase <= 0;
                    state <= ST_DATA_SEND;
                end

                ST_DATA_SEND: begin
                    case (phase)
                        0: begin o_ncs <= 1'b0; phase <= 1; end
                        1: begin o_data <= shift_register[7]; o_clock <= 1'b0; phase <= 2; end
                        2: begin o_clock <= 1'b1; phase <= 3; end
                        default: begin
                            if (bit_index == 7) begin
                                if (frame_index == 19) begin
                                    o_ncs <= 1'b1;
                                    state <= ST_DATA_END;
                                end
                                else begin
                                    frame_index <= frame_index + 1'b1;
                                    shift_register <= frame_byte(i_frame, frame_index + 1'b1);
                                    bit_index <= 0;
                                    phase <= 1;
                                end
                            end else begin
                                shift_register <= {shift_register[6:0], 1'b0};
                                bit_index <= bit_index + 1'b1;
                                phase <= 1;
                            end
                        end
                    endcase
                end

                ST_DATA_END: begin
                    o_clock <= 1'b0;
                    frame_index <= 0;
                    // To update only data  state <= ST_DATA_START;
                    // Update configuration and data
                    state <= ST_CFG0_START;
                end

                default: state <= ST_RESET;
            endcase
        end else begin
            divider <= divider + 1'b1;
        end
    end
endmodule