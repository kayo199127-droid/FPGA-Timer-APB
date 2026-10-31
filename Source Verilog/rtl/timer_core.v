`timescale 1ns/1ps

// Assigned member: Le Duong Hoang Khang (SE204508) - Member 4: Timer Core.
// 64-bit count, compare-event generation and debug freeze.
module timer_core (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        timer_en,
    input  wire        div_tick,
    input  wire        halt_ack,
    input  wire [63:0] tcmp_val,
    input  wire        tdr0_load,
    input  wire [31:0] tdr0_wdata,
    input  wire        tdr1_load,
    input  wire [31:0] tdr1_wdata,
    output reg  [63:0] counter_val,
    output wire        cmp_match_evt
);
    reg timer_en_d;
    wire timer_disable_edge = timer_en_d && !timer_en;

    assign cmp_match_evt = (counter_val == tcmp_val);

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            counter_val <= 64'd0;
            timer_en_d  <= 1'b0;
        end else begin
            timer_en_d <= timer_en;

            // Clear once on the HIGH-to-LOW transition. While stopped, TDR writes
            // may preload the count; otherwise the value is held until re-enabled.
            if (timer_disable_edge) begin
                counter_val <= 64'd0;
            end else if (!halt_ack && tdr0_load) begin
                counter_val[31:0] <= tdr0_wdata;
            end else if (!halt_ack && tdr1_load) begin
                counter_val[63:32] <= tdr1_wdata;
            end else if (timer_en && div_tick && !halt_ack) begin
                counter_val <= counter_val + 64'd1;
            end
        end
    end
endmodule
