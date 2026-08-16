`timescale 1ns/1ps

module clock_recovery_tb;
    reg clk = 0;
    reg reset = 1;
    reg sample_strobe = 0;
    reg signed [15:0] sample_l_in = 0;
    reg signed [15:0] sample_r_in = 0;
    reg sample_req = 0;

    wire signed [15:0] sample_l_out;
    wire signed [15:0] sample_r_out;
    wire signed [31:0] rate_adjust;
    wire ready;
    wire [4:0] level;

    integer source_count = 0;
    integer output_count = 0;
    integer source_limit = 98;
    integer output_limit = 99;

    audio_clock_recovery #(
        .RATE_STEP(32'sd256)
    ) dut (
        .clk(clk),
        .reset(reset),
        .sample_strobe(sample_strobe),
        .sample_l_in(sample_l_in),
        .sample_r_in(sample_r_in),
        .sample_req(sample_req),
        .sample_l_out(sample_l_out),
        .sample_r_out(sample_r_out),
        .rate_adjust(rate_adjust),
        .ready(ready),
        .level(level)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        sample_strobe <= 0;
        sample_req <= 0;

        if (reset) begin
            source_count <= 0;
            output_count <= 0;
        end else begin
            if (source_count == source_limit) begin
                source_count <= 0;
                sample_strobe <= 1;
                sample_l_in <= sample_l_in + 1'b1;
                sample_r_in <= sample_r_in - 1'b1;
            end else begin
                source_count <= source_count + 1;
            end

            if (output_count == output_limit) begin
                output_count <= 0;
                sample_req <= 1;
            end else begin
                output_count <= output_count + 1;
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        reset <= 0;
        repeat (12000) @(posedge clk);

        if (!ready) begin
            $display("clock recovery did not reach ready state");
            $fatal(1);
        end

        if (rate_adjust <= 0) begin
            $display("faster source did not increase output rate: %0d", rate_adjust);
            $fatal(1);
        end

        if ((level < 2) || (level > 14)) begin
            $display("FIFO level escaped recovery range: %0d", level);
            $fatal(1);
        end

        reset <= 1;
        source_limit <= 100;
        repeat (4) @(posedge clk);
        reset <= 0;
        repeat (12000) @(posedge clk);

        if (!ready) begin
            $display("clock recovery did not reacquire ready state");
            $fatal(1);
        end

        if (rate_adjust >= 0) begin
            $display("slower source did not decrease output rate: %0d", rate_adjust);
            $fatal(1);
        end

        $display("clock_recovery_tb PASS level=%0d adjust=%0d", level, rate_adjust);
        $finish;
    end
endmodule