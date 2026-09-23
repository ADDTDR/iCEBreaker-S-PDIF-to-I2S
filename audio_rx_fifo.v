module wishbone_audio_rx #(
    parameter integer ADDRESS_BITS = 4
) (
    input wire i_audio_clk,
    input wire i_audio_reset,
    input wire i_sample_strobe,
    input wire signed [15:0] i_sample_l,
    input wire signed [15:0] i_sample_r,

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
    output wire [31:0] o_scratch,
    output wire signed [15:0] o_spectrum_sample_l,
    output wire signed [15:0] o_spectrum_sample_r,
    output reg o_spectrum_sample_strobe = 0
);
    localparam [31:0] DEVICE_ID = 32'h49434542;
    localparam integer POINTER_BITS = ADDRESS_BITS + 1;

    reg [POINTER_BITS-1:0] write_binary = 0;
    reg [POINTER_BITS-1:0] write_gray = 0;
    reg [POINTER_BITS-1:0] read_binary = 0;
    reg [POINTER_BITS-1:0] read_gray = 0;
    reg [POINTER_BITS-1:0] read_gray_audio_meta = 0;
    reg [POINTER_BITS-1:0] read_gray_audio = 0;
    reg [POINTER_BITS-1:0] write_gray_wb_meta = 0;
    reg [POINTER_BITS-1:0] write_gray_wb = 0;
    reg overflow = 0;
    reg full = 0;
    reg overflow_wb_meta = 0;
    reg overflow_wb = 0;
    reg [31:0] scratch = 0;
    reg data_read_pending = 0;
    reg [31:0] spectrum_sample = 0;
    reg spectrum_toggle = 0;
    reg spectrum_toggle_meta = 0;
    reg spectrum_toggle_audio = 0;
    reg spectrum_toggle_seen = 0;

    wire request = i_wb_cyc && i_wb_stb;
    wire push = i_sample_strobe && !full;
    wire [POINTER_BITS-1:0] write_binary_next = write_binary + push;
    wire [POINTER_BITS-1:0] write_gray_next = (write_binary_next >> 1) ^ write_binary_next;
    wire [POINTER_BITS-1:0] read_binary_next = read_binary + 1'b1;
    wire [POINTER_BITS-1:0] read_gray_next = (read_binary_next >> 1) ^ read_binary_next;
    wire full_next = write_gray_next == {
        ~read_gray_audio[POINTER_BITS-1:POINTER_BITS-2],
        read_gray_audio[POINTER_BITS-3:0]
    };
    wire empty = read_gray == write_gray_wb;
    wire data_read_request = request && !o_wb_ack && !data_read_pending &&
                             (i_wb_adr[3:2] == 2'd2) && !empty;
    wire [7:0] ram_write_address = {{(8-ADDRESS_BITS){1'b0}}, write_binary[ADDRESS_BITS-1:0]};
    wire [7:0] ram_read_address = {{(8-ADDRESS_BITS){1'b0}}, read_binary[ADDRESS_BITS-1:0]};
    wire [15:0] ram_read_l;
    wire [15:0] ram_read_r;

    assign o_wb_err = 1'b0;
    assign o_scratch = scratch;
    assign o_spectrum_sample_l = spectrum_sample[31:16];
    assign o_spectrum_sample_r = spectrum_sample[15:0];

    SB_RAM40_4K #(
        .READ_MODE(0),
        .WRITE_MODE(0)
    ) sample_memory_l (
        .RDATA(ram_read_l),
        .RCLK(i_wb_clk),
        .RCLKE(data_read_request),
        .RE(1'b1),
        .RADDR({3'b000, ram_read_address}),
        .WCLK(i_audio_clk),
        .WCLKE(push),
        .WE(1'b1),
        .WADDR({3'b000, ram_write_address}),
        .MASK(16'd0),
        .WDATA(i_sample_l)
    );

    SB_RAM40_4K #(
        .READ_MODE(0),
        .WRITE_MODE(0)
    ) sample_memory_r (
        .RDATA(ram_read_r),
        .RCLK(i_wb_clk),
        .RCLKE(data_read_request),
        .RE(1'b1),
        .RADDR({3'b000, ram_read_address}),
        .WCLK(i_audio_clk),
        .WCLKE(push),
        .WE(1'b1),
        .WADDR({3'b000, ram_write_address}),
        .MASK(16'd0),
        .WDATA(i_sample_r)
    );

    always @(posedge i_audio_clk) begin
        if (i_audio_reset) begin
            write_binary <= 0;
            write_gray <= 0;
            read_gray_audio_meta <= 0;
            read_gray_audio <= 0;
            overflow <= 0;
            full <= 0;
            spectrum_toggle_meta <= 0;
            spectrum_toggle_audio <= 0;
            spectrum_toggle_seen <= 0;
            o_spectrum_sample_strobe <= 0;
        end else begin
            read_gray_audio_meta <= read_gray;
            read_gray_audio <= read_gray_audio_meta;
            full <= full_next;
            spectrum_toggle_meta <= spectrum_toggle;
            spectrum_toggle_audio <= spectrum_toggle_meta;
            o_spectrum_sample_strobe <= 0;

            if (spectrum_toggle_audio != spectrum_toggle_seen) begin
                spectrum_toggle_seen <= spectrum_toggle_audio;
                o_spectrum_sample_strobe <= 1'b1;
            end

            if (push) begin
                write_binary <= write_binary_next;
                write_gray <= write_gray_next;
            end else if (i_sample_strobe) begin
                overflow <= 1'b1;
            end
        end
    end

    always @(posedge i_wb_clk) begin
        if (i_wb_reset) begin
            read_binary <= 0;
            read_gray <= 0;
            write_gray_wb_meta <= 0;
            write_gray_wb <= 0;
            overflow_wb_meta <= 0;
            overflow_wb <= 0;
            scratch <= 0;
            o_wb_dat <= 0;
            o_wb_ack <= 0;
            data_read_pending <= 0;
            spectrum_sample <= 0;
            spectrum_toggle <= 0;
        end else begin
            write_gray_wb_meta <= write_gray;
            write_gray_wb <= write_gray_wb_meta;
            overflow_wb_meta <= overflow;
            overflow_wb <= overflow_wb_meta;
            o_wb_ack <= 1'b0;

            if (data_read_pending) begin
                o_wb_dat <= {ram_read_l, ram_read_r};
                o_wb_ack <= 1'b1;
                data_read_pending <= 1'b0;
                read_binary <= read_binary_next;
                read_gray <= read_gray_next;
            end else if (request && !o_wb_ack) begin
                o_wb_ack <= 1'b1;
                case (i_wb_adr[4:2])
                    3'd0: o_wb_dat <= DEVICE_ID;
                    3'd1: o_wb_dat <= {30'd0, overflow_wb, !empty};
                    3'd2: begin
                        if (!empty) begin
                            o_wb_ack <= 1'b0;
                            data_read_pending <= 1'b1;
                        end else begin
                            o_wb_dat <= 0;
                        end
                    end
                    3'd3: begin
                        o_wb_dat <= scratch;
                        if (i_wb_we) begin
                            if (i_wb_sel[0]) scratch[7:0] <= i_wb_dat[7:0];
                            if (i_wb_sel[1]) scratch[15:8] <= i_wb_dat[15:8];
                            if (i_wb_sel[2]) scratch[23:16] <= i_wb_dat[23:16];
                            if (i_wb_sel[3]) scratch[31:24] <= i_wb_dat[31:24];
                        end
                    end
                    3'd4: begin
                        o_wb_dat <= spectrum_sample;
                        if (i_wb_we) begin
                            spectrum_sample <= i_wb_dat;
                            spectrum_toggle <= ~spectrum_toggle;
                        end
                    end
                    default: o_wb_dat <= 0;
                endcase
            end
        end
    end
endmodule