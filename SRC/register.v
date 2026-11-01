`timescale 1ns/1ps
// ============================================================================
// Module : timer_register
// Project: 64-bit APB Timer IP
// Purpose: Timer control/status register bank, byte strobes and RW1C logic.
// Address map (byte address, word-aligned decode):
//   0x00 TCR   [0] timer_en, [1] div_en, [11:8] div_val
//   0x04 TDR0  [31:0] timer counter low word (read/write)
//   0x08 TDR1  [31:0] timer counter high word (read/write)
//   0x0C TCMP0 [31:0] compare value low word (reset 0xFFFF_FFFF)
//   0x10 TCMP1 [31:0] compare value high word (reset 0xFFFF_FFFF)
//   0x14 TIER  [0] interrupt enable
//   0x18 TISR  [0] interrupt status, write-one-to-clear (RW1C)
//   0x1C THCSR [0] halt request, [1] halt acknowledge (read-only)
// Other addresses/bits are reserved: reads return zero; writes are ignored.
// ============================================================================
module timer_register #(
    parameter ADDR_W = 12
) (
    input  wire              sys_clk,
    input  wire              sys_rst_n,

    // Completed APB write request
    input  wire              reg_wr_en,
    input  wire [ADDR_W-1:0] reg_addr,
    input  wire [31:0]       reg_wdata,
    input  wire [3:0]        reg_pstrb,
    output reg  [31:0]       reg_rdata,
    output wire              reg_err,

    // Timer configuration and interrupt outputs
    output wire              timer_en,
    output wire              div_en,
    output wire [3:0]        div_val,
    output wire [63:0]       tcmp,
    output wire              int_en,
    output wire              halt_req,
    output wire              tim_int,

    // TDR write interface and current counter readback
    output wire              tdr0_load,
    output wire [31:0]       tdr0_wdata,
    output wire              tdr1_load,
    output wire [31:0]       tdr1_wdata,
    input  wire [31:0]       tdr0_rdata,
    input  wire [31:0]       tdr1_rdata,

    // Hardware status inputs
    input  wire              int_set,
    input  wire              halt_ack
);

    localparam [ADDR_W-1:0] A_TCR   = 12'h000;
    localparam [ADDR_W-1:0] A_TDR0  = 12'h004;
    localparam [ADDR_W-1:0] A_TDR1  = 12'h008;
    localparam [ADDR_W-1:0] A_TCMP0 = 12'h00C;
    localparam [ADDR_W-1:0] A_TCMP1 = 12'h010;
    localparam [ADDR_W-1:0] A_TIER  = 12'h014;
    localparam [ADDR_W-1:0] A_TISR  = 12'h018;
    localparam [ADDR_W-1:0] A_THCSR = 12'h01C;

    reg        r_timer_en;
    reg        r_div_en;
    reg [3:0]  r_div_val;
    reg [31:0] r_tcmp0;
    reg [31:0] r_tcmp1;
    reg        r_int_en;
    reg        r_int_st;
    reg        r_halt_req;

    wire [ADDR_W-1:0] addr_aligned;
    wire sel_tcr, sel_tdr0, sel_tdr1, sel_tcmp0, sel_tcmp1;
    wire sel_tier, sel_tisr, sel_thcsr;
    wire wr_tcr, wr_tcmp0, wr_tcmp1, wr_tier, wr_tisr, wr_thcsr;
    wire [31:0] tcr_current;
    wire [31:0] tcr_merged;
    wire        next_timer_en;
    wire        next_div_en;
    wire [3:0]  next_div_val;
    wire        err_prohibited_divider;
    wire        err_change_while_enabled;
    wire [31:0] tier_merged;
    wire [31:0] thcsr_merged;

    // Merge only the byte lanes selected by PSTRB.
    function [31:0] merge_bytes;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  byte_strobe;
        begin
            merge_bytes = {
                byte_strobe[3] ? new_value[31:24] : old_value[31:24],
                byte_strobe[2] ? new_value[23:16] : old_value[23:16],
                byte_strobe[1] ? new_value[15:8]  : old_value[15:8],
                byte_strobe[0] ? new_value[7:0]   : old_value[7:0]
            };
        end
    endfunction

    // Ignore address bits [1:0] so all byte offsets in one word select it.
    assign addr_aligned = {reg_addr[ADDR_W-1:2], 2'b00};

    assign sel_tcr   = (addr_aligned == A_TCR);
    assign sel_tdr0  = (addr_aligned == A_TDR0);
    assign sel_tdr1  = (addr_aligned == A_TDR1);
    assign sel_tcmp0 = (addr_aligned == A_TCMP0);
    assign sel_tcmp1 = (addr_aligned == A_TCMP1);
    assign sel_tier  = (addr_aligned == A_TIER);
    assign sel_tisr  = (addr_aligned == A_TISR);
    assign sel_thcsr = (addr_aligned == A_THCSR);

    assign wr_tcr   = reg_wr_en && sel_tcr;
    assign wr_tcmp0 = reg_wr_en && sel_tcmp0;
    assign wr_tcmp1 = reg_wr_en && sel_tcmp1;
    assign wr_tier  = reg_wr_en && sel_tier;
    assign wr_tisr  = reg_wr_en && sel_tisr;
    assign wr_thcsr = reg_wr_en && sel_thcsr;

    assign tcr_current = {20'b0, r_div_val, 6'b0, r_div_en, r_timer_en};
    assign tcr_merged  = merge_bytes(tcr_current, reg_wdata, reg_pstrb);
    assign next_timer_en = tcr_merged[0];
    assign next_div_en   = tcr_merged[1];
    assign next_div_val  = tcr_merged[11:8];

    // div_val[3] = 1 represents a prohibited prescaler value (8..15).
    // A running timer also locks div_en and div_val until it is stopped.
    assign tier_merged  = merge_bytes({31'b0, r_int_en}, reg_wdata, reg_pstrb);
    assign thcsr_merged = merge_bytes({31'b0, r_halt_req}, reg_wdata, reg_pstrb);

    assign err_prohibited_divider = wr_tcr && reg_pstrb[1] && next_div_val[3];
    assign err_change_while_enabled = wr_tcr && r_timer_en &&
        ((next_div_en != r_div_en) || (next_div_val != r_div_val));
    assign reg_err = err_prohibited_divider || err_change_while_enabled;

    // Register update logic. Hardware interrupt set has priority over SW W1C.
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
                r_timer_en <= next_timer_en;
                r_div_en   <= next_div_en;
                r_div_val  <= next_div_val;
            end

            if (wr_tcmp0)
                r_tcmp0 <= merge_bytes(r_tcmp0, reg_wdata, reg_pstrb);
            if (wr_tcmp1)
                r_tcmp1 <= merge_bytes(r_tcmp1, reg_wdata, reg_pstrb);

            if (wr_tier)
                r_int_en <= tier_merged[0];

            if (wr_thcsr)
                r_halt_req <= thcsr_merged[0];

            if (wr_tisr && reg_pstrb[0] && reg_wdata[0])
                r_int_st <= 1'b0;
            if (int_set)
                r_int_st <= 1'b1;
        end
    end

    // TDR is the live 64-bit counter. The top module stores its programmed
    // value so it can be restored while the timer is disabled.
    assign tdr0_load  = reg_wr_en && sel_tdr0 && (|reg_pstrb);
    assign tdr1_load  = reg_wr_en && sel_tdr1 && (|reg_pstrb);
    assign tdr0_wdata = merge_bytes(tdr0_rdata, reg_wdata, reg_pstrb);
    assign tdr1_wdata = merge_bytes(tdr1_rdata, reg_wdata, reg_pstrb);

    // Combinational read mux; reserved addresses and bits read as zero.
    always @(*) begin
        case (addr_aligned)
            A_TCR:   reg_rdata = tcr_current;
            A_TDR0:  reg_rdata = tdr0_rdata;
            A_TDR1:  reg_rdata = tdr1_rdata;
            A_TCMP0: reg_rdata = r_tcmp0;
            A_TCMP1: reg_rdata = r_tcmp1;
            A_TIER:  reg_rdata = {31'b0, r_int_en};
            A_TISR:  reg_rdata = {31'b0, r_int_st};
            A_THCSR: reg_rdata = {30'b0, halt_ack, r_halt_req};
            default: reg_rdata = 32'b0;
        endcase
    end

    assign timer_en = r_timer_en;
    assign div_en   = r_div_en;
    assign div_val  = r_div_val;
    assign tcmp     = {r_tcmp1, r_tcmp0};
    assign int_en   = r_int_en;
    assign halt_req = r_halt_req;
    assign tim_int  = r_int_st && r_int_en;

endmodule
