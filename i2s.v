
 module tone_rom #(
     parameter INIT_FILE = "mem_init.txt"
 )(
     input wire clk,
     input wire [9:0] addr,
     output reg signed [15:0] data
 );
     reg signed [15:0] mem [0:1023];

     always @(posedge clk) begin
         data <= mem[addr];
     end

     initial if (INIT_FILE) begin
         $readmemh(INIT_FILE, mem);
     end
 endmodule


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


 module spdif_rx (
     input  wire clk,
     input  wire spdif_in,
     output reg  signed [15:0] sample_l = 0,
     output reg  signed [15:0] sample_r = 0,
     output reg  sample_strobe = 0,
     output reg  active = 0,
     output reg  locked = 0
 );

     // Synchronizer & Noise Filter Signals
     reg [2:0] spdif_sync = 3'b000;
     reg spdif_f = 1'b0;
     reg spdif_ff = 1'b0;
    
     // Time/Edge Tracking Registers
     reg [6:0] edge_ticks = 0;
     reg [6:0] quiet_ticks = 0;

     // S/PDIF Protocol State Engine
     reg pending_short = 0;
     reg [5:0] bit_count = 0;
     reg [27:0] subframe_bits = 0;
     reg channel_sel = 0;
     reg channel_valid = 0;
     reg in_preamble = 0;
     reg [1:0] preamble_step = 0;
     reg preamble_right = 0;

     reg [5:0] good_subframes = 0;

     // 96 MHz input sampling for 88.2/96 kHz S/PDIF streams.
     localparam [6:0] SHORT_MAX = 7'd11;
     localparam [6:0] LONG_MAX  = 7'd20;
     localparam [6:0] SYNC_MIN  = 7'd21;
     localparam [6:0] IDLE_MAX  = 7'd55;

     // 3-Input Majority Voter Filter for raw signal glitch reduction
     wire spdif_maj = (spdif_sync[2] & spdif_sync[1]) |
                      (spdif_sync[2] & spdif_sync[0]) |
                      (spdif_sync[1] & spdif_sync[0]);

     // OPTIMIZATION: Hardcoded to Mode 0 (Direct MSB-first subframe mapping)
     wire [15:0] w_sel = subframe_bits[23:8];

     always @(posedge clk) begin
         sample_strobe  <= 1'b0;
         spdif_sync     <= {spdif_sync[1:0], spdif_in};
         spdif_ff       <= spdif_f;
         spdif_f        <= spdif_maj;

         // Keep counting ticks until they saturate at maximum width
         if (edge_ticks != 7'h7f)
             edge_ticks <= edge_ticks + 1'b1;
         if (quiet_ticks != 7'h7f)
             quiet_ticks <= quiet_ticks + 1'b1;

         active <= (quiet_ticks < IDLE_MAX);

         // Reset state and drop lock immediately if incoming transitions freeze
         if (quiet_ticks >= IDLE_MAX) begin
             locked         <= 1'b0;
             pending_short  <= 1'b0;
             bit_count      <= 0;
             good_subframes <= 0;
             channel_sel    <= 1'b0;
             channel_valid  <= 1'b0;
             in_preamble    <= 1'b0;
             preamble_step  <= 0;
         end

         // Evaluate logic solely on valid filtered S/PDIF transitions
         if (spdif_f ^ spdif_ff) begin
             quiet_ticks <= 0;

             if (in_preamble) begin
                 // Preamble parsing window: B=3,1,1,3; M=3,3,1,1; W=3,2,1,2.
                 // The second interval isolates W (right channel) from B/M (left channel).
                 if (preamble_step == 2'd1)
                     preamble_right <= (edge_ticks > SHORT_MAX) && (edge_ticks < SYNC_MIN);

                 if (preamble_step == 2'd3) begin
                     channel_sel    <= preamble_right;
                     channel_valid  <= 1'b1;
                     in_preamble    <= 1'b0;
                     preamble_step  <= 0;
                     bit_count      <= 0;
                     pending_short  <= 1'b0;
                 end else begin
                     preamble_step  <= preamble_step + 1'b1;
                 end
             end else if (edge_ticks >= SYNC_MIN) begin
                 // A 3T sync interval identifies the start of an S/PDIF preamble.
                 // Commit the compiled payload registers before parsing the next preamble header.
                 if (channel_valid && (bit_count >= 6'd24)) begin
                     if (channel_sel) begin
                         sample_r      <= w_sel;
                         sample_strobe <= 1'b1;
                     end else begin
                         sample_l      <= w_sel;
                     end

                     if (good_subframes != 6'h3f)
                         good_subframes <= good_subframes + 1'b1;
                 end else if (channel_valid) begin
                     good_subframes <= 0;
                     locked         <= 1'b0;
                 end

                 if (good_subframes >= 6'd4)
                     locked <= 1'b1;

                 in_preamble   <= 1'b1;
                 preamble_step <= 2'd1;
                 bit_count     <= 0;
                 pending_short <= 1'b0;
             end else begin
                 // Decode incoming data based on measured cell periods
                 if (edge_ticks <= SHORT_MAX) begin
                     if (!pending_short) begin
                         pending_short <= 1'b1; // First half of BMC logic '1' cell
                     end else begin
                         pending_short <= 1'b0; // Second half complete
                         if (bit_count < 6'd28) begin
                             subframe_bits[bit_count] <= 1'b1;
                             bit_count <= bit_count + 1'b1;
                         end
                     end
                 end else if (edge_ticks <= LONG_MAX) begin
                     if (pending_short) begin
                         // Phase tracking fault detected: reset window alignment
                         pending_short  <= 1'b0;
                         bit_count      <= 0;
                         good_subframes <= 0;
                         locked         <= 1'b0;
                     end else begin
                         if (bit_count < 6'd28) begin
                             subframe_bits[bit_count] <= 1'b0;
                             bit_count <= bit_count + 1'b1;
                         end
                     end
                 end else begin
                     // Ambiguous interval width: bypass data bit, wait for clean sync block
                     pending_short <= 1'b0;
                 end
             end

             edge_ticks <= 0; // Reset period counter for the next edge interval
         end
     end
 endmodule




module top (
    input wire i_clk,
    output wire HCMS_DATA_O,
    output wire HCMS_CLOCK_O,
    output wire HCMS_REGSEL_O,
    output wire HCMS_NCS_O,
    output wire HCMS_RESET_O,

    input  wire SPDIF_IN,
    output wire MCLK,
    output wire LRCLK,
    output wire SDATA,
    output wire BLCK,
    output wire SPDIF_DBG,
    output wire LEDR_N,
    output wire LEDG_N,
);

wire clk_sys;
wire pll_lock;
reg [1:0] pll_lock_sync = 2'b00;
reg [23:0] rx_watchdog = 24'hffffff;
reg [21:0] dbg_hold = 22'd0;

wire signed [15:0] sample_l;
wire signed [15:0] sample_r;
wire sample_strobe;
wire spdif_active;
wire spdif_locked;

reg [9:0] sample_addr = 10'd0;
reg signed [15:0] sample_fallback = 16'sd0;
wire signed [15:0] rom_sample;

wire sample_req;
wire signed [15:0] recovered_sample_l;
wire signed [15:0] recovered_sample_r;
wire signed [31:0] rate_adjust;
wire recovery_ready;
wire [4:0] fifo_level;
wire receiver_timed_out = rx_watchdog >= 24'd4800000;
wire system_ready = pll_lock_sync[1];
wire audio_valid = system_ready && spdif_active && !receiver_timed_out && recovery_ready;

reg [2:0] hcms_divider = 3'd0;
reg hcms_clk = 1'b0;
reg [4:0] fifo_level_meta = 5'd0;
reg [5:0] fifo_level_display = 6'd0;

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

    if (sample_strobe)
        rx_watchdog <= 24'd0;
    else if (rx_watchdog != 24'hffffff)
        rx_watchdog <= rx_watchdog + 1'b1;

    if (sample_strobe)
        dbg_hold <= 22'd2000000;
    else if (dbg_hold != 0)
        dbg_hold <= dbg_hold - 1'b1;

    if (sample_req) begin
        sample_fallback <= rom_sample;
        sample_addr <= sample_addr + 1'b1;
    end
end

always @(posedge hcms_clk) begin
    fifo_level_meta <= fifo_level;
    fifo_level_display <= fifo_level_meta;
end

tone_rom #(
    .INIT_FILE("mem_init.txt")
) rom (
    .clk(clk_sys),
    .addr(sample_addr),
    .data(rom_sample)
);

spdif_rx rx (
    .clk(clk_sys),
    .spdif_in(SPDIF_IN),
    .sample_l(sample_l),
    .sample_r(sample_r),
    .sample_strobe(sample_strobe),
    .active(spdif_active),
    .locked(spdif_locked)
);

audio_clock_recovery recovery (
    .clk(clk_sys),
    .reset(!system_ready || receiver_timed_out),
    .sample_strobe(sample_strobe),
    .sample_l_in(sample_l),
    .sample_r_in(sample_r),
    .sample_req(sample_req),
    .sample_l_out(recovered_sample_l),
    .sample_r_out(recovered_sample_r),
    .rate_adjust(rate_adjust),
    .ready(recovery_ready),
    .level(fifo_level)
);

assign MCLK = 1'b0;

i2s_tx i2s (
    .clk(clk_sys),
    .sample_l(audio_valid ? recovered_sample_l : sample_fallback),
    .sample_r(audio_valid ? recovered_sample_r : sample_fallback),
    .rate_adjust(rate_adjust),
    .sample_req(sample_req),
    .bclk(BLCK),
    .lrclk(LRCLK),
    .sdata(SDATA)
);

assign SPDIF_DBG = spdif_locked | (dbg_hold != 0);
assign LEDG_N = ~audio_valid;
assign LEDR_N = ~(spdif_active && !audio_valid);

hcms29xx_integer_display u_display (
    .i_clk(hcms_clk),
    .i_value({9'd0, fifo_level_display}),
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
