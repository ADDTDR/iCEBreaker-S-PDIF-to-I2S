`timescale 1ns/1ps

module cpu_subsystem_tb;
    reg clk = 0;
    reg reset = 1;
    wire booted;
    wire trap;
    integer cycles;

    cpu_subsystem dut (
        .i_clk(clk),
        .i_reset(reset),
        .o_booted(booted),
        .o_trap(trap)
    );

    always #5 clk = ~clk;

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