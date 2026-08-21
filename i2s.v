
 module i2s_tx #(
     parameter integer SAMPLE_BITS = 16,
     parameter integer CHANNEL_BITS = 32,
     parameter [31:0] PHASE_INCREMENT = 32'h20c49ba6
 )(
     input  wire clk,
     input  wire signed [SAMPLE_BITS-1:0] sample_l,
     input  wire signed [SAMPLE_BITS-1:0] sample_r,
     input  wire signed [31:0] rate_adjust,
     output reg  sample_req = 0,
     output reg  bclk = 0,
     output reg  lrclk = 0,
     output reg  sdata = 0
 );
     // The phase accumulator generates a nominal 6.144 MHz BCLK and 96 kHz
     // LRCLK from 96 MHz. rate_adjust permits slow source-rate tracking.
     localparam integer RIGHT_SLOT_FIRST = CHANNEL_BITS;
     localparam integer RIGHT_DATA_LAST = CHANNEL_BITS + SAMPLE_BITS - 1;
     localparam integer LEFT_SLOT_LAST = CHANNEL_BITS - 1;
     localparam integer SLOT_LAST = (2 * CHANNEL_BITS) - 1;

     reg [31:0] phase_accumulator = 0;
     reg [15:0] slot = 0;
     reg signed [SAMPLE_BITS-1:0] sample_l_hold = 0;
     reg signed [SAMPLE_BITS-1:0] sample_r_hold = 0;
     wire signed [32:0] phase_step = $signed({1'b0, PHASE_INCREMENT}) + rate_adjust;
     wire [32:0] phase_sum = {1'b0, phase_accumulator} + phase_step;

     always @(posedge clk) begin
         sample_req <= 1'b0;
         phase_accumulator <= phase_sum[31:0];

         if (phase_sum[32]) begin
             bclk <= ~bclk;

             // Update SDATA on one BCLK phase and hold it stable on the other.
             if (bclk) begin
                 if (slot == 0) begin
                     sample_l_hold <= sample_l;
                     sample_r_hold <= sample_r;
                     sdata <= sample_l[SAMPLE_BITS - 1];
                 end else if (slot > 0 && slot < SAMPLE_BITS) begin
                     sdata <= sample_l_hold[SAMPLE_BITS - 1 - slot];
                 end else if (slot == RIGHT_SLOT_FIRST) begin
                     sdata <= sample_r_hold[SAMPLE_BITS - 1];
                 end else if (slot > RIGHT_SLOT_FIRST && slot <= RIGHT_DATA_LAST) begin
                     sdata <= sample_r_hold[RIGHT_DATA_LAST - slot];
                 end else begin
                     sdata <= 1'b0;
                 end

                 // Standard I2S: LRCLK changes one bit clock before the next
                 // channel's MSB. Low selects left, high selects right.
                 if (slot == LEFT_SLOT_LAST)
                     lrclk <= 1'b1;
                 else if (slot == SLOT_LAST)
                     lrclk <= 1'b0;

                 if (slot == SLOT_LAST) begin
                     slot <= 0;
                     sample_req <= 1'b1;
                 end else begin
                     slot <= slot + 1'b1;
                 end
             end
         end
     end
 endmodule

module i2s_mic_rx #(
    parameter integer SAMPLE_BITS = 16,
    parameter integer MIC_BITS = 24
)(
    input  wire clk,
    input  wire bclk,
    input  wire lrclk,
    input  wire mic_sdata,
    output reg  signed [SAMPLE_BITS-1:0] sample_l = 0,
    output reg  signed [SAMPLE_BITS-1:0] sample_r = 0,
    output reg  sample_strobe = 0,
    output reg  frame_active = 0
);
    reg bclk_d = 1'b0;
    reg lrclk_at_bclk = 1'b0;
    reg [5:0] bit_count = 6'd0;
    reg [MIC_BITS-1:0] shift_reg = {MIC_BITS{1'b0}};
    reg [23:0] activity_watchdog = 24'hffffff;

    wire bclk_rise = !bclk_d && bclk;
    wire [MIC_BITS-1:0] shifted_word = {shift_reg[MIC_BITS-2:0], mic_sdata};

    always @(posedge clk) begin
        sample_strobe <= 1'b0;
        bclk_d <= bclk;

        if (sample_strobe)
            activity_watchdog <= 24'd0;
        else if (activity_watchdog != 24'hffffff)
            activity_watchdog <= activity_watchdog + 1'b1;

        frame_active <= (activity_watchdog < 24'd4800000);

        if (bclk_rise) begin
            lrclk_at_bclk <= lrclk;

            if (lrclk != lrclk_at_bclk) begin
                // I2S toggles LRCLK one BCLK before the next channel MSB.
                bit_count <= 6'd0;
                shift_reg <= {MIC_BITS{1'b0}};
            end else begin
                shift_reg <= shifted_word;

                if (bit_count < MIC_BITS) begin
                    bit_count <= bit_count + 1'b1;

                    if (bit_count == MIC_BITS-1) begin
                        if (!lrclk) begin
                            // LRCLK low: left slot.
                            sample_l <= shifted_word[MIC_BITS-1 -: SAMPLE_BITS];
                        end else begin
                            // LRCLK high: right slot.
                            sample_r <= shifted_word[MIC_BITS-1 -: SAMPLE_BITS];
                            sample_strobe <= 1'b1;
                        end
                    end
                end

            end
        end
    end
endmodule

 module audio_clock_recovery #(
     parameter integer FIFO_DEPTH = 16,
     parameter integer FIFO_ADDR_BITS = 4,
     parameter signed [31:0] RATE_STEP = 32'sd16,
     parameter signed [31:0] RATE_LIMIT = 32'sd1048576
 )(
     input  wire clk,
     input  wire reset,
     input  wire sample_strobe,
     input  wire signed [15:0] sample_l_in,
     input  wire signed [15:0] sample_r_in,
     input  wire sample_req,
     output reg  signed [15:0] sample_l_out = 0,
     output reg  signed [15:0] sample_r_out = 0,
     output reg  signed [31:0] rate_adjust = 0,
     output reg  ready = 0,
     output reg  [FIFO_ADDR_BITS:0] level = 0
 );
     localparam integer TARGET_LEVEL = FIFO_DEPTH / 2;

     reg [31:0] fifo [0:FIFO_DEPTH-1];
     reg [FIFO_ADDR_BITS-1:0] write_ptr = 0;
     reg [FIFO_ADDR_BITS-1:0] read_ptr = 0;

     wire push = sample_strobe && (level < FIFO_DEPTH);
     wire pop = sample_req && ready && (level != 0);

     always @(posedge clk) begin
         if (reset) begin
             write_ptr <= 0;
             read_ptr <= 0;
             level <= 0;
             ready <= 0;
             rate_adjust <= 0;
             sample_l_out <= 0;
             sample_r_out <= 0;
         end else begin
             if (push) begin
                 fifo[write_ptr] <= {sample_l_in, sample_r_in};
                 write_ptr <= write_ptr + 1'b1;
             end

             if (pop) begin
                 sample_l_out <= fifo[read_ptr][31:16];
                 sample_r_out <= fifo[read_ptr][15:0];
                 read_ptr <= read_ptr + 1'b1;
             end

             case ({push, pop})
                 2'b10: level <= level + 1'b1;
                 2'b01: level <= level - 1'b1;
                 default: level <= level;
             endcase

             if (!ready) begin
                 rate_adjust <= 0;
                 if (level >= TARGET_LEVEL)
                     ready <= 1'b1;
             end else if (level == 0) begin
                 ready <= 1'b0;
                 rate_adjust <= 0;
             end else if (sample_req) begin
                 if ((level > TARGET_LEVEL) && (rate_adjust < RATE_LIMIT))
                     rate_adjust <= rate_adjust + RATE_STEP;
                 else if ((level < TARGET_LEVEL) && (rate_adjust > -RATE_LIMIT))
                     rate_adjust <= rate_adjust - RATE_STEP;
             end
         end
     end
 endmodule

module pll_96m (
    input  wire clk_12m,
    output wire clk_96m,
    output wire pll_lock
);
    SB_PLL40_PAD #(
         .FEEDBACK_PATH("SIMPLE"),
         .DIVR(4'b0000),
         .DIVF(7'b0111111),
         .DIVQ(3'b100),
         .FILTER_RANGE(3'b001)
     ) pll_i (
        .PACKAGEPIN(clk_12m),
         .PLLOUTCORE(clk_96m),
         .RESETB(1'b1),
         .BYPASS(1'b0),
         .LOCK(pll_lock)
     );
 endmodule


module top #(
    parameter integer AMP_LEVEL = 4
)(
    input wire i_clk,
    output wire HCMS_DATA_O,
    output wire HCMS_CLOCK_O,
    output wire HCMS_REGSEL_O,
    output wire HCMS_NCS_O,
    output wire HCMS_RESET_O,

    input  wire MIC_SD_IN,
    output wire MCLK,
    output wire LRCLK,
    output wire SDATA,
    output wire BLCK,
    output wire MIC_BCLK,
    output wire MIC_LRCLK,
    output wire LEDR_N,
    output wire LEDG_N,
);

wire clk_sys;
wire pll_lock;
reg [1:0] pll_lock_sync = 2'b00;

wire signed [15:0] sample_l;
wire signed [15:0] sample_r;
wire sample_strobe;
wire mic_active;

wire sample_req;
wire system_ready = pll_lock_sync[1];
wire audio_valid = system_ready && mic_active;

reg signed [15:0] mic_left_buffer = 16'sd0;
reg signed [15:0] mic_right_buffer = 16'sd0;
localparam integer AMP_SHIFT =
    (AMP_LEVEL == 1) ? 0 :
    (AMP_LEVEL == 2) ? 1 :
    (AMP_LEVEL == 4) ? 2 :
    (AMP_LEVEL == 8) ? 3 : 0;
wire signed [18:0] mic_scaled =
    $signed({{3{sample_l[15]}}, sample_l}) <<< AMP_SHIFT;
wire signed [15:0] mic_mono_gain =
    (mic_scaled > 19'sd32767) ? 16'sh7fff :
    (mic_scaled < -19'sd32768) ? 16'sh8000 :
    mic_scaled[15:0];

reg [23:0] window_counter = 24'd0;
reg [13:0] frame_counter = 14'd0;
reg [13:0] display_value = 14'd0;

reg [2:0] hcms_divider = 3'd0;
reg hcms_clk = 1'b0;

pll_96m pll (
    .clk_12m(i_clk),
    .clk_96m(clk_sys),
    .pll_lock(pll_lock)
);

always @(posedge clk_sys) begin
    pll_lock_sync <= {pll_lock_sync[0], pll_lock};

    if (hcms_divider == 3'd3) begin
        hcms_divider <= 3'd0;
        hcms_clk <= ~hcms_clk;
    end else begin
        hcms_divider <= hcms_divider + 1'b1;
    end

    if (sample_strobe) begin
        mic_left_buffer <= mic_mono_gain;
        mic_right_buffer <= mic_mono_gain;

        if (frame_counter != 14'd9999)
            frame_counter <= frame_counter + 1'b1;
    end

    if (window_counter == 24'd9599999) begin
        window_counter <= 24'd0;
        display_value <= frame_counter;
        frame_counter <= 14'd0;
    end else begin
        window_counter <= window_counter + 1'b1;
    end

end

i2s_mic_rx rx (
    .clk(clk_sys),
    .bclk(BLCK),
    .lrclk(LRCLK),
    .mic_sdata(MIC_SD_IN),
    .sample_l(sample_l),
    .sample_r(sample_r),
    .sample_strobe(sample_strobe),
    .frame_active(mic_active)
);

assign MCLK = 1'b0;

i2s_tx i2s (
    .clk(clk_sys),
    .sample_l(mic_left_buffer),
    .sample_r(mic_right_buffer),
    .rate_adjust(32'sd0),
    .sample_req(sample_req),
    .bclk(BLCK),
    .lrclk(LRCLK),
    .sdata(SDATA)
);

assign MIC_BCLK = BLCK;
assign MIC_LRCLK = LRCLK;

assign LEDG_N = ~audio_valid;
assign LEDR_N = ~(system_ready && !audio_valid);

hcms29xx_integer_display u_display (
    .i_clk(hcms_clk),
    .i_value(display_value),
    .i_pwm(4'b1101),
    .i_current(2'b00),
    .i_sleep(1'b1),
    .o_hcms_data(HCMS_DATA_O),
    .o_hcms_clock(HCMS_CLOCK_O),
    .o_hcms_regsel(HCMS_REGSEL_O),
    .o_hcms_ncs(HCMS_NCS_O),
    .o_hcms_reset(HCMS_RESET_O)
);

endmodule
