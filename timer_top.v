`timescale 1ns/1ps
// ============================================================================
// Module : timer_top
// Project: 64-bit APB Timer IP
// Purpose: Top-level integration of APB slave, register bank and timer core.
// ============================================================================
module timer_top (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    // APB slave interface
    input  wire        tim_psel,
    input  wire        tim_penable,
    input  wire        tim_pwrite,
    input  wire [11:0] tim_paddr,
    input  wire [31:0] tim_pwdata,
    input  wire [3:0]  tim_pstrb,
    output wire [31:0] tim_prdata,
    output wire        tim_pready,
    output wire        tim_pslverr,

    // System debug and interrupt interface
    input  wire        dbg_mode,
    output wire        tim_int
);

    // APB-to-register interface wires
    wire        reg_valid_w;
    wire        reg_write_w;
    wire [11:0] reg_addr_w;
    wire [31:0] reg_wdata_w;
    wire [3:0]  reg_strb_w;
    wire [31:0] reg_rdata_w;
    wire        reg_error_w;
    wire        reg_wr_en_w;

    // Register-bank control outputs
    wire        timer_en_w;
    wire        div_en_w;
    wire [3:0]  div_val_w;
    wire [63:0] tcmp_w;
    wire        int_en_w;
    wire        halt_req_w;
    wire        halt_ack_w;
    wire        int_set_w;

    // TDR readback and programmed-value storage
    wire        tdr0_load_w;
    wire [31:0] tdr0_wdata_w;
    wire        tdr1_load_w;
    wire [31:0] tdr1_wdata_w;
    wire [63:0] counter_val_w;
    reg  [63:0] tdr_shadow;

    assign reg_wr_en_w = reg_valid_w && reg_write_w;

    // ------------------------------------------------------------------------
    // APB front-end
    // ------------------------------------------------------------------------
    apb_slave u_apb_slave (
        .sys_clk    (sys_clk),
        .sys_rst_n  (sys_rst_n),
        .tim_psel   (tim_psel),
        .tim_penable(tim_penable),
        .tim_pwrite (tim_pwrite),
        .tim_paddr  (tim_paddr),
        .tim_pwdata (tim_pwdata),
        .tim_pstrb  (tim_pstrb),
        .tim_prdata (tim_prdata),
        .tim_pready (tim_pready),
        .tim_pslverr(tim_pslverr),
        .reg_valid  (reg_valid_w),
        .reg_write  (reg_write_w),
        .reg_addr   (reg_addr_w),
        .reg_wdata  (reg_wdata_w),
        .reg_strb   (reg_strb_w),
        .reg_rdata  (reg_rdata_w),
        .reg_error  (reg_error_w)
    );

    // ------------------------------------------------------------------------
    // Register bank
    // ------------------------------------------------------------------------
    timer_register u_register (
        .sys_clk    (sys_clk),
        .sys_rst_n  (sys_rst_n),
        .reg_wr_en  (reg_wr_en_w),
        .reg_addr   (reg_addr_w),
        .reg_wdata  (reg_wdata_w),
        .reg_pstrb  (reg_strb_w),
        .reg_rdata  (reg_rdata_w),
        .reg_err    (reg_error_w),
        .timer_en   (timer_en_w),
        .div_en     (div_en_w),
        .div_val    (div_val_w),
        .tcmp       (tcmp_w),
        .int_en     (int_en_w),
        .halt_req   (halt_req_w),
        .tim_int    (tim_int),
        .tdr0_load  (tdr0_load_w),
        .tdr0_wdata (tdr0_wdata_w),
        .tdr1_load  (tdr1_load_w),
        .tdr1_wdata (tdr1_wdata_w),
        .tdr0_rdata (counter_val_w[31:0]),
        .tdr1_rdata (counter_val_w[63:32]),
        .int_set    (int_set_w),
        .halt_ack   (halt_ack_w)
    );

    // Keep the programmed TDR value synchronized with every software write.
    // The counter uses this value whenever TIMER_EN is low.
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            tdr_shadow <= 64'd0;
        else begin
            if (tdr0_load_w)
                tdr_shadow[31:0] <= tdr0_wdata_w;
            if (tdr1_load_w)
                tdr_shadow[63:32] <= tdr1_wdata_w;
        end
    end

    // ------------------------------------------------------------------------
    // Timer core and prescaler
    // ------------------------------------------------------------------------
    counter u_counter (
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),
        .reg_addr     (reg_addr_w),
        .reg_wdata    (reg_wdata_w),
        .reg_wstrb    (reg_strb_w),
        .wr_en        (reg_wr_en_w),
        .has_error    (reg_error_w),
        .timer_en     (timer_en_w),
        .div_en       (div_en_w),
        .div_val      (div_val_w),
        .tcmp_val     (tcmp_w),
        .tdr_val      (tdr_shadow),
        .dbg_mode     (dbg_mode),
        .halt_req     (halt_req_w),
        .halt_ack     (halt_ack_w),
        .counter_val  (counter_val_w),
        .cmp_match_evt(int_set_w)
    );

endmodule
