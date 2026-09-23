module wishbone_interconnect #(
    parameter [3:0] SLAVE_ENABLE = 4'b0001
) (
    input wire [31:0] i_m_adr,
    input wire [31:0] i_m_dat,
    input wire [3:0] i_m_sel,
    input wire i_m_we,
    input wire i_m_cyc,
    input wire i_m_stb,
    output reg [31:0] o_m_dat,
    output reg o_m_ack,
    output reg o_m_err,

    output wire [31:0] o_s_adr,
    output wire [31:0] o_s_dat,
    output wire [3:0] o_s_sel,
    output wire o_s_we,
    output wire [3:0] o_s_cyc,
    output wire [3:0] o_s_stb,
    input wire [127:0] i_s_dat,
    input wire [3:0] i_s_ack,
    input wire [3:0] i_s_err
);
    wire request = i_m_cyc && i_m_stb;
    wire in_peripheral_region = (i_m_adr[31:14] == 18'h04000);
    wire [1:0] slave_index = i_m_adr[13:12];
    wire slave_enabled = SLAVE_ENABLE[slave_index];
    wire target_valid = in_peripheral_region && slave_enabled;
    wire [3:0] selected_slave = 4'b0001 << slave_index;

    assign o_s_adr = i_m_adr;
    assign o_s_dat = i_m_dat;
    assign o_s_sel = i_m_sel;
    assign o_s_we = i_m_we;
    assign o_s_cyc = (i_m_cyc && target_valid) ? selected_slave : 4'b0000;
    assign o_s_stb = request && target_valid ? selected_slave : 4'b0000;

    always @* begin
        o_m_dat = 32'd0;
        o_m_ack = 1'b0;
        o_m_err = 1'b0;

        if (request && !target_valid) begin
            o_m_ack = 1'b1;
            o_m_err = 1'b1;
        end else if (target_valid) begin
            case (slave_index)
                2'd0: begin
                    o_m_dat = i_s_dat[31:0];
                    o_m_ack = i_s_ack[0];
                    o_m_err = i_s_err[0];
                end
                2'd1: begin
                    o_m_dat = i_s_dat[63:32];
                    o_m_ack = i_s_ack[1];
                    o_m_err = i_s_err[1];
                end
                2'd2: begin
                    o_m_dat = i_s_dat[95:64];
                    o_m_ack = i_s_ack[2];
                    o_m_err = i_s_err[2];
                end
                default: begin
                    o_m_dat = i_s_dat[127:96];
                    o_m_ack = i_s_ack[3];
                    o_m_err = i_s_err[3];
                end
            endcase
        end
    end
endmodule

module wishbone_scratch (
    input wire i_clk,
    input wire i_reset,
    input wire [31:0] i_wb_adr,
    input wire [31:0] i_wb_dat,
    input wire [3:0] i_wb_sel,
    input wire i_wb_we,
    input wire i_wb_cyc,
    input wire i_wb_stb,
    output reg [31:0] o_wb_dat,
    output wire o_wb_ack,
    output wire o_wb_err,
    output wire [31:0] o_scratch
);
    localparam [31:0] DEVICE_ID = 32'h49434542;

    reg [31:0] scratch = 0;
    wire request = i_wb_cyc && i_wb_stb;

    assign o_wb_ack = request;
    assign o_wb_err = 1'b0;
    assign o_scratch = scratch;

    always @* begin
        case (i_wb_adr[3:2])
            2'd0: o_wb_dat = DEVICE_ID;
            2'd1: o_wb_dat = scratch;
            default: o_wb_dat = 32'd0;
        endcase
    end

    always @(posedge i_clk) begin
        if (i_reset) begin
            scratch <= 0;
        end else if (request && i_wb_we && (i_wb_adr[3:2] == 2'd1)) begin
            if (i_wb_sel[0]) scratch[7:0] <= i_wb_dat[7:0];
            if (i_wb_sel[1]) scratch[15:8] <= i_wb_dat[15:8];
            if (i_wb_sel[2]) scratch[23:16] <= i_wb_dat[23:16];
            if (i_wb_sel[3]) scratch[31:24] <= i_wb_dat[31:24];
        end
    end
endmodule