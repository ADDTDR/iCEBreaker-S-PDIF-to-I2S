module cpu_firmware_memory #(
    parameter INIT_FILE = "firmware/firmware.hex"
) (
    input wire i_clk,
    input wire [31:0] i_wb_adr,
    input wire [31:0] i_wb_dat,
    input wire [3:0] i_wb_sel,
    input wire i_wb_we,
    input wire i_wb_cyc,
    input wire i_wb_stb,
    output reg [31:0] o_wb_dat = 0,
    output reg o_wb_ack = 0
);
    reg [31:0] memory [0:1023];
    wire request = i_wb_cyc && i_wb_stb;

    initial begin
        $readmemh(INIT_FILE, memory);
    end

    always @(posedge i_clk) begin
        o_wb_ack <= request;

        if (request) begin
            o_wb_dat <= memory[i_wb_adr[11:2]];
            if (i_wb_we) begin
                if (i_wb_sel[0]) memory[i_wb_adr[11:2]][7:0] <= i_wb_dat[7:0];
                if (i_wb_sel[1]) memory[i_wb_adr[11:2]][15:8] <= i_wb_dat[15:8];
                if (i_wb_sel[2]) memory[i_wb_adr[11:2]][23:16] <= i_wb_dat[23:16];
                if (i_wb_sel[3]) memory[i_wb_adr[11:2]][31:24] <= i_wb_dat[31:24];
            end
        end
    end
endmodule

module cpu_subsystem (
    input wire i_clk,
    input wire i_reset,
    input wire i_audio_clk,
    input wire i_audio_reset,
    input wire i_sample_strobe,
    input wire signed [15:0] i_sample_l,
    input wire signed [15:0] i_sample_r,
    output wire o_booted,
    output wire o_trap
);
    wire [31:0] master_address;
    wire [31:0] master_write_data;
    wire [31:0] master_read_data;
    wire [3:0] master_select;
    wire master_write_enable;
    wire master_strobe;
    wire master_cycle;
    wire master_ack;

    wire memory_selected = (master_address[31:12] == 20'd0);
    wire memory_cycle = master_cycle && memory_selected;
    wire memory_strobe = master_strobe && memory_selected;
    wire [31:0] memory_read_data;
    wire memory_ack;

    wire [31:0] peripheral_read_data;
    wire peripheral_ack;
    wire peripheral_error;
    wire [31:0] slave_address;
    wire [31:0] slave_write_data;
    wire [3:0] slave_select;
    wire slave_write_enable;
    wire [3:0] slave_cycle;
    wire [3:0] slave_strobe;
    wire [31:0] scratch_read_data;
    wire scratch_ack;
    wire scratch_error;
    wire [31:0] scratch_value;

    wire [127:0] slave_read_data = {96'd0, scratch_read_data};
    wire [3:0] slave_ack = {3'b000, scratch_ack};
    wire [3:0] slave_error = {3'b000, scratch_error};

    assign master_read_data = memory_selected ? memory_read_data : peripheral_read_data;
    assign master_ack = memory_selected ? memory_ack : peripheral_ack;
    assign o_booted = (scratch_value == 32'hb007c0de);

    picorv32_wb #(
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .ENABLE_REGS_16_31(0),
        .ENABLE_REGS_DUALPORT(0),
        .TWO_STAGE_SHIFT(0),
        .TWO_CYCLE_COMPARE(0),
        .TWO_CYCLE_ALU(0),
        .CATCH_MISALIGN(0),
        .CATCH_ILLINSN(0),
        .ENABLE_IRQ(0),
        .ENABLE_IRQ_QREGS(0),
        .ENABLE_IRQ_TIMER(0),
        .STACKADDR(32'h00001000)
    ) cpu (
        .wb_rst_i(i_reset),
        .wb_clk_i(i_clk),
        .trap(o_trap),
        .wbm_adr_o(master_address),
        .wbm_dat_o(master_write_data),
        .wbm_dat_i(master_read_data),
        .wbm_we_o(master_write_enable),
        .wbm_sel_o(master_select),
        .wbm_stb_o(master_strobe),
        .wbm_ack_i(master_ack),
        .wbm_cyc_o(master_cycle),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'd0),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),
        .irq(32'd0)
    );

    cpu_firmware_memory memory (
        .i_clk(i_clk),
        .i_wb_adr(master_address),
        .i_wb_dat(master_write_data),
        .i_wb_sel(master_select),
        .i_wb_we(master_write_enable),
        .i_wb_cyc(memory_cycle),
        .i_wb_stb(memory_strobe),
        .o_wb_dat(memory_read_data),
        .o_wb_ack(memory_ack)
    );

    wishbone_interconnect #(
        .SLAVE_ENABLE(4'b0001)
    ) peripheral_bus (
        .i_m_adr(master_address),
        .i_m_dat(master_write_data),
        .i_m_sel(master_select),
        .i_m_we(master_write_enable),
        .i_m_cyc(master_cycle && !memory_selected),
        .i_m_stb(master_strobe && !memory_selected),
        .o_m_dat(peripheral_read_data),
        .o_m_ack(peripheral_ack),
        .o_m_err(peripheral_error),
        .o_s_adr(slave_address),
        .o_s_dat(slave_write_data),
        .o_s_sel(slave_select),
        .o_s_we(slave_write_enable),
        .o_s_cyc(slave_cycle),
        .o_s_stb(slave_strobe),
        .i_s_dat(slave_read_data),
        .i_s_ack(slave_ack),
        .i_s_err(slave_error)
    );

    wishbone_audio_rx audio_rx (
        .i_audio_clk(i_audio_clk),
        .i_audio_reset(i_audio_reset),
        .i_sample_strobe(i_sample_strobe),
        .i_sample_l(i_sample_l),
        .i_sample_r(i_sample_r),
        .i_wb_clk(i_clk),
        .i_wb_reset(i_reset),
        .i_wb_adr(slave_address),
        .i_wb_dat(slave_write_data),
        .i_wb_sel(slave_select),
        .i_wb_we(slave_write_enable),
        .i_wb_cyc(slave_cycle[0]),
        .i_wb_stb(slave_strobe[0]),
        .o_wb_dat(scratch_read_data),
        .o_wb_ack(scratch_ack),
        .o_wb_err(scratch_error),
        .o_scratch(scratch_value)
    );
endmodule