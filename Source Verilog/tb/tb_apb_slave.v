`timescale 1ns/1ps

// Member 3 integration regression: standalone verification of Member 2 APB slave.
module tb_apb_slave;
    reg sys_clk = 1'b0;
    reg sys_rst_n = 1'b0;
    reg tim_psel = 1'b0;
    reg tim_penable = 1'b0;
    reg tim_pwrite = 1'b0;
    reg [11:0] tim_paddr = 12'd0;
    reg [31:0] tim_pwdata = 32'd0;
    reg [3:0] tim_pstrb = 4'd0;
    reg [31:0] reg_rdata = 32'h1234_5678;
    reg reg_error = 1'b0;
    wire [31:0] tim_prdata;
    wire tim_pready, tim_pslverr;
    wire reg_valid, reg_write;
    wire [11:0] reg_addr;
    wire [31:0] reg_wdata;
    wire [3:0] reg_strb;
    integer errors = 0;

    apb_slave dut (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .tim_psel(tim_psel), .tim_penable(tim_penable), .tim_pwrite(tim_pwrite),
        .tim_paddr(tim_paddr), .tim_pwdata(tim_pwdata), .tim_pstrb(tim_pstrb),
        .tim_prdata(tim_prdata), .tim_pready(tim_pready), .tim_pslverr(tim_pslverr),
        .reg_valid(reg_valid), .reg_write(reg_write), .reg_addr(reg_addr),
        .reg_wdata(reg_wdata), .reg_strb(reg_strb),
        .reg_rdata(reg_rdata), .reg_error(reg_error)
    );

    always #10 sys_clk = ~sys_clk;

    task check_bit;
        input [8*48-1:0] label;
        input got;
        input expected;
        begin
            if (got !== expected) begin
                $display("[FAIL] %0s: got=%b expected=%b", label, got, expected);
                errors = errors + 1;
            end else $display("[PASS] %0s", label);
        end
    endtask

    initial begin
        $dumpfile("results/waveforms/tb_apb_slave.vcd");
        $dumpvars(0, tb_apb_slave);
        repeat (2) @(posedge sys_clk);
        @(negedge sys_clk);
        sys_rst_n = 1'b1;

        // SETUP phase must not complete an APB transfer.
        @(negedge sys_clk);
        tim_psel = 1'b1;
        tim_penable = 1'b0;
        tim_pwrite = 1'b1;
        tim_paddr = 12'h014;
        tim_pwdata = 32'hA5A5_5A5A;
        tim_pstrb = 4'hF;
        reg_error = 1'b1;
        #1;
        check_bit("PREADY remains low during SETUP", tim_pready, 1'b0);
        check_bit("reg_valid remains low during SETUP", reg_valid, 1'b0);

        // First ACCESS edge inserts one wait cycle; completion is then asserted.
        @(negedge sys_clk);
        tim_penable = 1'b1;
        #1;
        check_bit("PREADY is low at ACCESS entry", tim_pready, 1'b0);
        @(posedge sys_clk);
        #1;
        check_bit("PREADY asserts after one ACCESS wait cycle", tim_pready, 1'b1);
        check_bit("reg_valid follows completed ACCESS", reg_valid, 1'b1);
        check_bit("PSLVERR reports completed illegal write", tim_pslverr, 1'b1);
        if (reg_addr !== 12'h014 || reg_wdata !== 32'hA5A5_5A5A || reg_strb !== 4'hF || reg_write !== 1'b1) begin
            $display("[FAIL] APB write payload was not forwarded correctly");
            errors = errors + 1;
        end else $display("[PASS] APB write payload forwarding");
        @(posedge sys_clk);
        @(negedge sys_clk);
        tim_psel = 1'b0;
        tim_penable = 1'b0;
        tim_pwrite = 1'b0;
        reg_error = 1'b0;

        // A read returns the selected register data and must not raise PSLVERR.
        @(negedge sys_clk);
        tim_psel = 1'b1;
        tim_penable = 1'b0;
        tim_pwrite = 1'b0;
        tim_paddr = 12'h018;
        @(negedge sys_clk);
        tim_penable = 1'b1;
        @(posedge sys_clk);
        #1;
        check_bit("Read transfer completes", tim_pready, 1'b1);
        check_bit("Read transfer does not raise write error", tim_pslverr, 1'b0);
        if (tim_prdata !== 32'h1234_5678) begin
            $display("[FAIL] APB read data got=%h expected=12345678", tim_prdata);
            errors = errors + 1;
        end else $display("[PASS] APB read-data forwarding");
        @(posedge sys_clk);
        @(negedge sys_clk);
        tim_psel = 1'b0;
        tim_penable = 1'b0;
        #1;
        if (tim_prdata !== 32'd0) begin
            $display("[FAIL] PRDATA is not zero when peripheral is deselected");
            errors = errors + 1;
        end else $display("[PASS] PRDATA is zero when peripheral is deselected");

        // Reset while selected suppresses completion and forces read data low.
        tim_psel = 1'b1;
        tim_penable = 1'b1;
        #1;
        sys_rst_n = 1'b0;
        #1;
        check_bit("PREADY is suppressed during reset", tim_pready, 1'b0);
        if (tim_prdata !== 32'd0) begin
            $display("[FAIL] PRDATA is not zero during reset");
            errors = errors + 1;
        end else $display("[PASS] PRDATA is zero during reset");

        if (errors == 0) begin
            $display("[PASS] tb_apb_slave: all checks passed");
            $finish;
        end else begin
            $display("[FAIL] tb_apb_slave: %0d checks failed", errors);
            $fatal(1, "tb_apb_slave failed");
        end
    end

    initial begin
        #100000;
        $fatal(1, "tb_apb_slave watchdog timeout");
    end
endmodule
