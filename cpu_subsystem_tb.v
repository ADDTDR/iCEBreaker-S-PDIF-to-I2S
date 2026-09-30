`timescale 1ns/1ps

module cpu_subsystem_tb;
    reg clk = 0;
    reg audio_clk = 0;
    reg reset = 1;
    reg sample_strobe = 0;
    reg signed [15:0] sample_l = 0;
    reg signed [15:0] sample_r = 0;
    wire booted;
    wire trap;
    reg i2s_sample_req = 0;
    wire signed [15:0] i2s_sample_l;
    wire signed [15:0] i2s_sample_r;
    wire signed [31:0] i2s_rate_adjust;
    wire i2s_ready;
    wire signed [15:0] spectrum_sample_l;
    wire signed [15:0] spectrum_sample_r;
    wire spectrum_sample_strobe;
    integer cycles;

    cpu_subsystem dut (
        .i_clk(clk),
        .i_reset(reset),
        .i_audio_clk(audio_clk),
        .i_audio_reset(reset),
        .i_sample_strobe(sample_strobe),
        .i_sample_l(sample_l),
        .i_sample_r(sample_r),
        .o_booted(booted),
        .o_trap(trap),
        .i_i2s_sample_req(i2s_sample_req),
        .o_i2s_sample_l(i2s_sample_l),
        .o_i2s_sample_r(i2s_sample_r),
        .o_i2s_rate_adjust(i2s_rate_adjust),
        .o_i2s_ready(i2s_ready),
        .o_spectrum_sample_l(spectrum_sample_l),
        .o_spectrum_sample_r(spectrum_sample_r),
        .o_spectrum_sample_strobe(spectrum_sample_strobe)
    );

    always #5 clk = ~clk;
    always #3 audio_clk = ~audio_clk;

    initial begin
        repeat (4) @(posedge clk);
        reset = 0;

        for (cycles = 0; cycles < 5000 && !booted && !trap; cycles = cycles + 1)
            @(posedge clk);

        if (trap) begin
            $display("CPU trapped before firmware completed");
            $fatal(1);
        end

        if (!booted) begin
            $display("CPU firmware did not produce boot signature");
            $fatal(1);
        end

        @(negedge audio_clk);
        sample_l = 16'sh1234;
        sample_r = -16'sd2;
        sample_strobe = 1'b1;
        @(negedge audio_clk);
        sample_strobe = 1'b0;

        for (cycles = 0; cycles < 5000 && !spectrum_sample_strobe && !trap; cycles = cycles + 1)
            @(posedge audio_clk);

        if (!spectrum_sample_strobe || spectrum_sample_l !== 16'sh1234 ||
            spectrum_sample_r !== -16'sd2) begin
            $display("CPU did not forward the received sample to the spectrum analyzer");
            $fatal(1);
        end

        for (cycles = 1; cycles < 8; cycles = cycles + 1) begin
            @(negedge audio_clk);
            sample_l = 16'sh1234 + cycles;
            sample_r = -16'sd2 - cycles;
            sample_strobe = 1'b1;
            @(negedge audio_clk);
            sample_strobe = 1'b0;
        end

        for (cycles = 0; cycles < 10000 && !i2s_ready && !trap; cycles = cycles + 1)
            @(posedge audio_clk);

        if (!i2s_ready || trap) begin
            $display("CPU did not fill the I2S transmit FIFO");
            $fatal(1);
        end

        @(negedge audio_clk);
        i2s_sample_req = 1'b1;
        @(negedge audio_clk);
        i2s_sample_req = 1'b0;
        repeat (3) @(posedge audio_clk);

        if (i2s_sample_l !== 16'sh1234 || i2s_sample_r !== -16'sd2) begin
            $display("CPU did not forward the received sample to I2S");
            $fatal(1);
        end

        $display("cpu_subsystem_tb PASS");
        $finish;
    end
endmodule