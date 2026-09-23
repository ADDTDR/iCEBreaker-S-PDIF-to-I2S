`timescale 1ns/1ps

module audio_spectrum_bands_tb;
    reg clk = 0;
    reg strobe = 0;
    reg signed [15:0] sample = 0;
    wire [29:0] bars;

    reg signed [23:0] lp_model [0:4];
    reg [15:0] env_model [0:4];
    reg [29:0] expected_bars = 0;
    integer index;

    audio_spectrum_bands dut (
        .i_clk(clk),
        .i_strobe(strobe),
        .i_sample(sample),
        .o_bars(bars)
    );

    always #5 clk = ~clk;

    function [2:0] level_of;
        input [15:0] magnitude;
        begin
            if (magnitude[15:14] != 2'b00) level_of = 3'd7;
            else if (magnitude[13]) level_of = 3'd6;
            else if (magnitude[12]) level_of = 3'd5;
            else if (magnitude[11]) level_of = 3'd4;
            else if (magnitude[10]) level_of = 3'd3;
            else if (magnitude[9]) level_of = 3'd2;
            else if (magnitude[8]) level_of = 3'd1;
            else level_of = 3'd0;
        end
    endfunction

    task apply_sample;
        input signed [15:0] next_sample;
        reg signed [23:0] previous;
        reg signed [23:0] current;
        reg signed [23:0] difference;
        reg signed [23:0] band_value;
        reg [23:0] band_abs;
        reg [15:0] magnitude;
        reg [15:0] envelope_next;
        integer band;
        begin
            previous = {next_sample, 8'd0};
            for (band = 0; band < 5; band = band + 1) begin
                current = lp_model[band];
                difference = previous - current;
                band_value = (band == 4) ? current : difference;
                band_abs = band_value[23] ? (~band_value + 1'b1) : band_value;
                magnitude = band_abs[23:8];
                envelope_next = (magnitude > env_model[band]) ? magnitude
                              : (env_model[band] - (env_model[band] >> 6));
                lp_model[band] = current + (difference >>> (2 * band + 1));
                env_model[band] = envelope_next;
                expected_bars[band*6 +: 3] = level_of(envelope_next);
                expected_bars[band*6+3 +: 3] = level_of(envelope_next);
                previous = current;
            end

            @(negedge clk);
            sample = next_sample;
            strobe = 1'b1;
            @(negedge clk);
            strobe = 1'b0;
            repeat (21) @(posedge clk);
            #1;

            if (bars !== expected_bars) begin
                $display("bars mismatch for sample %0d: got %h expected %h", next_sample, bars, expected_bars);
                $fatal(1);
            end
        end
    endtask

    initial begin
        for (index = 0; index < 5; index = index + 1) begin
            lp_model[index] = 0;
            env_model[index] = 0;
        end

        apply_sample(16'sd0);
        apply_sample(16'sd12000);
        apply_sample(-16'sd8000);
        apply_sample(16'sd32767);
        apply_sample(-16'sd32767);
        repeat (80) apply_sample(16'sd0);

        $display("audio_spectrum_bands_tb PASS");
        $finish;
    end
endmodule