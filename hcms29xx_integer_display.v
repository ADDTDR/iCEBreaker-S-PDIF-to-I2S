module hcms29xx_integer_display #(
    parameter integer CLOCK_DIVIDER = 10,
    parameter integer RESET_TICKS = 100
) (
    input wire i_clk,
    input wire [13:0] i_value,
    input wire [3:0] i_pwm,
    input wire [1:0] i_current,
    input wire i_sleep,
    output wire o_hcms_data,
    output wire o_hcms_clock,
    output wire o_hcms_regsel,
    output wire o_hcms_ncs,
    output wire o_hcms_reset
);
    reg [3:0] thousands_r = 4'd0;
    reg [3:0] hundreds_r = 4'd0;
    reg [3:0] tens_r = 4'd0;
    reg [3:0] ones_r = 4'd0;
    integer value_tmp;
    wire [13:0] value_clamped_w = (i_value > 14'd9999) ? 14'd9999 : i_value;

    // Decode any 14-bit value directly into decimal digits.
    always @(*) begin
        value_tmp = value_clamped_w;
        thousands_r = value_tmp / 1000;
        value_tmp = value_tmp % 1000;
        hundreds_r = value_tmp / 100;
        value_tmp = value_tmp % 100;
        tens_r = value_tmp / 10;
        ones_r = value_tmp % 10;
    end

    wire [159:0] frame_w = {
        digit_col(thousands_r, 3'd0),
        digit_col(thousands_r, 3'd1),
        digit_col(thousands_r, 3'd2),
        digit_col(thousands_r, 3'd3),
        digit_col(thousands_r, 3'd4),
        digit_col(hundreds_r, 3'd0),
        digit_col(hundreds_r, 3'd1),
        digit_col(hundreds_r, 3'd2),
        digit_col(hundreds_r, 3'd3),
        digit_col(hundreds_r, 3'd4),
        digit_col(tens_r, 3'd0),
        digit_col(tens_r, 3'd1),
        digit_col(tens_r, 3'd2),
        digit_col(tens_r, 3'd3),
        digit_col(tens_r, 3'd4),
        digit_col(ones_r, 3'd0),
        digit_col(ones_r, 3'd1),
        digit_col(ones_r, 3'd2),
        digit_col(ones_r, 3'd3),
        digit_col(ones_r, 3'd4)
    };

    hcms29xx #(
        .CLOCK_DIVIDER(CLOCK_DIVIDER),
        .RESET_TICKS(RESET_TICKS)
    ) display (
        .i_clk(i_clk),
        .i_frame(frame_w),
        .i_pwm(i_pwm),
        .i_current(i_current),
        .i_sleep(i_sleep),
        .o_data(o_hcms_data),
        .o_clock(o_hcms_clock),
        .o_regsel(o_hcms_regsel),
        .o_ncs(o_hcms_ncs),
        .o_reset(o_hcms_reset)
    );

    function [7:0] digit_col;
        input [3:0] digit;
        input [2:0] col;
        begin
            case (digit)
                4'd0: begin
                    case (col)
                        3'd0: digit_col = 8'h3E;
                        3'd1: digit_col = 8'h51;
                        3'd2: digit_col = 8'h49;
                        3'd3: digit_col = 8'h45;
                        default: digit_col = 8'h3E;
                    endcase
                end
                4'd1: begin
                    case (col)
                        3'd0: digit_col = 8'h00;
                        3'd1: digit_col = 8'h42;
                        3'd2: digit_col = 8'h7F;
                        3'd3: digit_col = 8'h40;
                        default: digit_col = 8'h00;
                    endcase
                end
                4'd2: begin
                    case (col)
                        3'd0: digit_col = 8'h42;
                        3'd1: digit_col = 8'h61;
                        3'd2: digit_col = 8'h51;
                        3'd3: digit_col = 8'h49;
                        default: digit_col = 8'h46;
                    endcase
                end
                4'd3: begin
                    case (col)
                        3'd0: digit_col = 8'h21;
                        3'd1: digit_col = 8'h41;
                        3'd2: digit_col = 8'h45;
                        3'd3: digit_col = 8'h4B;
                        default: digit_col = 8'h31;
                    endcase
                end
                4'd4: begin
                    case (col)
                        3'd0: digit_col = 8'h18;
                        3'd1: digit_col = 8'h14;
                        3'd2: digit_col = 8'h12;
                        3'd3: digit_col = 8'h7F;
                        default: digit_col = 8'h10;
                    endcase
                end
                4'd5: begin
                    case (col)
                        3'd0: digit_col = 8'h27;
                        3'd1: digit_col = 8'h45;
                        3'd2: digit_col = 8'h45;
                        3'd3: digit_col = 8'h45;
                        default: digit_col = 8'h39;
                    endcase
                end
                4'd6: begin
                    case (col)
                        3'd0: digit_col = 8'h3C;
                        3'd1: digit_col = 8'h4A;
                        3'd2: digit_col = 8'h49;
                        3'd3: digit_col = 8'h49;
                        default: digit_col = 8'h30;
                    endcase
                end
                4'd7: begin
                    case (col)
                        3'd0: digit_col = 8'h01;
                        3'd1: digit_col = 8'h71;
                        3'd2: digit_col = 8'h09;
                        3'd3: digit_col = 8'h05;
                        default: digit_col = 8'h03;
                    endcase
                end
                4'd8: begin
                    case (col)
                        3'd0: digit_col = 8'h36;
                        3'd1: digit_col = 8'h49;
                        3'd2: digit_col = 8'h49;
                        3'd3: digit_col = 8'h49;
                        default: digit_col = 8'h36;
                    endcase
                end
                4'd9: begin
                    case (col)
                        3'd0: digit_col = 8'h06;
                        3'd1: digit_col = 8'h49;
                        3'd2: digit_col = 8'h49;
                        3'd3: digit_col = 8'h29;
                        default: digit_col = 8'h1E;
                    endcase
                end
                default: begin
                    digit_col = 8'h00;
                end
            endcase
        end
    endfunction
endmodule