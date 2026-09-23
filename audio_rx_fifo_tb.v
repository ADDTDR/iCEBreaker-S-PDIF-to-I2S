`timescale 1ns/1ps

module audio_rx_fifo_tb;
    reg audio_clk = 0;
    reg wb_clk = 0;
    reg reset = 1;
    reg sample_strobe = 0;
    reg signed [15:0] sample_l = 0;
    reg signed [15:0] sample_r = 0;
    reg [31:0] wb_address = 0;
    reg [31:0] wb_write_data = 0;
    reg [3:0] wb_select = 4'b1111;
    reg wb_write_enable = 0;
    reg wb_cycle = 0;
    reg wb_strobe = 0;
    wire [31:0] wb_read_data;
    wire wb_ack;
    wire wb_error;
    wire [31:0] scratch;

    wishbone_audio_rx dut (
        .i_audio_clk(audio_clk),
        .i_audio_reset(reset),
        .i_sample_strobe(sample_strobe),
        .i_sample_l(sample_l),
        .i_sample_r(sample_r),
        .i_wb_clk(wb_clk),
        .i_wb_reset(reset),
        .i_wb_adr(wb_address),
        .i_wb_dat(wb_write_data),
        .i_wb_sel(wb_select),
        .i_wb_we(wb_write_enable),
        .i_wb_cyc(wb_cycle),
        .i_wb_stb(wb_strobe),
        .o_wb_dat(wb_read_data),
        .o_wb_ack(wb_ack),
        .o_wb_err(wb_error),
        .o_scratch(scratch)
    );

    always #3 audio_clk = ~audio_clk;
    always #5 wb_clk = ~wb_clk;

    task push_sample;
        input signed [15:0] left;
        input signed [15:0] right;
        begin
            @(negedge audio_clk);
            sample_l = left;
            sample_r = right;
            sample_strobe = 1'b1;
            @(negedge audio_clk);
            sample_strobe = 1'b0;
        end
    endtask

    task read_check;
        input [31:0] address;
        input [31:0] expected;
        begin
            @(negedge wb_clk);
            wb_address = address;
            wb_cycle = 1'b1;
            wb_strobe = 1'b1;
            while (!wb_ack) @(posedge wb_clk);
            #1;
            if (wb_error || wb_read_data !== expected) begin
                $display("read mismatch at %h: got %h expected %h", address, wb_read_data, expected);
                $fatal(1);
            end
            @(negedge wb_clk);
            wb_cycle = 1'b0;
            wb_strobe = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge wb_clk);
        reset = 0;

        read_check(32'h10000000, 32'h49434542);
        read_check(32'h10000004, 32'h00000000);
        push_sample(16'sh1234, -16'sd2);
        push_sample(-16'sd3, 16'sh5678);
        repeat (4) @(posedge wb_clk);
        read_check(32'h10000004, 32'h00000001);
        read_check(32'h10000008, 32'h1234fffe);
        read_check(32'h10000008, 32'hfffd5678);
        repeat (2) @(posedge wb_clk);
        read_check(32'h10000004, 32'h00000000);

        $display("audio_rx_fifo_tb PASS");
        $finish;
    end
endmodule