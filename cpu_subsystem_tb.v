`timescale 1ns/1ps

module cpu_subsystem_tb;
    reg clk = 0;
    reg audio_clk = 0;
    reg reset = 1;
    reg sample_strobe = 0;
    wire booted;
    wire trap;
    integer cycles;

    cpu_subsystem dut (
        .i_clk(clk),
        .i_reset(reset),
        .i_audio_clk(audio_clk),
        .i_audio_reset(reset),
        .i_sample_strobe(sample_strobe),
        .i_sample_l(16'sd0),
        .i_sample_r(16'sd0),
        .o_booted(booted),
        .o_trap(trap)
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

        $display("cpu_subsystem_tb PASS in %0d cycles", cycles);
        $finish;
    end
endmodule