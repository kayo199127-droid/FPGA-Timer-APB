`timescale 1ns/1ps

// Assigned member: Hoang Quoc Tri (SE203836) - Member 3: System Integration and Verification.
// Subsystem wrapper connecting Member 1's timer_divider to Member 4's timer_core.
// This wrapper is integration glue; the divider and core logic remain separate.
module counter (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        timer_en,
    input  wire        div_en,
    input  wire [3:0]  div_val,
    input  wire        dbg_mode,
    input  wire        halt_req,
    input  wire [63:0] tcmp_val,
    input  wire        tdr0_load,
    input  wire [31:0] tdr0_wdata,
    input  wire        tdr1_load,
    input  wire [31:0] tdr1_wdata,
    output wire        halt_ack,
    output wire        div_tick,
    output wire [63:0] counter_val,
    output wire        cmp_match_evt
);
    timer_divider u_counter_divider (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .timer_en(timer_en), .div_en(div_en), .div_val(div_val),
        .dbg_mode(dbg_mode), .halt_req(halt_req),
        .halt_ack(halt_ack), .div_tick(div_tick)
    );

    timer_core u_counter_core (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .timer_en(timer_en), .div_tick(div_tick), .halt_ack(halt_ack),
        .tcmp_val(tcmp_val),
        .tdr0_load(tdr0_load), .tdr0_wdata(tdr0_wdata),
        .tdr1_load(tdr1_load), .tdr1_wdata(tdr1_wdata),
        .counter_val(counter_val), .cmp_match_evt(cmp_match_evt)
    );
endmodule
