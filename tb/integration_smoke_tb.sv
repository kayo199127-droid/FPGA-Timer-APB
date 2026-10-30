`timescale 1ns/1ps

module integration_smoke_tb;
    reg         sys_clk;
    reg         sys_rst_n;
    reg         tim_psel;
    reg         tim_penable;
    reg         tim_pwrite;
    reg [11:0]  tim_paddr;
    reg [31:0]  tim_pwdata;
    reg [3:0]   tim_pstrb;
    reg         dbg_mode;
    wire [31:0] tim_prdata;
    wire        tim_pready;
    wire        tim_pslverr;
    wire        tim_int;

    integer checks;
    reg [31:0] rd;
    reg [31:0] count_before;

    timer_top dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .tim_psel(tim_psel),
        .tim_penable(tim_penable),
        .tim_pwrite(tim_pwrite),
        .tim_paddr(tim_paddr),
        .tim_pwdata(tim_pwdata),
        .tim_prdata(tim_prdata),
        .tim_pstrb(tim_pstrb),
        .tim_pready(tim_pready),
        .tim_pslverr(tim_pslverr),
        .tim_int(tim_int),
        .dbg_mode(dbg_mode)
    );

    always #5 sys_clk = ~sys_clk;

    task automatic apb_write(input [11:0] addr,
                             input [31:0] data,
                             input [3:0] strb);
        integer timeout;
        begin
            @(negedge sys_clk);
            tim_psel = 1'b1;
            tim_penable = 1'b0;
            tim_pwrite = 1'b1;
            tim_paddr = addr;
            tim_pwdata = data;
            tim_pstrb = strb;

            @(negedge sys_clk);
            tim_penable = 1'b1;
            timeout = 0;
            while (tim_pready !== 1'b1 && timeout < 10) begin
                @(posedge sys_clk);
                timeout = timeout + 1;
            end
            if (tim_pready !== 1'b1)
                $fatal(1, "APB write timeout at address 0x%03h", addr);
            if (tim_pslverr !== 1'b0)
                $fatal(1, "Unexpected PSLVERR on write to 0x%03h", addr);
            @(negedge sys_clk);
            tim_psel = 1'b0;
            tim_penable = 1'b0;
            tim_pwrite = 1'b0;
            tim_pstrb = 4'b0;
        end
    endtask

    task automatic apb_read(input [11:0] addr, output [31:0] data);
        integer timeout;
        begin
            @(negedge sys_clk);
            tim_psel = 1'b1;
            tim_penable = 1'b0;
            tim_pwrite = 1'b0;
            tim_paddr = addr;
            tim_pstrb = 4'b0;

            @(negedge sys_clk);
            tim_penable = 1'b1;
            timeout = 0;
            while (tim_pready !== 1'b1 && timeout < 10) begin
                @(posedge sys_clk);
                timeout = timeout + 1;
            end
            if (tim_pready !== 1'b1)
                $fatal(1, "APB read timeout at address 0x%03h", addr);
            if (tim_pslverr !== 1'b0)
                $fatal(1, "Unexpected PSLVERR on read from 0x%03h", addr);
            data = tim_prdata;
            @(negedge sys_clk);
            tim_psel = 1'b0;
            tim_penable = 1'b0;
        end
    endtask

    task automatic expect32(input [31:0] actual,
                            input [31:0] expected,
                            input [255:0] label_text);
        begin
            checks = checks + 1;
            if (actual !== expected)
                $fatal(1, "FAIL %0s: got 0x%08h expected 0x%08h",
                       label_text, actual, expected);
            $display("PASS %0s = 0x%08h", label_text, actual);
        end
    endtask

    initial begin
        sys_clk = 1'b0;
        sys_rst_n = 1'b0;
        tim_psel = 1'b0;
        tim_penable = 1'b0;
        tim_pwrite = 1'b0;
        tim_paddr = 12'b0;
        tim_pwdata = 32'b0;
        tim_pstrb = 4'b0;
        dbg_mode = 1'b0;
        checks = 0;

        #1;
        expect32(tim_prdata, 32'h0, "PRDATA forced low during reset");
        if (tim_pready !== 1'b0)
            $fatal(1, "PREADY must remain low during reset");

        repeat (3) @(negedge sys_clk);
        sys_rst_n = 1'b1;

        apb_read(12'h000, rd);
        expect32(rd, 32'h0000_0100, "TCR reset value");
        apb_read(12'h00C, rd);
        expect32(rd, 32'hFFFF_FFFF, "TCMP0 reset value");

        // Configure a short compare interval and enable its interrupt.
        apb_write(12'h004, 32'h0000_0000, 4'hF);
        apb_write(12'h008, 32'h0000_0000, 4'hF);
        apb_write(12'h00C, 32'h0000_0005, 4'hF);
        apb_write(12'h010, 32'h0000_0000, 4'hF);
        apb_write(12'h014, 32'h0000_0001, 4'hF);
        apb_write(12'h000, 32'h0000_0001, 4'hF);

        repeat (8) @(posedge sys_clk);
        #1;
        apb_read(12'h018, rd);
        expect32(rd, 32'h0000_0001, "TISR set at compare match");
        if (tim_int !== 1'b1)
            $fatal(1, "tim_int should assert when TIER and TISR are set");

        // Disabling the timer must clear the live counter exactly once.
        apb_write(12'h000, 32'h0000_0000, 4'hF);
        repeat (2) @(posedge sys_clk);
        apb_read(12'h004, rd);
        expect32(rd, 32'h0000_0000, "counter cleared on timer disable");

        // TDR preload remains available while the timer is stopped.
        apb_write(12'h004, 32'h1234_5678, 4'hF);
        apb_read(12'h004, rd);
        expect32(rd, 32'h1234_5678, "TDR0 preload while stopped");

        // Check software W1C priority against a simultaneous hardware event.
        apb_write(12'h018, 32'h0000_0001, 4'hF);
        force dut.u_counter.u_counter_core.current_match = 1'b1;
        @(posedge sys_clk);
        #1;
        apb_write(12'h018, 32'h0000_0001, 4'hF);
        release dut.u_counter.u_counter_core.current_match;
        apb_read(12'h018, rd);
        expect32(rd, 32'h0000_0000, "W1C clear wins simultaneous compare event");

        // Debug halt is acknowledged only while dbg_mode and halt_req are high.
        apb_write(12'h000, 32'h0000_0000, 4'hF);
        apb_write(12'h004, 32'h0000_0000, 4'hF);
        apb_write(12'h00C, 32'hFFFF_FFFF, 4'hF);
        apb_write(12'h014, 32'h0000_0000, 4'hF);
        apb_write(12'h000, 32'h0000_0001, 4'hF);
        repeat (3) @(posedge sys_clk);
        dbg_mode = 1'b1;
        apb_write(12'h01C, 32'h0000_0001, 4'hF);
        repeat (2) @(posedge sys_clk);
        apb_read(12'h01C, rd);
        if (rd[1] !== 1'b1)
            $fatal(1, "THCSR.halt_ack did not assert in debug halt");
        apb_read(12'h004, count_before);
        repeat (4) @(posedge sys_clk);
        apb_read(12'h004, rd);
        expect32(rd, count_before, "counter frozen in debug halt");
        apb_write(12'h01C, 32'h0000_0000, 4'hF);
        repeat (3) @(posedge sys_clk);
        apb_read(12'h004, rd);
        if (rd <= count_before)
            $fatal(1, "counter did not resume after debug halt");
        dbg_mode = 1'b0;

        $display("ALL %0d INTEGRATION CHECKS PASSED", checks);
        $finish;
    end
endmodule
