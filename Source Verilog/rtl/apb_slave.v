`timescale 1ns/1ps

// Assigned member: Hoang Trung Hieu (SE203208) - Member 2: APB Slave Interface.
// APB front end: SETUP/ACCESS handling, one ACCESS wait cycle and error response.
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
    wire access_phase;

    assign access_phase = tim_psel && tim_penable;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            access_seen <= 1'b0;
        else if (!access_phase)
            access_seen <= 1'b0;
        else
            access_seen <= 1'b1;
    end

    assign tim_pready  = sys_rst_n && access_phase && access_seen;
    assign tim_pslverr = tim_pready && tim_pwrite && reg_error;
    assign tim_prdata  = (sys_rst_n && tim_psel) ? reg_rdata : 32'b0;

    // A register write is committed only on the APB completion cycle.
    assign reg_valid = tim_pready;
    assign reg_write = tim_pwrite;
    assign reg_addr  = tim_paddr;
    assign reg_wdata = tim_pwdata;
    assign reg_strb  = tim_pstrb;
endmodule
