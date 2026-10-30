`timescale 1ns/1ps
//==============================================================================
// Module  : register
// Project : IP TIMER (APB) - Advanced Mode
// Role    : Tap thanh ghi 32-bit, byte access (PSTRB), bao ve TCR, bao loi
//
// BAN DO DIA CHI (byte address)
//   0x00 TCR   : [0] timer_en  (RW)
//                [1] div_en    (RW)   -- bi bao ve khi timer_en = 1
//                [11:8] div_val(RW)   -- bi bao ve khi timer_en = 1
//                                        0000..0111 hop le; period = 2^div_val
//                                        1000..1111 CAM (prohibited)
//                cac bit con lai: reserved (RAZ/WI)
//   0x04 TDR0  : [31:0] bo dem 64-bit, phan thap  (RW)
//   0x08 TDR1  : [31:0] bo dem 64-bit, phan cao   (RW)
//   0x0C TCMP0 : [31:0] gia tri so sanh, phan thap (RW, reset = 0xFFFF_FFFF)
//   0x10 TCMP1 : [31:0] gia tri so sanh, phan cao  (RW, reset = 0xFFFF_FFFF)
//   0x14 TIER  : [0] int_en                        (RW)
//   0x18 TISR  : [0] int_st                        (W1C)
//   0x1C THCSR : [0] halt_req (RW), [1] halt_ack (RO)
//   Dia chi khac 0x1C : reserved -> doc = 0, ghi bi bo qua, KHONG bao loi.
//
// QUY UOC GIAO TIEP VOI apb_slave
//   - reg_wr_en : xung 1 chu ky, dung chu ky giao dich ghi hoan tat.
//   - reg_addr/reg_wdata/reg_pstrb : giu on dinh trong chu ky do.
//   - reg_rdata : to hop theo reg_addr (apb_slave tu lay mau khi doc).
//   - reg_err   : to hop, hop le cung chu ky voi reg_wr_en. APB master phai
//                 giu dia chi/du lieu on dinh den khi PREADY = 1.
//   - Khi reg_err = 1 thi lenh ghi TCR do KHONG co tac dung (khong cap nhat
//     bat ky truong nao cua TCR).
//   - Dia chi khong can le tu: reg_addr[1:0] bi bo qua.
//==============================================================================
module register #(
    parameter ADDR_W = 12,
    parameter [3:0] RESET_DIV_VAL = 4'h0,
    // 1 follows the Design SPEC (software W1C clear wins); 0 preserves the
    // legacy register-only reference testbench behavior (hardware set wins).
    parameter SW_CLEAR_PRIORITY = 1'b0
)(
    input  wire              sys_clk,
    input  wire              sys_rst_n,      // async reset, active low

    // ---- Giao tiep voi apb_slave ----
    input  wire              reg_wr_en,
    input  wire [ADDR_W-1:0] reg_addr,
    input  wire [31:0]       reg_wdata,
    input  wire [3:0]        reg_pstrb,
    output reg  [31:0]       reg_rdata,
    output wire              reg_err,

    // ---- Cau hinh ra timer_divider / timer_core ----
    output wire              timer_en,
    output wire              div_en,
    output wire [3:0]        div_val,
    output wire [63:0]       tcmp,           // {TCMP1, TCMP0}
    output wire              int_en,
    output wire              halt_req,
    output wire              tim_int,        // = int_st & int_en (muc)

    // ---- Nap gia tri bo dem (ghi TDR0/TDR1) ----
    output wire              tdr0_load,
    output wire [31:0]       tdr0_wdata,     // da gop theo pstrb
    output wire              tdr1_load,
    output wire [31:0]       tdr1_wdata,

    // ---- Tu timer_core ----
    input  wire [31:0]       tdr0_rdata,     // gia tri dem hien tai [31:0]
    input  wire [31:0]       tdr1_rdata,     // gia tri dem hien tai [63:32]
    input  wire              int_set,        // dem == TCMP -> set TISR.int_st
    input  wire              halt_ack        // trang thai halt (THCSR[1])
);

    //--------------------------------------------------------------------------
    // Hang so dia chi & vi tri bit
    //--------------------------------------------------------------------------
    localparam [ADDR_W-1:0] A_TCR   = 'h00;
    localparam [ADDR_W-1:0] A_TDR0  = 'h04;
    localparam [ADDR_W-1:0] A_TDR1  = 'h08;
    localparam [ADDR_W-1:0] A_TCMP0 = 'h0C;
    localparam [ADDR_W-1:0] A_TCMP1 = 'h10;
    localparam [ADDR_W-1:0] A_TIER  = 'h14;
    localparam [ADDR_W-1:0] A_TISR  = 'h18;
    localparam [ADDR_W-1:0] A_THCSR = 'h1C;

    localparam TCR_TIMER_EN = 0;
    localparam TCR_DIV_EN   = 1;
    localparam TCR_DIV_LSB  = 8;   // div_val = TCR[11:8]

    //--------------------------------------------------------------------------
    // Thanh ghi
    //--------------------------------------------------------------------------
    reg         r_timer_en;
    reg         r_div_en;
    reg  [3:0]  r_div_val;
    reg  [31:0] r_tcmp0;
    reg  [31:0] r_tcmp1;

    // Hierarchical alias retained for the supplied integration testbench.
    wire [31:0] tcmp0_reg = r_tcmp0;
    reg         r_int_en;
    reg         r_int_st;
    reg         r_halt_req;

    //--------------------------------------------------------------------------
    // Gop du lieu theo byte strobe: byte nao co pstrb=1 thi lay du lieu moi
    //--------------------------------------------------------------------------
    function [31:0] merge;
        input [31:0] old_v;
        input [31:0] new_v;
        input [3:0]  strb;
        begin
            merge = { strb[3] ? new_v[31:24] : old_v[31:24],
                      strb[2] ? new_v[23:16] : old_v[23:16],
                      strb[1] ? new_v[15:8]  : old_v[15:8],
                      strb[0] ? new_v[7:0]   : old_v[7:0] };
        end
    endfunction

    //--------------------------------------------------------------------------
    // Giai ma dia chi (bo qua 2 bit thap; dia chi ngoai 0x00..0x1C = reserved)
    //--------------------------------------------------------------------------
    wire [ADDR_W-1:0] a = {reg_addr[ADDR_W-1:2], 2'b00};

    wire sel_tcr   = (a == A_TCR);
    wire sel_tdr0  = (a == A_TDR0);
    wire sel_tdr1  = (a == A_TDR1);
    wire sel_tcmp0 = (a == A_TCMP0);
    wire sel_tcmp1 = (a == A_TCMP1);
    wire sel_tier  = (a == A_TIER);
    wire sel_tisr  = (a == A_TISR);
    wire sel_thcsr = (a == A_THCSR);

    wire wr_tcr   = reg_wr_en & sel_tcr;
    wire wr_tcmp0 = reg_wr_en & sel_tcmp0;
    wire wr_tcmp1 = reg_wr_en & sel_tcmp1;
    wire wr_tier  = reg_wr_en & sel_tier;
    wire wr_tisr  = reg_wr_en & sel_tisr;
    wire wr_thcsr = reg_wr_en & sel_thcsr;

    //--------------------------------------------------------------------------
    // TCR: tinh gia tri moi sau khi gop byte, kiem tra vi pham
    //--------------------------------------------------------------------------
    wire [31:0] tcr_cur = {20'b0, r_div_val, 6'b0, r_div_en, r_timer_en};
    wire [31:0] tcr_new = merge(tcr_cur, reg_wdata, reg_pstrb);

    wire        n_timer_en = tcr_new[TCR_TIMER_EN];
    wire        n_div_en   = tcr_new[TCR_DIV_EN];
    wire [3:0]  n_div_val  = tcr_new[TCR_DIV_LSB +: 4];

    // (1) Ghi gia tri cam vao div_val (>= 1000b). Chi xet khi byte chua div_val
    //     (byte 1) thuc su duoc ghi.
    wire err_prohibited = wr_tcr & reg_pstrb[1] & n_div_val[3];

    // (2) Doi div_en / div_val khi timer_en dang = 1 (ghi cung gia tri cu
    //     khong tinh la thay doi).
    wire err_protect    = wr_tcr & r_timer_en &
                          ((n_div_en != r_div_en) || (n_div_val != r_div_val));

    assign reg_err = err_prohibited | err_protect;

    //--------------------------------------------------------------------------
    // Ghi thanh ghi
    //--------------------------------------------------------------------------
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            r_timer_en <= 1'b0;
            r_div_en   <= 1'b0;
            r_div_val  <= RESET_DIV_VAL;
            r_tcmp0    <= 32'hFFFF_FFFF;
            r_tcmp1    <= 32'hFFFF_FFFF;
            r_int_en   <= 1'b0;
            r_int_st   <= 1'b0;
            r_halt_req <= 1'b0;
        end else begin
            // TCR: neu co loi thi bo ca lenh ghi
            if (wr_tcr && !reg_err) begin
                r_timer_en <= n_timer_en;
                r_div_en   <= n_div_en;
                r_div_val  <= n_div_val;
            end

            if (wr_tcmp0) r_tcmp0 <= merge(r_tcmp0, reg_wdata, reg_pstrb);
            if (wr_tcmp1) r_tcmp1 <= merge(r_tcmp1, reg_wdata, reg_pstrb);

            if (wr_tier)  r_int_en   <= merge({31'b0, r_int_en},   reg_wdata, reg_pstrb) & 1'b1;
            if (wr_thcsr) r_halt_req <= merge({30'b0, 1'b0, r_halt_req}, reg_wdata, reg_pstrb) & 1'b1;

            // TISR is W1C. Select the simultaneous set/clear policy through
            // a parameter so the top-level follows the Design SPEC while the
            // legacy standalone register test remains reproducible.
            if (SW_CLEAR_PRIORITY) begin
                if (wr_tisr && reg_pstrb[0] && reg_wdata[0])
                    r_int_st <= 1'b0;
                else if (int_set)
                    r_int_st <= 1'b1;
            end else begin
                if (int_set)
                    r_int_st <= 1'b1;
                else if (wr_tisr && reg_pstrb[0] && reg_wdata[0])
                    r_int_st <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // TDR0/TDR1: dua xung nap + du lieu da gop byte cho timer_core
    //--------------------------------------------------------------------------
    assign tdr0_load  = reg_wr_en & sel_tdr0 & (|reg_pstrb);
    assign tdr1_load  = reg_wr_en & sel_tdr1 & (|reg_pstrb);
    assign tdr0_wdata = merge(tdr0_rdata, reg_wdata, reg_pstrb);
    assign tdr1_wdata = merge(tdr1_rdata, reg_wdata, reg_pstrb);

    //--------------------------------------------------------------------------
    // Doc thanh ghi (reserved -> 0, bit reserved -> 0)
    //--------------------------------------------------------------------------
    always @(*) begin
        case (1'b1)
            sel_tcr   : reg_rdata = tcr_cur;
            sel_tdr0  : reg_rdata = tdr0_rdata;
            sel_tdr1  : reg_rdata = tdr1_rdata;
            sel_tcmp0 : reg_rdata = r_tcmp0;
            sel_tcmp1 : reg_rdata = r_tcmp1;
            sel_tier  : reg_rdata = {31'b0, r_int_en};
            sel_tisr  : reg_rdata = {31'b0, r_int_st};
            sel_thcsr : reg_rdata = {30'b0, halt_ack, r_halt_req};
            default   : reg_rdata = 32'b0;
        endcase
    end

    //--------------------------------------------------------------------------
    // Ngo ra
    //--------------------------------------------------------------------------
    assign timer_en = r_timer_en;
    assign div_en   = r_div_en;
    assign div_val  = r_div_val;
    assign tcmp     = {r_tcmp1, r_tcmp0};
    assign int_en   = r_int_en;
    assign halt_req = r_halt_req;
    assign tim_int  = r_int_st & r_int_en;

endmodule
