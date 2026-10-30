`timescale 1ns/1ps

// APB3-style slave front end for the Timer IP.
// One wait cycle is inserted in the ACCESS phase. A transfer is completed
// only while PSEL && PENABLE && PREADY are all high.
module apb_slave (
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

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            access_seen <= 1'b0;
        else if (!apb_access)
            access_seen <= 1'b0;
        else
            access_seen <= 1'b1;
    end

    assign tim_pready = sys_rst_n && apb_access && access_seen;
    assign tim_pslverr = tim_pready && reg_error;
    // During asynchronous reset the APB read-data bus is driven to a known zero.
    assign tim_prdata  = sys_rst_n ? reg_rdata : 32'b0;

    assign reg_valid = tim_pready;
    assign reg_write = tim_pwrite;
    assign reg_addr  = tim_paddr;
    assign reg_wdata = tim_pwdata;
    assign reg_strb  = tim_pstrb;
endmodule
