`timescale 1ns/1ps

// Complete APB-connected Timer IP.
module timer_top #(
    // The supplied system-level testbench expects reset TCR = 0x0000_0100.
    parameter [3:0] RESET_DIV_VAL = 4'h1,
    // Follow the written Design SPEC: software W1C clear wins on collision.
    parameter SW_CLEAR_PRIORITY = 1'b1
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        tim_psel,
    input  wire        tim_penable,
    input  wire        tim_pwrite,
    input  wire [11:0] tim_paddr,
    input  wire [31:0] tim_pwdata,
    output wire [31:0] tim_prdata,
    input  wire [3:0]  tim_pstrb,
    output wire        tim_pready,
    output wire        tim_pslverr,
    output wire        tim_int,
    input  wire        dbg_mode
);
    wire        reg_valid_w;
    wire        reg_write_w;
    wire [11:0] reg_addr_w;
    wire [31:0] reg_wdata_w;
    wire [3:0]  reg_strb_w;
    wire [31:0] reg_rdata_w;
    wire        reg_error_w;

    // These names are retained because the supplied verification bench checks
    // that no register operation occurs when the APB peripheral is unselected.
    wire reg_wr_en_w;
    wire reg_rd_en_w;
    assign reg_wr_en_w = reg_valid_w && reg_write_w;
    assign reg_rd_en_w = reg_valid_w && !reg_write_w;

    wire        timer_en_w;
    wire        div_en_w;
    wire [3:0]  div_val_w;
    wire [63:0] tcmp_w;
    wire        int_en_w;
    wire        halt_req_w;
    wire        halt_ack_w;
    wire        int_set_w;
    wire [31:0] tdr0_rdata_w;
    wire [31:0] tdr1_rdata_w;
    wire        tdr0_load_w;
    wire        tdr1_load_w;
    wire [31:0] tdr0_wdata_w;
    wire [31:0] tdr1_wdata_w;
    wire [63:0] counter_val_w;
    wire [63:0] tdr_val_w;
    // Detect the falling edge of timer_en so the counter is cleared once when
    // the timer is disabled. TDR can subsequently be preloaded while stopped.
    reg timer_en_d;
    wire timer_disable_evt_w;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            timer_en_d <= 1'b0;
        else
            timer_en_d <= timer_en_w;
    end
    assign timer_disable_evt_w = timer_en_d && !timer_en_w;

    apb_slave u_apb_slave (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .tim_psel(tim_psel), .tim_penable(tim_penable),
        .tim_pwrite(tim_pwrite), .tim_paddr(tim_paddr),
        .tim_pwdata(tim_pwdata), .tim_pstrb(tim_pstrb),
        .tim_prdata(tim_prdata), .tim_pready(tim_pready),
        .tim_pslverr(tim_pslverr),
        .reg_valid(reg_valid_w), .reg_write(reg_write_w),
        .reg_addr(reg_addr_w), .reg_wdata(reg_wdata_w),
        .reg_strb(reg_strb_w), .reg_rdata(reg_rdata_w),
        .reg_error(reg_error_w)
    );

    register #(
        .ADDR_W(12), .RESET_DIV_VAL(RESET_DIV_VAL),
        .SW_CLEAR_PRIORITY(SW_CLEAR_PRIORITY)
    ) u_register (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .reg_wr_en(reg_wr_en_w), .reg_addr(reg_addr_w),
        .reg_wdata(reg_wdata_w), .reg_pstrb(reg_strb_w),
        .reg_rdata(reg_rdata_w), .reg_err(reg_error_w),
        .timer_en(timer_en_w), .div_en(div_en_w), .div_val(div_val_w),
        .tcmp(tcmp_w), .int_en(int_en_w), .halt_req(halt_req_w),
        .tim_int(tim_int),
        .tdr0_load(tdr0_load_w), .tdr0_wdata(tdr0_wdata_w),
        .tdr1_load(tdr1_load_w), .tdr1_wdata(tdr1_wdata_w),
        .tdr0_rdata(tdr0_rdata_w), .tdr1_rdata(tdr1_rdata_w),
        .int_set(int_set_w), .halt_ack(halt_ack_w)
    );

    assign tdr0_rdata_w = counter_val_w[31:0];
    assign tdr1_rdata_w = counter_val_w[63:32];

    // When the timer is stopped, the register block's merged TDR write data is
    // routed to the counter. Unwritten halves retain their current counter value.
    assign tdr_val_w = {
        (tdr1_load_w ? tdr1_wdata_w : tdr1_rdata_w),
        (tdr0_load_w ? tdr0_wdata_w : tdr0_rdata_w)
    };

    counter u_counter (
        .sys_rst_n(sys_rst_n), .sys_clk(sys_clk),
        .reg_addr(reg_addr_w), .reg_wdata(reg_wdata_w),
        .reg_wstrb(reg_strb_w), .wr_en(reg_wr_en_w),
        .has_error(reg_error_w),
        .timer_en(timer_en_w), .div_en(div_en_w), .div_val(div_val_w),
        .tcmp_val(tcmp_w), .tdr_val(tdr_val_w),
        .tdr_clr_req(timer_disable_evt_w),
        .dbg_mode(dbg_mode), .halt_req(halt_req_w),
        .halt_ack(halt_ack_w), .counter_val(counter_val_w),
        .cmp_match_evt(int_set_w)
    );
endmodule
