`timescale 1ns/1ps

// Assigned member: Hoang Quoc Tri (SE203836) - Member 3: System Integration and Verification.
// System-level IP Timer top module. Integrates APB, register bank and timer subsystem.
module timer_top (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        tim_psel,
    input  wire        tim_penable,
    input  wire        tim_pwrite,
    input  wire [11:0] tim_paddr,
    input  wire [31:0] tim_pwdata,
    input  wire [3:0]  tim_pstrb,
    output wire [31:0] tim_prdata,
    output wire        tim_pready,
    output wire        tim_pslverr,
    input  wire        dbg_mode,
    output wire        tim_int
);
    wire        reg_valid;
    wire        reg_write;
    wire [11:0] reg_addr;
    wire [31:0] reg_wdata;
    wire [3:0]  reg_strb;
    wire [31:0] reg_rdata;
    wire        reg_error;

    wire        timer_en;
    wire        div_en;
    wire [3:0]  div_val;
    wire [63:0] tcmp;
    wire        int_en;
    wire        halt_req;
    wire        tdr0_load;
    wire [31:0] tdr0_wdata;
    wire        tdr1_load;
    wire [31:0] tdr1_wdata;
    wire [63:0] counter_val;
    wire        int_set;
    wire        halt_ack;
    wire        div_tick;

    apb_slave u_apb_slave (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .tim_psel(tim_psel), .tim_penable(tim_penable), .tim_pwrite(tim_pwrite),
        .tim_paddr(tim_paddr), .tim_pwdata(tim_pwdata), .tim_pstrb(tim_pstrb),
        .tim_prdata(tim_prdata), .tim_pready(tim_pready), .tim_pslverr(tim_pslverr),
        .reg_valid(reg_valid), .reg_write(reg_write), .reg_addr(reg_addr),
        .reg_wdata(reg_wdata), .reg_strb(reg_strb),
        .reg_rdata(reg_rdata), .reg_error(reg_error)
    );

    register #(.ADDR_W(12)) u_register (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .reg_wr_en(reg_valid && reg_write), .reg_addr(reg_addr),
        .reg_wdata(reg_wdata), .reg_pstrb(reg_strb),
        .reg_rdata(reg_rdata), .reg_err(reg_error),
        .timer_en(timer_en), .div_en(div_en), .div_val(div_val), .tcmp(tcmp),
        .int_en(int_en), .halt_req(halt_req), .tim_int(tim_int),
        .tdr0_load(tdr0_load), .tdr0_wdata(tdr0_wdata),
        .tdr1_load(tdr1_load), .tdr1_wdata(tdr1_wdata),
        .tdr0_rdata(counter_val[31:0]), .tdr1_rdata(counter_val[63:32]),
        .int_set(int_set), .halt_ack(halt_ack)
    );

    counter u_counter (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .timer_en(timer_en), .div_en(div_en), .div_val(div_val),
        .dbg_mode(dbg_mode), .halt_req(halt_req), .tcmp_val(tcmp),
        .tdr0_load(tdr0_load), .tdr0_wdata(tdr0_wdata),
        .tdr1_load(tdr1_load), .tdr1_wdata(tdr1_wdata),
        .halt_ack(halt_ack), .div_tick(div_tick),
        .counter_val(counter_val), .cmp_match_evt(int_set)
    );
endmodule
