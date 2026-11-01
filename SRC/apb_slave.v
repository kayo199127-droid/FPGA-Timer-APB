`timescale 1ns/1ps
// ============================================================================
// Module : apb_slave
// Project: 64-bit APB Timer IP
// Purpose: APB access-phase controller with one wait state.
// Notes  : A register request is issued only in the completed access cycle.
//          Reserved register addresses are handled by the register bank.
// ============================================================================
module apb_slave (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    // APB inputs
    input  wire        tim_psel,
    input  wire        tim_penable,
    input  wire        tim_pwrite,
    input  wire [11:0] tim_paddr,
    input  wire [31:0] tim_pwdata,
    input  wire [3:0]  tim_pstrb,

    // APB outputs
    output wire [31:0] tim_prdata,
    output wire        tim_pready,
    output wire        tim_pslverr,

    // Register-bank interface
    output wire        reg_valid,
    output wire        reg_write,
    output wire [11:0] reg_addr,
    output wire [31:0] reg_wdata,
    output wire [3:0]  reg_strb,
    input  wire [31:0] reg_rdata,
    input  wire        reg_error
);

    reg access_seen;
    wire apb_access;

    assign apb_access = tim_psel && tim_penable;

    // Insert one wait state after entering the APB access phase.
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            access_seen <= 1'b0;
        else if (!apb_access)
            access_seen <= 1'b0;
        else
            access_seen <= 1'b1;
    end

    // A transfer completes when PSEL, PENABLE and PREADY are all high.
    assign tim_pready = apb_access && access_seen;
    assign tim_pslverr = tim_pready && tim_pwrite && reg_error;
    assign tim_prdata  = reg_rdata;

    assign reg_valid = tim_pready;
    assign reg_write = tim_pwrite;
    assign reg_addr  = tim_paddr;
    assign reg_wdata = tim_pwdata;
    assign reg_strb  = tim_pstrb;

endmodule
