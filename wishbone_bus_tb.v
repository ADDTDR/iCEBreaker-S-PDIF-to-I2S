`timescale 1ns/1ps

module wishbone_bus_tb;
    reg clk = 0;
    reg reset = 1;
    reg [31:0] master_address = 0;
    reg [31:0] master_write_data = 0;
    reg [3:0] master_select = 0;
    reg master_write_enable = 0;
    reg master_cycle = 0;
    reg master_strobe = 0;
    wire [31:0] master_read_data;
    wire master_ack;
    wire master_error;

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

    wishbone_interconnect #(
        .SLAVE_ENABLE(4'b0001)
    ) dut_interconnect (
        .i_m_adr(master_address),
        .i_m_dat(master_write_data),
        .i_m_sel(master_select),
        .i_m_we(master_write_enable),
        .i_m_cyc(master_cycle),
        .i_m_stb(master_strobe),
        .o_m_dat(master_read_data),
        .o_m_ack(master_ack),
        .o_m_err(master_error),
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

    wishbone_scratch scratch (
        .i_clk(clk),
        .i_reset(reset),
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

    always #5 clk = ~clk;

    task bus_write;
        input [31:0] address;
        input [31:0] data;
        input [3:0] select;
        begin
            @(negedge clk);
            master_address = address;
            master_write_data = data;
            master_select = select;
            master_write_enable = 1'b1;
            master_cycle = 1'b1;
            master_strobe = 1'b1;
            #1;
            if (!master_ack || master_error) begin
                $display("write did not complete at %h", address);
                $fatal(1);
            end
            @(negedge clk);
            master_cycle = 1'b0;
            master_strobe = 1'b0;
            master_write_enable = 1'b0;
        end
    endtask

    task bus_read_check;
        input [31:0] address;
        input [31:0] expected;
        begin
            @(negedge clk);
            master_address = address;
            master_select = 4'b1111;
            master_cycle = 1'b1;
            master_strobe = 1'b1;
            #1;
            if (!master_ack || master_error || (master_read_data !== expected)) begin
                $display("read mismatch at %h: got %h expected %h ack=%b err=%b",
                         address, master_read_data, expected, master_ack, master_error);
                $fatal(1);
            end
            @(negedge clk);
            master_cycle = 1'b0;
            master_strobe = 1'b0;
        end
    endtask

    task bus_error_check;
        input [31:0] address;
        begin
            @(negedge clk);
            master_address = address;
            master_cycle = 1'b1;
            master_strobe = 1'b1;
            #1;
            if (!master_ack || !master_error || (slave_strobe != 4'b0000)) begin
                $display("unmapped access did not return an isolated error at %h", address);
                $fatal(1);
            end
            @(negedge clk);
            master_cycle = 1'b0;
            master_strobe = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset = 0;

        bus_read_check(32'h10000000, 32'h49434542);
        bus_read_check(32'h10000004, 32'h00000000);
        bus_write(32'h10000004, 32'h12345678, 4'b1111);
        bus_read_check(32'h10000004, 32'h12345678);
        bus_write(32'h10000004, 32'hAABBCCDD, 4'b0101);
        bus_read_check(32'h10000004, 32'h12BB56DD);
        bus_error_check(32'h10001000);
        bus_error_check(32'h20000000);

        $display("wishbone_bus_tb PASS");
        $finish;
    end
endmodule