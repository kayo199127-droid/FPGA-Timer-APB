// Regression ownership: Member 3 (Hoang Quoc Tri); tests Member 5 register-bank behavior.
`timescale 1ns/1ps
module tb_register;
    reg sys_clk=0, sys_rst_n=0, reg_wr_en=0;
    reg [11:0] reg_addr=0;
    reg [31:0] reg_wdata=0;
    reg [3:0] reg_pstrb=0;
    wire [31:0] reg_rdata;
    wire reg_err, timer_en, div_en, int_en, halt_req, tim_int;
    wire [3:0] div_val;
    wire [63:0] tcmp;
    wire tdr0_load, tdr1_load;
    wire [31:0] tdr0_wdata, tdr1_wdata;
    reg [31:0] tdr0_rdata=0, tdr1_rdata=0;
    reg int_set=0, halt_ack=0;
    integer errors=0;

    register dut (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .reg_wr_en(reg_wr_en),
        .reg_addr(reg_addr), .reg_wdata(reg_wdata), .reg_pstrb(reg_pstrb),
        .reg_rdata(reg_rdata), .reg_err(reg_err),
        .timer_en(timer_en), .div_en(div_en), .div_val(div_val), .tcmp(tcmp),
        .int_en(int_en), .halt_req(halt_req), .tim_int(tim_int),
        .tdr0_load(tdr0_load), .tdr0_wdata(tdr0_wdata),
        .tdr1_load(tdr1_load), .tdr1_wdata(tdr1_wdata),
        .tdr0_rdata(tdr0_rdata), .tdr1_rdata(tdr1_rdata),
        .int_set(int_set), .halt_ack(halt_ack)
    );
    always #10 sys_clk=~sys_clk;

    task write_reg;
        input [11:0] a; input [31:0] v; input [3:0] s;
        begin
            @(negedge sys_clk); reg_addr=a; reg_wdata=v; reg_pstrb=s; reg_wr_en=1;
            @(posedge sys_clk); #1; reg_wr_en=0; reg_pstrb=0; reg_wdata=0;
        end
    endtask
    task check32;
        input [8*48-1:0] label; input [31:0] got; input [31:0] expected;
        begin
            if (got !== expected) begin
                $display("[FAIL] %0s got=%h expected=%h", label, got, expected); errors=errors+1;
            end
        end
    endtask
    initial begin
        $dumpfile("results/waveforms/tb_register.vcd");
        $dumpvars(0, tb_register);
    end

    initial begin
        repeat(2) @(posedge sys_clk); @(negedge sys_clk); sys_rst_n=1;
        @(negedge sys_clk); reg_addr=12'h000; #1; check32("TCR reset",reg_rdata,32'h0);
        check32("TCMP reset low",tcmp[31:0],32'hFFFF_FFFF);
        check32("TCMP reset high",tcmp[63:32],32'hFFFF_FFFF);
        write_reg(12'h000,32'h0000_0302,4'hF);
        check32("TCR legal write",{20'b0,div_val,6'b0,div_en,timer_en},32'h302);
        // Sample the combinational error during the active invalid write.
        @(negedge sys_clk); reg_addr=0; reg_wdata=32'h0000_0802; reg_pstrb=4'hF; reg_wr_en=1; #1;
        if (reg_err !== 1'b1) begin $display("[FAIL] invalid divider value not rejected"); errors=errors+1; end
        @(posedge sys_clk); #1; reg_wr_en=0;
        write_reg(12'h014,32'hFFFF_FFFF,4'hF);
        if (int_en !== 1'b1) begin $display("[FAIL] TIER bit0 not set"); errors=errors+1; end
        int_set=1; @(posedge sys_clk); #1; int_set=0;
        if (tim_int !== 1'b1) begin $display("[FAIL] interrupt enable/status gating"); errors=errors+1; end
        // Software W1C must win when it coincides with hardware set (Design SPEC).
        @(negedge sys_clk); reg_addr=12'h018; reg_wdata=1; reg_pstrb=4'hF; reg_wr_en=1; int_set=1;
        @(posedge sys_clk); #1; reg_wr_en=0; int_set=0;
        if (tim_int !== 1'b0) begin $display("[FAIL] software W1C did not take priority"); errors=errors+1; end
        if (errors==0) begin
            $display("[PASS] tb_register: all checks passed");
            $finish;
        end else begin
            $display("[FAIL] tb_register: %0d checks failed",errors);
            $fatal(1, "tb_register failed");
        end
    end
endmodule
