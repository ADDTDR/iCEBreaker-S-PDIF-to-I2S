`timescale 1ns/1ps

module audio_tx_fifo_tb;
    reg wb_clk = 0;
    reg audio_clk = 0;
    reg reset = 1;
    reg [31:0] wb_address = 0;
    reg [31:0] wb_write_data = 0;
    reg [3:0] wb_select = 4'b1111;
    reg wb_write_enable = 0;
    reg wb_cycle = 0;
    reg wb_strobe = 0;
    reg sample_req = 0;
    wire [31:0] wb_read_data;
    wire wb_ack;
    wire wb_error;
    wire signed [15:0] sample_l;
    wire signed [15:0] sample_r;
    wire signed [31:0] rate_adjust;
    wire ready;
    integer sample_index;

    wishbone_audio_tx dut (
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
        .i_audio_clk(audio_clk),
        .i_audio_reset(reset),
        .i_sample_req(sample_req),
        .o_sample_l(sample_l),
        .o_sample_r(sample_r),
        .o_rate_adjust(rate_adjust),
        .o_ready(ready)
    );

    always #5 wb_clk = ~wb_clk;
    always #3 audio_clk = ~audio_clk;

    task write_sample;
        input [31:0] sample;
        begin
            @(negedge wb_clk);
            wb_address = 32'h10001008;
            wb_write_data = sample;
            wb_write_enable = 1'b1;
            wb_cycle = 1'b1;
            wb_strobe = 1'b1;
            while (!wb_ack) @(posedge wb_clk);
            @(negedge wb_clk);
            wb_write_enable = 1'b0;
            wb_cycle = 1'b0;
            wb_strobe = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge wb_clk);
        reset = 0;

        for (sample_index = 0; sample_index < 8; sample_index = sample_index + 1)
            write_sample(32'h12003400 + (sample_index << 16) + sample_index);

        while (!ready) @(posedge audio_clk);
        @(negedge audio_clk);
        sample_req = 1'b1;
        @(negedge audio_clk);
        sample_req = 1'b0;
        repeat (3) @(posedge audio_clk);

        if (sample_l !== 16'h1200 || sample_r !== 16'h3400) begin
            $display("TX sample mismatch: got %h %h expected 1200 3400", sample_l, sample_r);
            $fatal(1);
        end

        $display("audio_tx_fifo_tb PASS");
        $finish;
    end
endmodule