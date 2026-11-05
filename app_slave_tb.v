`timescale 1ns/1ps
// ============================================================================
// File   : app_slave_tb.v
// Purpose: Self-checking unit testbench for apb_slave (file app_slave.v).
//          The register bank is replaced by a simple model:
//            reg_rdata = 32'hA5A5_0000 | reg_addr   (to check PRDATA)
//            reg_error = driven by the testbench    (to check PSLVERR)
// Checks : setup phase, 1 wait state, completion pulse on reg_valid,
//          pass-through of address / data / strobe, PRDATA, PSLVERR on
//          write error only, back-to-back transfers, PENABLE without PSEL,
//          asynchronous reset in the access phase.
// Run in ModelSim:  do run_app_slave_tb.do
// ============================================================================
module apb_slave_tb;

    reg         sys_clk;
    reg         sys_rst_n;

    reg         tim_psel;
    reg         tim_penable;
    reg         tim_pwrite;
    reg  [11:0] tim_paddr;
    reg  [31:0] tim_pwdata;
    reg  [3:0]  tim_pstrb;

    wire [31:0] tim_prdata;
    wire        tim_pready;
    wire        tim_pslverr;

    wire        reg_valid;
    wire        reg_write;
    wire [11:0] reg_addr;
    wire [31:0] reg_wdata;
    wire [3:0]  reg_strb;
    wire [31:0] reg_rdata;
    reg         reg_error;

    // Register-bank model
    assign reg_rdata = 32'hA5A5_0000 | {20'd0, reg_addr};

    apb_slave uut (
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
        .reg_valid  (reg_valid),
        .reg_write  (reg_write),
        .reg_addr   (reg_addr),
        .reg_wdata  (reg_wdata),
        .reg_strb   (reg_strb),
        .reg_rdata  (reg_rdata),
        .reg_error  (reg_error)
    );

    // 10 ns clock
    initial sys_clk = 1'b0;
    always #5 sys_clk = ~sys_clk;

    // Name of the running test (wave radix ASCII)
    reg [8*24-1:0] test_phase;

    integer checks;
    integer errors;
    integer waits;
    integer valid_pulses;

    // Count completion pulses seen by the register bank
    always @(posedge sys_clk)
        if (reg_valid) valid_pulses = valid_pulses + 1;

    task check32(input [8*40-1:0] name, input [31:0] act, input [31:0] exp);
        begin
            checks = checks + 1;
            if (act !== exp) begin
                errors = errors + 1;
                $display("[%0t] FAIL  %0s : got %h, expected %h", $time, name, act, exp);
            end else
                $display("[%0t] PASS  %0s = %h", $time, name, act);
        end
    endtask

    task idle_bus;
        begin
            tim_psel    = 1'b0;
            tim_penable = 1'b0;
            tim_pwrite  = 1'b0;
            tim_paddr   = 12'h000;
            tim_pwdata  = 32'h0;
            tim_pstrb   = 4'b0000;
        end
    endtask

    // Full APB transfer: setup phase, access phase, wait for PREADY.
    // Checks everything that is visible in the completion cycle.
    task apb_transfer(input        write,
                      input [11:0] addr,
                      input [31:0] data,
                      input [3:0]  strb,
                      input        err,
                      input        exp_slverr);
        begin
            // Setup phase
            @(negedge sys_clk);
            tim_psel    = 1'b1;
            tim_penable = 1'b0;
            tim_pwrite  = write;
            tim_paddr   = addr;
            tim_pwdata  = data;
            tim_pstrb   = strb;
            reg_error   = err;
            #1 check32("setup: PREADY = 0", tim_pready, 1'b0);
            check32("setup: reg_valid = 0", reg_valid, 1'b0);

            // Access phase
            @(negedge sys_clk);
            tim_penable = 1'b1;
            #1 check32("access 1st cycle: PREADY = 0", tim_pready, 1'b0);
            waits = 0;
            while (!tim_pready && (waits < 10)) begin
                @(negedge sys_clk);
                #1 waits = waits + 1;
            end
            check32("wait states = 1", waits, 1);

            // Completion cycle
            check32("reg_valid in completion", reg_valid, 1'b1);
            check32("reg_write = PWRITE", reg_write, write);
            check32("reg_addr = PADDR", reg_addr, addr);
            check32("reg_wdata = PWDATA", reg_wdata, data);
            check32("reg_strb = PSTRB", reg_strb, strb);
            check32("PSLVERR", tim_pslverr, exp_slverr);
            if (!write)
                check32("PRDATA = reg_rdata", tim_prdata, 32'hA5A5_0000 | addr);

            // End of transfer
            @(negedge sys_clk);
            idle_bus;
            reg_error = 1'b0;
            #1 check32("idle: PREADY = 0", tim_pready, 1'b0);
        end
    endtask

    initial begin
        checks = 0; errors = 0; valid_pulses = 0;
        idle_bus;
        reg_error = 1'b0;
        sys_rst_n = 1'b0;

        $display("==============================================================");
        $display(" APB SLAVE UNIT TEST (app_slave.v)");
        $display("==============================================================");

        // T1 reset
        test_phase = "T1_RESET";
        repeat (2) @(negedge sys_clk);
        check32("T1 PREADY after reset", tim_pready, 1'b0);
        check32("T1 PSLVERR after reset", tim_pslverr, 1'b0);
        check32("T1 reg_valid after reset", reg_valid, 1'b0);
        sys_rst_n = 1'b1;

        // T2 write TDR0, no error
        test_phase = "T2_WRITE";
        apb_transfer(1'b1, 12'h004, 32'hAABB_CCDD, 4'b1111, 1'b0, 1'b0);

        // T3 read TDR1
        test_phase = "T3_READ";
        apb_transfer(1'b0, 12'h008, 32'h0, 4'b0000, 1'b0, 1'b0);

        // T4 write with byte strobes
        test_phase = "T4_WRITE_PSTRB";
        apb_transfer(1'b1, 12'h00C, 32'h1234_5678, 4'b0101, 1'b0, 1'b0);

        // T5 write rejected by the register bank -> PSLVERR = 1
        test_phase = "T5_WRITE_ERROR";
        apb_transfer(1'b1, 12'h000, 32'h0000_0F01, 4'b1111, 1'b1, 1'b1);

        // T6 read while reg_error = 1 -> no PSLVERR (errors are write-only)
        test_phase = "T6_READ_NO_ERROR";
        apb_transfer(1'b0, 12'h000, 32'h0, 4'b0000, 1'b1, 1'b0);

        // T7 back-to-back: PSEL stays high, PENABLE drops between transfers
        test_phase = "T7_BACK_TO_BACK";
        @(negedge sys_clk);
        tim_psel = 1'b1; tim_penable = 1'b0; tim_pwrite = 1'b1;
        tim_paddr = 12'h010; tim_pwdata = 32'hCAFE_0001; tim_pstrb = 4'hF;
        @(negedge sys_clk); tim_penable = 1'b1;
        @(negedge sys_clk);                       // PREADY = 1 (completes at next rising edge)
        @(negedge sys_clk);                       // 1st transfer completed
        tim_penable = 1'b0;                       // new setup phase, PSEL kept
        tim_paddr = 12'h014; tim_pwdata = 32'hCAFE_0002;
        #1 check32("T7 PREADY low in 2nd setup", tim_pready, 1'b0);
        @(negedge sys_clk); tim_penable = 1'b1;
        #1 check32("T7 2nd access: wait state again", tim_pready, 1'b0);
        @(negedge sys_clk);
        #1 check32("T7 2nd transfer completes", tim_pready, 1'b1);
        check32("T7 2nd reg_addr", reg_addr, 12'h014);
        @(negedge sys_clk); idle_bus;

        // T8 PENABLE without PSEL -> no transfer
        test_phase = "T8_NO_PSEL";
        valid_pulses = 0;
        @(negedge sys_clk);
        tim_psel = 1'b0; tim_penable = 1'b1; tim_pwrite = 1'b1; tim_paddr = 12'h004;
        repeat (3) @(negedge sys_clk);
        check32("T8 no reg_valid without PSEL", valid_pulses, 0);
        check32("T8 PREADY = 0 without PSEL", tim_pready, 1'b0);
        idle_bus;

        // T9 asynchronous reset in the access phase
        test_phase = "T9_ASYNC_RESET";
        @(negedge sys_clk);
        tim_psel = 1'b1; tim_pwrite = 1'b0; tim_paddr = 12'h018;
        @(negedge sys_clk); tim_penable = 1'b1;
        @(negedge sys_clk);                       // access_seen = 1 after this edge
        #1 check32("T9 PREADY before reset", tim_pready, 1'b1);
        #1 sys_rst_n = 1'b0;
        #1 check32("T9 PREADY cleared by async reset", tim_pready, 1'b0);
        @(negedge sys_clk); sys_rst_n = 1'b1; idle_bus;
        repeat (2) @(negedge sys_clk);

        test_phase = "DONE";
        $display("==============================================================");
        $display(" APB SLAVE TB SUMMARY: checks = %0d, failures = %0d", checks, errors);
        if (errors == 0) $display(" *** TEST PASSED ***");
        else             $display(" *** TEST FAILED ***");
        $display("==============================================================");
        $finish;
    end

endmodule
