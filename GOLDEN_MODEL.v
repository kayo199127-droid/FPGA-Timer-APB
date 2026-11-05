`timescale 1ns/1ps
// ============================================================================
// File   : GOLDEN_MODEL.v
// Module : counter_golden_model
// Purpose: Verilog version of GOLDEN_MODEL.py (class CounterGoldenModel).
//          Cycle-accurate, bit-accurate reference model of the `counter`
//          block (counter_divider + counter_core) of the FAP201 IP Timer.
//
//   GOLDEN_MODEL.py is a Python file. ModelSim (vlog) only compiles
//   Verilog/SystemVerilog, so it cannot be added to the ModelSim project.
//   This file re-implements the same behaviour in Verilog so counter_tb.v
//   can compare the RTL against the reference model on every clock cycle.
//
//   The coding style is intentionally different from counter.v: it follows
//   the step_clk() / eval_combinational() structure of the Python model
//   (combinational "next state" block + one clocked update block), so it
//   is an independent reference, not a copy of the RTL.
//
// Python -> Verilog mapping
//   eval_combinational()  -> always @* block (div_limit, match, is_halted,
//                            div_tick, and_gate_out, cmp_match_evt)
//   step_clk()            -> always @(posedge sys_clk or negedge sys_rst_n)
//   reset_async()         -> if (!sys_rst_n) branch
//   get_outputs()         -> output ports (+ gm_div_cnt / gm_div_tick debug)
//
// The model has no APB/register logic: like the Python model, it receives
// the decoded write (reg_addr, reg_wdata, reg_wstrb, wr_en, has_error) and
// the register values (timer_en, div_en, div_val, tcmp_val, tdr_val,
// dbg_mode, halt_req) directly.
// ============================================================================
module counter_golden_model (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
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
    input  wire        dbg_mode,
    input  wire        halt_req,
    output wire        halt_ack,
    output wire [63:0] counter_val,
    output wire        cmp_match_evt,
    output wire [7:0]  gm_div_cnt,     // internal_div_cnt  in the Python model
    output wire        gm_div_tick     // internal_div_tick in the Python model
);

    // ------------------------------------------------------------------
    // State registers (self.div_cnt, self.counter_val)
    // ------------------------------------------------------------------
    reg [7:0]  div_cnt;
    reg [63:0] cnt;

    // ------------------------------------------------------------------
    // eval_combinational()
    // ------------------------------------------------------------------
    reg [7:0] shifted_8bit;
    reg [7:0] div_limit;
    reg       match;
    reg       clr_div_cnt;
    reg [7:0] div_cnt_next;
    reg       is_halted;
    reg       div_tick;
    reg       and_gate_out;
    reg       cmp_evt;

    always @* begin
        // div_limit = ((1 << div_val) & 0xFF) - 1  (8-bit wrap)
        shifted_8bit = 8'd1 << div_val;          // 0 when div_val >= 8
        div_limit    = shifted_8bit - 8'd1;      // 0xFF when div_val >= 8
        match        = (div_cnt == div_limit);
        clr_div_cnt  = match || !timer_en;
        div_cnt_next = clr_div_cnt ? 8'd0 : (div_cnt + 8'd1);

        is_halted    = dbg_mode && halt_req;

        if (is_halted)
            div_tick = 1'b0;
        else if (div_en)
            div_tick = match && timer_en;
        else
            div_tick = timer_en;

        and_gate_out = div_tick && !is_halted;   // div_tick && !halt_ack
        cmp_evt      = (cnt == tcmp_val);
    end

    // ------------------------------------------------------------------
    // step_clk(): next counter value, then non-blocking update
    // ------------------------------------------------------------------
    reg [63:0] next_cnt;
    integer    b;

    always @* begin
        next_cnt = cnt;
        if (!timer_en) begin
            // 1. Timer stopped -> follow TDR
            next_cnt = tdr_val;
        end else if (wr_en && !has_error && (reg_addr == 12'h004)) begin
            // 2. Direct write to TDR0 (bits 31:0), byte strobes
            for (b = 0; b < 4; b = b + 1)
                if (reg_wstrb[b])
                    next_cnt[b*8 +: 8] = reg_wdata[b*8 +: 8];
        end else if (wr_en && !has_error && (reg_addr == 12'h008)) begin
            // 3. Direct write to TDR1 (bits 63:32), byte strobes
            for (b = 0; b < 4; b = b + 1)
                if (reg_wstrb[b])
                    next_cnt[32 + b*8 +: 8] = reg_wdata[b*8 +: 8];
        end else if (and_gate_out) begin
            // 4. Normal count-up (64-bit wrap)
            next_cnt = cnt + 64'd1;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            // reset_async()
            div_cnt <= 8'd0;
            cnt     <= 64'd0;
        end else begin
            if (!is_halted)
                div_cnt <= div_cnt_next;
            cnt <= next_cnt;
        end
    end

    // ------------------------------------------------------------------
    // get_outputs()
    // ------------------------------------------------------------------
    assign counter_val   = cnt;
    assign cmp_match_evt = cmp_evt;
    assign halt_ack      = is_halted;
    assign gm_div_cnt    = div_cnt;
    assign gm_div_tick   = div_tick;

endmodule
