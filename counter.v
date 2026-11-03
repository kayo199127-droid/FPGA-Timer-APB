`timescale 1ns/1ps
// ============================================================================
// Module : counter_divider
// Purpose: Generates a one-cycle timer tick.
// Prescaler rule (matches the project verification sequence):
//   div_en = 0                 -> one tick per system-clock cycle
//   div_en = 1, div_val = N    -> one tick every 2^N clock cycles
//   N is restricted to 0..7 by the TCR register bank.
// Debug halt is acknowledged only when both dbg_mode and halt_req are high.
// ============================================================================
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
    wire       div_match;
    wire       is_halted;

    assign is_halted = dbg_mode && halt_req;
    assign halt_ack  = is_halted;
    assign div_limit = (8'd1 << div_val) - 8'd1;
    assign div_match = (div_cnt == div_limit);

    // Match the supplied RTL and GOLDEN_MODEL.py exactly: the divider
    // phase is held whenever debug halt is active. Otherwise it clears on a
    // match or when TIMER_EN is low; DIV_EN only selects the output tick path.
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            div_cnt <= 8'd0;
        else if (!is_halted) begin
            if (div_match || !timer_en)
                div_cnt <= 8'd0;
            else
                div_cnt <= div_cnt + 8'd1;
        end
    end

    assign div_tick = timer_en && !is_halted && (!div_en || div_match);

endmodule

// ============================================================================
// Module : counter_core
// Purpose: 64-bit count-up register, TDR writes, compare-event generation.
// Compare output follows the equality level, as in the supplied reference RTL.
// ============================================================================
module counter_core (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire [11:0] reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire [3:0]  reg_wstrb,
    input  wire        wr_en,
    input  wire        has_error,
    input  wire        timer_en,
    input  wire        div_tick,
    input  wire        halt_ack,
    input  wire [63:0] tcmp_val,
    input  wire [63:0] tdr_val,
    output reg  [63:0] counter_val,
    output wire        cmp_match_evt
);

    wire count_enable;

    // The supplied counter.sv and GOLDEN_MODEL.py define this as a direct
    // equality level, not an edge-detected pulse.
    assign cmp_match_evt = (counter_val == tcmp_val);
    assign count_enable  = div_tick && !halt_ack;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            counter_val <= 64'd0;
        end else if (!timer_en) begin
            // Follow the programmed TDR shadow while the timer is stopped.
            counter_val <= tdr_val;
        end else begin
            // A completed APB write to TDR0/TDR1 updates the live counter.
            // PSTRB selects exactly which bytes are modified.
            if (wr_en && !has_error && (reg_addr == 12'h004)) begin
                if (reg_wstrb[0]) counter_val[7:0]   <= reg_wdata[7:0];
                if (reg_wstrb[1]) counter_val[15:8]  <= reg_wdata[15:8];
                if (reg_wstrb[2]) counter_val[23:16] <= reg_wdata[23:16];
                if (reg_wstrb[3]) counter_val[31:24] <= reg_wdata[31:24];
            end else if (wr_en && !has_error && (reg_addr == 12'h008)) begin
                if (reg_wstrb[0]) counter_val[39:32] <= reg_wdata[7:0];
                if (reg_wstrb[1]) counter_val[47:40] <= reg_wdata[15:8];
                if (reg_wstrb[2]) counter_val[55:48] <= reg_wdata[23:16];
                if (reg_wstrb[3]) counter_val[63:56] <= reg_wdata[31:24];
            end else if (count_enable) begin
                counter_val <= counter_val + 64'd1;
            end
        end
    end

endmodule

// ============================================================================
// Module : counter
// Purpose: Integrates the prescaler and 64-bit timer counter.
// Instance names are kept stable for convenient ModelSim waveform navigation.
// ============================================================================
module counter (
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
    output wire        cmp_match_evt
);

    wire div_tick_wire;

    counter_divider u_counter_divider (
        .sys_clk   (sys_clk),
        .sys_rst_n (sys_rst_n),
        .timer_en  (timer_en),
        .div_en    (div_en),
        .div_val   (div_val),
        .dbg_mode  (dbg_mode),
        .halt_req  (halt_req),
        .halt_ack  (halt_ack),
        .div_tick  (div_tick_wire)
    );

    counter_core u_counter_core (
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),
        .reg_addr     (reg_addr),
        .reg_wdata    (reg_wdata),
        .reg_wstrb    (reg_wstrb),
        .wr_en        (wr_en),
        .has_error    (has_error),
        .timer_en     (timer_en),
        .div_tick     (div_tick_wire),
        .halt_ack     (halt_ack),
        .tcmp_val     (tcmp_val),
        .tdr_val      (tdr_val),
        .counter_val  (counter_val),
        .cmp_match_evt(cmp_match_evt)
    );

endmodule
