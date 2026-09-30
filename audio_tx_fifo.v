module wishbone_audio_tx #(
    parameter integer ADDRESS_BITS = 4,
    parameter signed [31:0] RATE_STEP = 32'sd16,
    parameter signed [31:0] RATE_LIMIT = 32'sd1048576
) (
    input wire i_wb_clk,
    input wire i_wb_reset,
    input wire [31:0] i_wb_adr,
    input wire [31:0] i_wb_dat,
    input wire [3:0] i_wb_sel,
    input wire i_wb_we,
    input wire i_wb_cyc,
    input wire i_wb_stb,
    output reg [31:0] o_wb_dat = 0,
    output reg o_wb_ack = 0,
    output wire o_wb_err,

    input wire i_audio_clk,
    input wire i_audio_reset,
    input wire i_sample_req,
    output reg signed [15:0] o_sample_l = 0,
    output reg signed [15:0] o_sample_r = 0,
    output reg signed [31:0] o_rate_adjust = 0,
    output reg o_ready = 0
);
    localparam [31:0] DEVICE_ID = 32'h49325354;
    localparam integer POINTER_BITS = ADDRESS_BITS + 1;
    localparam integer TARGET_LEVEL = (1 << ADDRESS_BITS) / 2;

    reg [POINTER_BITS-1:0] write_binary = 0;
    reg [POINTER_BITS-1:0] write_gray = 0;
    reg [POINTER_BITS-1:0] read_binary = 0;
    reg [POINTER_BITS-1:0] read_gray = 0;
    reg [POINTER_BITS-1:0] read_gray_wb_meta = 0;
    reg [POINTER_BITS-1:0] read_gray_wb = 0;
    reg [POINTER_BITS-1:0] write_gray_audio_meta = 0;
    reg [POINTER_BITS-1:0] write_gray_audio = 0;
    reg full = 0;
    reg underflow = 0;
    reg underflow_wb_meta = 0;
    reg underflow_wb = 0;
    reg read_pending = 0;

    wire request = i_wb_cyc && i_wb_stb;
    wire data_write = request && !o_wb_ack && i_wb_we &&
                      (i_wb_adr[3:2] == 2'd2) && !full;
    wire [POINTER_BITS-1:0] write_binary_next = write_binary + data_write;
    wire [POINTER_BITS-1:0] write_gray_next = (write_binary_next >> 1) ^ write_binary_next;
    wire full_next = write_gray_next == {
        ~read_gray_wb[POINTER_BITS-1:POINTER_BITS-2],
        read_gray_wb[POINTER_BITS-3:0]
    };
    wire empty = read_gray == write_gray_audio;
    wire pop = i_sample_req && o_ready && !empty && !read_pending;
    wire [POINTER_BITS-1:0] read_binary_next = read_binary + 1'b1;
    wire [POINTER_BITS-1:0] read_gray_next = (read_binary_next >> 1) ^ read_binary_next;
    wire [POINTER_BITS-1:0] write_binary_audio;
    wire [POINTER_BITS-1:0] audio_level = write_binary_audio - read_binary;
    wire [7:0] ram_write_address = {{(8-ADDRESS_BITS){1'b0}}, write_binary[ADDRESS_BITS-1:0]};
    wire [7:0] ram_read_address = {{(8-ADDRESS_BITS){1'b0}}, read_binary[ADDRESS_BITS-1:0]};
    wire [15:0] ram_read_l;
    wire [15:0] ram_read_r;

    function [POINTER_BITS-1:0] gray_to_binary;
        input [POINTER_BITS-1:0] gray;
        integer bit_index;
        begin
            gray_to_binary[POINTER_BITS-1] = gray[POINTER_BITS-1];
            for (bit_index = POINTER_BITS - 2; bit_index >= 0; bit_index = bit_index - 1)
                gray_to_binary[bit_index] = gray_to_binary[bit_index + 1] ^ gray[bit_index];
        end
    endfunction

    assign write_binary_audio = gray_to_binary(write_gray_audio);
    assign o_wb_err = 1'b0;

    SB_RAM40_4K #(
        .READ_MODE(0),
        .WRITE_MODE(0)
    ) sample_memory_l (
        .RDATA(ram_read_l),
        .RCLK(i_audio_clk),
        .RCLKE(pop),
        .RE(1'b1),
        .RADDR({3'b000, ram_read_address}),
        .WCLK(i_wb_clk),
        .WCLKE(data_write),
        .WE(1'b1),
        .WADDR({3'b000, ram_write_address}),
        .MASK(16'd0),
        .WDATA(i_wb_dat[31:16])
    );

    SB_RAM40_4K #(
        .READ_MODE(0),
        .WRITE_MODE(0)
    ) sample_memory_r (
        .RDATA(ram_read_r),
        .RCLK(i_audio_clk),
        .RCLKE(pop),
        .RE(1'b1),
        .RADDR({3'b000, ram_read_address}),
        .WCLK(i_wb_clk),
        .WCLKE(data_write),
        .WE(1'b1),
        .WADDR({3'b000, ram_write_address}),
        .MASK(16'd0),
        .WDATA(i_wb_dat[15:0])
    );

    always @(posedge i_wb_clk) begin
        if (i_wb_reset) begin
            write_binary <= 0;
            write_gray <= 0;
            read_gray_wb_meta <= 0;
            read_gray_wb <= 0;
            full <= 0;
            underflow_wb_meta <= 0;
            underflow_wb <= 0;
            o_wb_dat <= 0;
            o_wb_ack <= 0;
        end else begin
            read_gray_wb_meta <= read_gray;
            read_gray_wb <= read_gray_wb_meta;
            underflow_wb_meta <= underflow;
            underflow_wb <= underflow_wb_meta;
            full <= full_next;
            o_wb_ack <= 1'b0;

            if (data_write) begin
                write_binary <= write_binary_next;
                write_gray <= write_gray_next;
            end

            if (request && !o_wb_ack) begin
                o_wb_ack <= 1'b1;
                case (i_wb_adr[3:2])
                    2'd0: o_wb_dat <= DEVICE_ID;
                    2'd1: o_wb_dat <= {30'd0, underflow_wb, !full};
                    default: o_wb_dat <= 0;
                endcase
            end
        end
    end

    always @(posedge i_audio_clk) begin
        if (i_audio_reset) begin
            read_binary <= 0;
            read_gray <= 0;
            write_gray_audio_meta <= 0;
            write_gray_audio <= 0;
            read_pending <= 0;
            underflow <= 0;
            o_sample_l <= 0;
            o_sample_r <= 0;
            o_rate_adjust <= 0;
            o_ready <= 0;
        end else begin
            write_gray_audio_meta <= write_gray;
            write_gray_audio <= write_gray_audio_meta;

            if (read_pending) begin
                o_sample_l <= ram_read_l;
                o_sample_r <= ram_read_r;
                read_binary <= read_binary_next;
                read_gray <= read_gray_next;
                read_pending <= 1'b0;
            end else if (pop) begin
                read_pending <= 1'b1;
            end else if (i_sample_req && o_ready && empty) begin
                underflow <= 1'b1;
                o_ready <= 1'b0;
                o_rate_adjust <= 0;
                o_sample_l <= 0;
                o_sample_r <= 0;
            end

            if (!o_ready) begin
                o_rate_adjust <= 0;
                if (audio_level >= TARGET_LEVEL)
                    o_ready <= 1'b1;
            end else if (i_sample_req) begin
                if ((audio_level > TARGET_LEVEL) && (o_rate_adjust < RATE_LIMIT))
                    o_rate_adjust <= o_rate_adjust + RATE_STEP;
                else if ((audio_level < TARGET_LEVEL) && (o_rate_adjust > -RATE_LIMIT))
                    o_rate_adjust <= o_rate_adjust - RATE_STEP;
            end
        end
    end
endmodule