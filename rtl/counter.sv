`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Counter divider. div_val selects a power-of-two period:
//   div_val=0 -> tick every sys_clk cycle (divide by 1)
//   div_val=1 -> tick every 2 cycles, ... div_val=7 -> tick every 128 cycles.
// div_en=0 bypasses the divider. Halt is effective only in debug mode.
// -----------------------------------------------------------------------------
module counter_divider (
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
    reg  [7:0] div_cnt;
    wire [7:0] div_limit;
    wire       match;
    wire       is_halted;
    wire [7:0] div_cnt_next;

    assign div_limit = (8'd1 << div_val) - 8'd1;
    assign match = (div_cnt == div_limit);
    assign is_halted = dbg_mode && halt_req;
    assign div_cnt_next = (match || !timer_en) ? 8'd0 : (div_cnt + 8'd1);

    assign halt_ack = is_halted;
    assign div_tick = !is_halted &&
                      (div_en ? (match && timer_en) : timer_en);

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            div_cnt <= 8'd0;
        else if (!is_halted)
            div_cnt <= div_cnt_next;
    end
endmodule

// -----------------------------------------------------------------------------
// 64-bit timer counter. TDR writes are supported while the timer is stopped
// through tdr_val (the register block supplies merged byte lanes), and while
// running through the APB register write path. Counting is frozen by halt_ack.
// -----------------------------------------------------------------------------
module counter_core (
    input  wire        sys_rst_n,
    input  wire        sys_clk,
    input  wire [11:0] reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire [3:0]  reg_wstrb,
    input  wire        wr_en,
    input  wire        has_error,
    input  wire        timer_en,
    input  wire        div_tick,
    input  wire        halt_ack,
    input  wire        dbg_mode,
    input  wire [63:0] tcmp_val,
    input  wire [63:0] tdr_val,
    input  wire        tdr_clr_req,
    output reg  [63:0] counter_val,
    output wire        cmp_match_evt
);
    wire and_gate_out;
    assign and_gate_out = div_tick && !halt_ack;

    // Keep the named match node because the supplied verification environment
    // can force it to inject a comparator event for coverage.
    wire current_match;
    assign current_match = (counter_val == tcmp_val);
    assign cmp_match_evt = current_match;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            counter_val <= 64'd0;
        end else if (tdr_clr_req) begin
            counter_val <= 64'd0;
        end else if (!timer_en) begin
            counter_val <= tdr_val;
        end else if (wr_en && !has_error && (reg_addr == 12'h004)) begin
            if (reg_wstrb[0]) counter_val[7:0]   <= reg_wdata[7:0];
            if (reg_wstrb[1]) counter_val[15:8]  <= reg_wdata[15:8];
            if (reg_wstrb[2]) counter_val[23:16] <= reg_wdata[23:16];
            if (reg_wstrb[3]) counter_val[31:24] <= reg_wdata[31:24];
        end else if (wr_en && !has_error && (reg_addr == 12'h008)) begin
            if (reg_wstrb[0]) counter_val[39:32] <= reg_wdata[7:0];
            if (reg_wstrb[1]) counter_val[47:40] <= reg_wdata[15:8];
            if (reg_wstrb[2]) counter_val[55:48] <= reg_wdata[23:16];
            if (reg_wstrb[3]) counter_val[63:56] <= reg_wdata[31:24];
        end else if (and_gate_out) begin
            counter_val <= counter_val + 64'd1;
        end
    end
endmodule

// -----------------------------------------------------------------------------
// Counter subsystem top: divider + 64-bit counter core.
// -----------------------------------------------------------------------------
module counter (
    input  wire        sys_rst_n,
    input  wire        sys_clk,
    input  wire [11:0] reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire [3:0]  reg_wstrb,
    input  wire        wr_en,
    input  wire        has_error,
    input  wire        timer_en,
    input  wire        div_en,
    input  wire [3:0]  div_val,
    input  wire [63:0] tcmp_val,
    input  wire [63:0] tdr_val,
    input  wire        tdr_clr_req,
    input  wire        dbg_mode,
    input  wire        halt_req,
    output wire        halt_ack,
    output wire [63:0] counter_val,
    output wire        cmp_match_evt
);
    wire tick_w;

    counter_divider u_counter_divider (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .timer_en(timer_en), .div_en(div_en), .div_val(div_val),
        .dbg_mode(dbg_mode), .halt_req(halt_req),
        .halt_ack(halt_ack), .div_tick(tick_w)
    );

    counter_core u_counter_core (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .reg_addr(reg_addr), .reg_wdata(reg_wdata), .reg_wstrb(reg_wstrb),
        .wr_en(wr_en), .has_error(has_error),
        .timer_en(timer_en), .div_tick(tick_w), .halt_ack(halt_ack),
        .dbg_mode(dbg_mode), .tcmp_val(tcmp_val), .tdr_val(tdr_val),
        .tdr_clr_req(tdr_clr_req), .counter_val(counter_val),
        .cmp_match_evt(cmp_match_evt)
    );
endmodule
