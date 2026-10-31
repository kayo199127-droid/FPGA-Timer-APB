`timescale 1ns/1ps

// Assigned member: Tran Dinh Quoc (CE202008) - Member 5: Register Bank.
// FAP201 IP Timer register bank.
// Register offsets are byte addresses; low two address bits are ignored.
module register #(
    parameter ADDR_W = 12
) (
    input  wire              sys_clk,
    input  wire              sys_rst_n,
    input  wire              reg_wr_en,
    input  wire [ADDR_W-1:0] reg_addr,
    input  wire [31:0]       reg_wdata,
    input  wire [3:0]        reg_pstrb,
    output reg  [31:0]       reg_rdata,
    output wire              reg_err,

    output wire              timer_en,
    output wire              div_en,
    output wire [3:0]        div_val,
    output wire [63:0]       tcmp,
    output wire              int_en,
    output wire              halt_req,
    output wire              tim_int,

    output wire              tdr0_load,
    output wire [31:0]       tdr0_wdata,
    output wire              tdr1_load,
    output wire [31:0]       tdr1_wdata,

    input  wire [31:0]       tdr0_rdata,
    input  wire [31:0]       tdr1_rdata,
    input  wire              int_set,
    input  wire              halt_ack
);
    localparam [ADDR_W-1:0] A_TCR   = 'h000;
    localparam [ADDR_W-1:0] A_TDR0  = 'h004;
    localparam [ADDR_W-1:0] A_TDR1  = 'h008;
    localparam [ADDR_W-1:0] A_TCMP0 = 'h00C;
    localparam [ADDR_W-1:0] A_TCMP1 = 'h010;
    localparam [ADDR_W-1:0] A_TIER  = 'h014;
    localparam [ADDR_W-1:0] A_TISR  = 'h018;
    localparam [ADDR_W-1:0] A_THCSR = 'h01C;

    reg        r_timer_en;
    reg        r_div_en;
    reg [3:0]  r_div_val;
    reg [31:0] r_tcmp0;
    reg [31:0] r_tcmp1;
    reg        r_int_en;
    reg        r_int_st;
    reg        r_halt_req;

    function [31:0] merge_bytes;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strobe;
        begin
            merge_bytes = {
                strobe[3] ? new_value[31:24] : old_value[31:24],
                strobe[2] ? new_value[23:16] : old_value[23:16],
                strobe[1] ? new_value[15:8]  : old_value[15:8],
                strobe[0] ? new_value[7:0]   : old_value[7:0]
            };
        end
    endfunction

    wire [ADDR_W-1:0] aligned_addr = {reg_addr[ADDR_W-1:2], 2'b00};
    wire sel_tcr   = (aligned_addr == A_TCR);
    wire sel_tdr0  = (aligned_addr == A_TDR0);
    wire sel_tdr1  = (aligned_addr == A_TDR1);
    wire sel_tcmp0 = (aligned_addr == A_TCMP0);
    wire sel_tcmp1 = (aligned_addr == A_TCMP1);
    wire sel_tier  = (aligned_addr == A_TIER);
    wire sel_tisr  = (aligned_addr == A_TISR);
    wire sel_thcsr = (aligned_addr == A_THCSR);

    wire wr_tcr   = reg_wr_en && sel_tcr;
    wire wr_tcmp0 = reg_wr_en && sel_tcmp0;
    wire wr_tcmp1 = reg_wr_en && sel_tcmp1;
    wire wr_tier  = reg_wr_en && sel_tier;
    wire wr_tisr  = reg_wr_en && sel_tisr;
    wire wr_thcsr = reg_wr_en && sel_thcsr;

    wire [31:0] tcr_current = {20'b0, r_div_val, 6'b0, r_div_en, r_timer_en};
    wire [31:0] tcr_merged  = merge_bytes(tcr_current, reg_wdata, reg_pstrb);
    wire        new_timer_en = tcr_merged[0];
    wire        new_div_en   = tcr_merged[1];
    wire [3:0]  new_div_val  = tcr_merged[11:8];

    // div_val 0..7 are legal. A write to div_val is checked only when byte 1 is strobed.
    wire err_divider_value = wr_tcr && reg_pstrb[1] && new_div_val[3];
    // Divider configuration is locked while the timer is currently enabled.
    wire err_divider_lock = wr_tcr && r_timer_en &&
                            ((new_div_en != r_div_en) || (new_div_val != r_div_val));
    assign reg_err = err_divider_value || err_divider_lock;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            r_timer_en <= 1'b0;
            r_div_en   <= 1'b0;
            r_div_val  <= 4'd0;
            r_tcmp0    <= 32'hFFFF_FFFF;
            r_tcmp1    <= 32'hFFFF_FFFF;
            r_int_en   <= 1'b0;
            r_int_st   <= 1'b0;
            r_halt_req <= 1'b0;
        end else begin
            if (wr_tcr && !reg_err) begin
                r_timer_en <= new_timer_en;
                r_div_en   <= new_div_en;
                r_div_val  <= new_div_val;
            end

            if (wr_tcmp0)
                r_tcmp0 <= merge_bytes(r_tcmp0, reg_wdata, reg_pstrb);
            if (wr_tcmp1)
                r_tcmp1 <= merge_bytes(r_tcmp1, reg_wdata, reg_pstrb);
            if (wr_tier)
                r_int_en <= merge_bytes({31'b0, r_int_en}, reg_wdata, reg_pstrb) & 32'h1;
            if (wr_thcsr)
                r_halt_req <= merge_bytes({31'b0, r_halt_req}, reg_wdata, reg_pstrb) & 32'h1;

            // Design SPEC priority: software W1C clear wins over a simultaneous hardware set.
            if (wr_tisr && reg_pstrb[0] && reg_wdata[0])
                r_int_st <= 1'b0;
            else if (int_set)
                r_int_st <= 1'b1;
        end
    end

    assign tdr0_load  = reg_wr_en && sel_tdr0 && (|reg_pstrb);
    assign tdr1_load  = reg_wr_en && sel_tdr1 && (|reg_pstrb);
    assign tdr0_wdata = merge_bytes(tdr0_rdata, reg_wdata, reg_pstrb);
    assign tdr1_wdata = merge_bytes(tdr1_rdata, reg_wdata, reg_pstrb);

    always @(*) begin
        case (1'b1)
            sel_tcr:   reg_rdata = tcr_current;
            sel_tdr0:  reg_rdata = tdr0_rdata;
            sel_tdr1:  reg_rdata = tdr1_rdata;
            sel_tcmp0: reg_rdata = r_tcmp0;
            sel_tcmp1: reg_rdata = r_tcmp1;
            sel_tier:  reg_rdata = {31'b0, r_int_en};
            sel_tisr:  reg_rdata = {31'b0, r_int_st};
            sel_thcsr: reg_rdata = {30'b0, halt_ack, r_halt_req};
            default:   reg_rdata = 32'b0; // Reserved: read-as-zero, writes ignored.
        endcase
    end

    assign timer_en = r_timer_en;
    assign div_en   = r_div_en;
    assign div_val  = r_div_val;
    assign tcmp     = {r_tcmp1, r_tcmp0};
    assign int_en   = r_int_en;
    assign halt_req = r_halt_req;
    assign tim_int  = r_int_st & r_int_en;
endmodule
