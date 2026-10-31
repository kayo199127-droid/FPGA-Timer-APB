`timescale 1ns/1ps

module apb_slave_tb;

    reg sys_clk;
    reg sys_rst_n;

    reg         tim_psel;
    reg         tim_penable;
    reg         tim_pwrite;
    reg [31:0]  tim_paddr;
    reg [31:0]  tim_pwdata;
    reg [3:0]   tim_pstrb;

    wire [31:0] tim_prdata;
    wire        tim_pready;
    wire        tim_pslverr;

    wire        reg_valid;
    wire        reg_write;
    wire [7:0]  reg_addr;
    wire [31:0] reg_wdata;
    wire [3:0]  reg_strb;

    reg [31:0]  reg_rdata;
    reg         reg_error;

    apb_slave uut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),

        .tim_psel(tim_psel),
        .tim_penable(tim_penable),
        .tim_pwrite(tim_pwrite),
        .tim_paddr(tim_paddr),
        .tim_pwdata(tim_pwdata),
        .tim_pstrb(tim_pstrb),

        .tim_prdata(tim_prdata),
        .tim_pready(tim_pready),
        .tim_pslverr(tim_pslverr),

        .reg_valid(reg_valid),
        .reg_write(reg_write),
        .reg_addr(reg_addr),
        .reg_wdata(reg_wdata),
        .reg_strb(reg_strb),
        .reg_rdata(reg_rdata),
        .reg_error(reg_error)
    );

    // 10 ns clock period
    always #5 sys_clk = ~sys_clk;

    initial begin
        sys_clk     = 0;
        sys_rst_n   = 0;
        tim_psel    = 0;
        tim_penable = 0;
        tim_pwrite  = 0;
        tim_paddr   = 0;
        tim_pwdata  = 0;
        tim_pstrb   = 0;
        reg_rdata   = 32'h12345678;
        reg_error   = 0;

        // Reset
        repeat (2) @(negedge sys_clk);
        sys_rst_n = 1;

        // Write transaction: address 0x04
        @(negedge sys_clk);
        tim_psel    = 1;
        tim_penable = 0;
        tim_pwrite  = 1;
        tim_paddr   = 32'h00000004;
        tim_pwdata  = 32'hAABBCCDD;
        tim_pstrb   = 4'b1111;

        // Access phase
        @(negedge sys_clk);
        tim_penable = 1;

        // ??i PREADY t? slave thay vì ??m chay (ho?c dùng wait)
        @(posedge sys_clk);
        while (!tim_pready) @(posedge sys_clk);

        // Completion
        @(negedge sys_clk);
        tim_psel    = 0;
        tim_penable = 0;

        // Read transaction: address 0x08
        @(negedge sys_clk);
        tim_psel    = 1;
        tim_penable = 0;
        tim_pwrite  = 0;
        tim_paddr   = 32'h00000008;
        tim_pstrb   = 4'b0000;

        @(negedge sys_clk);
        tim_penable = 1;

        @(posedge sys_clk);
        while (!tim_pready) @(posedge sys_clk);

        @(negedge sys_clk);
        tim_psel    = 0;
        tim_penable = 0;

        // Error response test
        @(negedge sys_clk);
        tim_psel    = 1;
        tim_penable = 0;
        tim_pwrite  = 1;
        tim_paddr   = 32'h000000FC;
        tim_pwdata  = 32'hFFFFFFFF;
        tim_pstrb   = 4'b1111;
        reg_error   = 1;

        @(negedge sys_clk);
        tim_penable = 1;

        @(posedge sys_clk);
        while (!tim_pready) @(posedge sys_clk);

        @(negedge sys_clk);
        tim_psel    = 0;
        tim_penable = 0;
        reg_error   = 0;

        repeat (2) @(negedge sys_clk);
        $finish;
    end

endmodule
