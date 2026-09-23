// Cheap octave-band spectrum estimator: a cascade of one-pole low passes whose
// stage-to-stage difference gives the band energy (a filter bank rather than a
// literal FFT, which is what fits in the iCE40 fabric).
module audio_spectrum_bands (
    input wire i_clk,
    input wire i_strobe,
    input wire signed [15:0] i_sample,
    output reg [29:0] o_bars = 0
);
    localparam integer BANDS = 10;

    reg [BANDS*24-1:0] lp_flat = 0;
    reg [BANDS*16-1:0] env_flat = 0;
    reg [BANDS*3-1:0] bars_work = 0;
    reg signed [23:0] lp_previous = 0;
    reg signed [23:0] lp_current_reg = 0;
    reg signed [23:0] difference_reg = 0;
    reg signed [23:0] lp_next_reg = 0;
    reg [15:0] magnitude_reg = 0;
    reg [15:0] envelope_current_reg = 0;
    reg [3:0] band_index = 0;
    reg [1:0] phase = 0;
    reg busy = 0;

    wire signed [23:0] x_ext = {i_sample, 8'd0};
    wire signed [23:0] lp_current = $signed(lp_flat[23:0]);
    wire signed [23:0] band_value = (band_index == BANDS - 1) ? lp_current_reg
                                                                       : difference_reg;
    wire [23:0] band_abs = band_value[23] ? (~band_value + 1'b1) : band_value;
    wire [15:0] envelope_next = (magnitude_reg > envelope_current_reg) ? magnitude_reg
                              : (envelope_current_reg - (envelope_current_reg >> 6));

    always @(posedge i_clk) begin
        if (i_strobe && !busy) begin
            lp_previous <= x_ext;
            band_index <= 0;
            phase <= 0;
            busy <= 1'b1;
        end else if (busy) begin
            case (phase)
                2'd0: begin
                    lp_current_reg <= lp_current;
                    envelope_current_reg <= env_flat[15:0];
                    phase <= 2'd1;
                end
                2'd1: begin
                    difference_reg <= lp_previous - lp_current_reg;
                    phase <= 2'd2;
                end
                2'd2: begin
                    lp_next_reg <= lp_current_reg + filter_step(difference_reg, band_index);
                    magnitude_reg <= band_abs[23:8];
                    phase <= 2'd3;
                end
                default: begin
                    lp_flat <= {lp_next_reg, lp_flat[BANDS*24-1:24]};
                    env_flat <= {envelope_next, env_flat[BANDS*16-1:16]};
                    bars_work <= {level_of(envelope_next), bars_work[BANDS*3-1:3]};
                    lp_previous <= lp_current_reg;
                    phase <= 0;

                    if (band_index == BANDS - 1) begin
                        o_bars <= {level_of(envelope_next), bars_work[BANDS*3-1:3]};
                        busy <= 1'b0;
                    end else begin
                        band_index <= band_index + 1'b1;
                    end
                end
            endcase
        end
    end

    function signed [23:0] filter_step;
        input signed [23:0] value;
        input [3:0] index;
        begin
            case (index)
                4'd0: filter_step = value >>> 1;
                4'd1: filter_step = value >>> 2;
                4'd2: filter_step = value >>> 3;
                4'd3: filter_step = value >>> 4;
                4'd4: filter_step = value >>> 5;
                4'd5: filter_step = value >>> 6;
                4'd6: filter_step = value >>> 7;
                4'd7: filter_step = value >>> 8;
                4'd8: filter_step = value >>> 9;
                default: filter_step = value >>> 10;
            endcase
        end
    endfunction

    // Log-ish mapping of envelope magnitude onto the 7 visible dot rows.
    function [2:0] level_of;
        input [15:0] mag;
        begin
            if (mag[15:14] != 2'b00) level_of = 3'd7;
            else if (mag[13]) level_of = 3'd6;
            else if (mag[12]) level_of = 3'd5;
            else if (mag[11]) level_of = 3'd4;
            else if (mag[10]) level_of = 3'd3;
            else if (mag[9]) level_of = 3'd2;
            else if (mag[8]) level_of = 3'd1;
            else level_of = 3'd0;
        end
    endfunction
endmodule

// 20 bar spectrum display: 10 bars for the left channel on the first two
// characters and 10 bars for the right channel on the last two.
module hcms29xx_fft_display #(
    parameter integer CLOCK_DIVIDER = 10,
    parameter integer RESET_TICKS = 100
) (
    input wire i_clk,
    input wire [29:0] i_bars_l,
    input wire [29:0] i_bars_r,
    input wire [3:0] i_pwm,
    input wire [1:0] i_current,
    input wire i_sleep,
    output wire o_hcms_data,
    output wire o_hcms_clock,
    output wire o_hcms_regsel,
    output wire o_hcms_ncs,
    output wire o_hcms_reset
);
    wire [159:0] frame_w = {
        bar_col(i_bars_l[2:0]),
        bar_col(i_bars_l[5:3]),
        bar_col(i_bars_l[8:6]),
        bar_col(i_bars_l[11:9]),
        bar_col(i_bars_l[14:12]),
        bar_col(i_bars_l[17:15]),
        bar_col(i_bars_l[20:18]),
        bar_col(i_bars_l[23:21]),
        bar_col(i_bars_l[26:24]),
        bar_col(i_bars_l[29:27]),
        
        bar_col(i_bars_r[2:0]),
        bar_col(i_bars_r[5:3]),
        bar_col(i_bars_r[8:6]),
        bar_col(i_bars_r[11:9]),
        bar_col(i_bars_r[14:12]),
        bar_col(i_bars_r[17:15]),
        bar_col(i_bars_r[20:18]),
        bar_col(i_bars_r[23:21]),
        bar_col(i_bars_r[26:24]),
        bar_col(i_bars_r[29:27])
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

    // Bit 6 is the bottom row, so the bar grows upwards from the baseline.
    function [7:0] bar_col;
        input [2:0] level;
        begin
            bar_col = 8'h7F & (8'h7F << (3'd7 - level));
        end
    endfunction
endmodule
