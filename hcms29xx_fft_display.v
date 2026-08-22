// Cheap octave-band spectrum estimator: a cascade of one-pole low passes whose
// stage-to-stage difference gives the band energy (a filter bank rather than a
// literal FFT, which is what fits in the iCE40 fabric).
module audio_spectrum_bands (
    input wire i_clk,
    input wire i_strobe,
    input wire signed [15:0] i_sample,
    output wire [20:0] o_bars
);
    localparam integer BANDS = 7;

    reg [BANDS*24-1:0] lp_flat = 0;
    reg [BANDS*16-1:0] env_flat = 0;

    wire signed [23:0] x_ext = {i_sample, 8'd0};

    genvar k;
    generate
        for (k = 0; k < BANDS; k = k + 1) begin : band
            wire signed [23:0] lp_cur = $signed(lp_flat[k*24 +: 24]);
            wire signed [23:0] lp_prev = (k == 0) ? x_ext
                                                  : $signed(lp_flat[((k == 0) ? 0 : k - 1)*24 +: 24]);
            wire signed [23:0] diff = lp_prev - lp_cur;
            wire signed [23:0] band_val = (k == BANDS - 1) ? lp_cur : diff;
            wire [23:0] band_abs = band_val[23] ? (~band_val + 1'b1) : band_val;
            wire [15:0] mag = band_abs[23:8];
            wire [15:0] env_cur = env_flat[k*16 +: 16];

            always @(posedge i_clk) begin
                if (i_strobe) begin
                    lp_flat[k*24 +: 24] <= lp_cur + (diff >>> (k + 1));
                    env_flat[k*16 +: 16] <= (mag > env_cur) ? mag
                                                            : (env_cur - (env_cur >> 6));
                end
            end

            assign o_bars[k*3 +: 3] = level_of(env_cur);
        end
    endgenerate

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

// 14 bar spectrum display: 7 bars for the left channel on the first two
// characters and 7 bars for the right channel on the last two.
module hcms29xx_fft_display #(
    parameter integer CLOCK_DIVIDER = 10,
    parameter integer RESET_TICKS = 100
) (
    input wire i_clk,
    input wire [20:0] i_bars_l,
    input wire [20:0] i_bars_r,
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
        8'h00,
        8'h00,
        8'h00,
        8'h00,
        8'h00,
        8'h00,
        bar_col(i_bars_r[2:0]),
        bar_col(i_bars_r[5:3]),
        bar_col(i_bars_r[8:6]),
        bar_col(i_bars_r[11:9]),
        bar_col(i_bars_r[14:12]),
        bar_col(i_bars_r[17:15]),
        bar_col(i_bars_r[20:18])
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
