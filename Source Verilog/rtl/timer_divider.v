`timescale 1ns/1ps

// Assigned member: Phung Van Tan (SE203222) - Member 1: Timer Divider.
// Generates a one-cycle timer enable tick; it never creates a new clock domain.
// The counter increments once every (div_val + 1) sys_clk cycles when div_en=1.
// When div_en=0, the timer runs at the full system-clock rate.
// The divider state is cleared while the timer is disabled and frozen on debug halt.
module timer_divider (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       timer_en,
    input  wire       div_en,
    input  wire [3:0] div_val,
    input  wire       dbg_mode,
    input  wire       halt_req,
    output wire       halt_ack,
    output wire       div_tick
);
    reg [3:0] div_count;
    wire halted = dbg_mode && halt_req;

    assign halt_ack = halted;
    assign div_tick = timer_en && !halted && (!div_en || (div_count == div_val));

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            div_count <= 4'd0;
        else if (!timer_en)
            div_count <= 4'd0;
        else if (!halted) begin
            if (!div_en || (div_count >= div_val))
                div_count <= 4'd0;
            else
                div_count <= div_count + 4'd1;
        end
    end
endmodule
