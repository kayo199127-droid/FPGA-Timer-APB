`timescale 1ns/1ps
// ============================================================================
// Testbench : timer_top_tb
// DUT       : timer_top
// Coverage  : reset, APB timing, register access, byte strobes, prescaler,
//             configuration protection, 64-bit TDR, interrupt, debug halt.
// ============================================================================
module timer_top_tb;

    reg         sys_clk;
    reg         sys_rst_n;
    reg         tim_psel;
    reg         tim_penable;
    reg         tim_pwrite;
    reg  [11:0] tim_paddr;
    reg  [31:0] tim_pwdata;
    reg  [3:0]  tim_pstrb;
    reg         dbg_mode;

    wire [31:0] tim_prdata;
    wire        tim_pready;
    wire        tim_pslverr;
    wire        tim_int;

    wire [63:0] counter_value;
    wire        divider_tick;
    wire        halt_ack;

    integer checks;
    integer errors;
    integer ticks;
    reg     got_error;
    reg [31:0] read_data;
    reg [63:0] count_before;
    reg [63:0] count_after;

    localparam [11:0] ADDR_TCR   = 12'h000;
    localparam [11:0] ADDR_TDR0  = 12'h004;
    localparam [11:0] ADDR_TDR1  = 12'h008;
    localparam [11:0] ADDR_TCMP0 = 12'h00C;
    localparam [11:0] ADDR_TCMP1 = 12'h010;
    localparam [11:0] ADDR_TIER  = 12'h014;
    localparam [11:0] ADDR_TISR  = 12'h018;
    localparam [11:0] ADDR_THCSR = 12'h01C;

    timer_top dut (
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
        .dbg_mode   (dbg_mode),
        .tim_int    (tim_int)
    );

    // Hierarchical observation points are intentionally kept visible in ModelSim.
    assign counter_value = dut.u_counter.counter_val;
    assign divider_tick = dut.u_counter.u_counter_divider.div_tick;
    assign halt_ack      = dut.u_counter.halt_ack;

    // 100 MHz example clock: 10 ns period.
    initial begin
        sys_clk = 1'b0;
        forever #5 sys_clk = ~sys_clk;
    end

    task check1;
        input [255:0] test_name;
        input         actual;
        input         expected;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s: actual=%b expected=%b at %0t ns", test_name, actual, expected, $time);
            end else begin
                $display("[PASS] %0s", test_name);
            end
        end
    endtask

    task check32;
        input [255:0] test_name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s: actual=0x%08h expected=0x%08h at %0t ns", test_name, actual, expected, $time);
            end else begin
                $display("[PASS] %0s: 0x%08h", test_name, actual);
            end
        end
    endtask

    task check64;
        input [255:0] test_name;
        input [63:0]  actual;
        input [63:0]  expected;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s: actual=0x%016h expected=0x%016h at %0t ns", test_name, actual, expected, $time);
            end else begin
                $display("[PASS] %0s: 0x%016h", test_name, actual);
            end
        end
    endtask

    task apb_write;
        input  [11:0] address;
        input  [31:0] data;
        input  [3:0]  strobe;
        output        response_error;
        begin
            // SETUP phase
            @(negedge sys_clk);
            tim_psel    = 1'b1;
            tim_penable = 1'b0;
            tim_pwrite  = 1'b1;
            tim_paddr   = address;
            tim_pwdata  = data;
            tim_pstrb   = strobe;

            // ACCESS phase; wait for the slave's completion response.
            @(negedge sys_clk);
            tim_penable = 1'b1;
            while (tim_pready !== 1'b1)
                @(negedge sys_clk);
            response_error = tim_pslverr;

            // The register write is sampled on the clock edge following PREADY.
            @(negedge sys_clk);
            tim_psel    = 1'b0;
            tim_penable = 1'b0;
            tim_pwrite  = 1'b0;
            tim_pstrb   = 4'b0000;
            tim_pwdata  = 32'b0;
        end
    endtask

    task apb_read;
        input  [11:0] address;
        output [31:0] data;
        output        response_error;
        begin
            // SETUP phase
            @(negedge sys_clk);
            tim_psel    = 1'b1;
            tim_penable = 1'b0;
            tim_pwrite  = 1'b0;
            tim_paddr   = address;
            tim_pwdata  = 32'b0;
            tim_pstrb   = 4'b0000;

            // ACCESS phase
            @(negedge sys_clk);
            tim_penable = 1'b1;
            while (tim_pready !== 1'b1)
                @(negedge sys_clk);
            data = tim_prdata;
            response_error = tim_pslverr;

            @(negedge sys_clk);
            tim_psel    = 1'b0;
            tim_penable = 1'b0;
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;
        ticks  = 0;
        sys_rst_n  = 1'b0;
        tim_psel   = 1'b0;
        tim_penable= 1'b0;
        tim_pwrite = 1'b0;
        tim_paddr  = 12'b0;
        tim_pwdata = 32'b0;
        tim_pstrb  = 4'b0;
        dbg_mode  = 1'b0;
        got_error = 1'b0;
        read_data = 32'b0;

        $display("============================================================");
        $display(" TIMER IP SELF-CHECKING TESTBENCH START");
        $display("============================================================");

        repeat (3) @(posedge sys_clk);
        @(negedge sys_clk);
        sys_rst_n = 1'b1;

        // -------------------------------------------------------------------
        // TEST 1: Reset values
        // -------------------------------------------------------------------
        $display("\n[TEST 1] Reset values and default register map");
        apb_read(ADDR_TCR, read_data, got_error);
        check32("TCR reset", read_data, 32'h0000_0000);
        apb_read(ADDR_TDR0, read_data, got_error);
        check32("TDR0 reset", read_data, 32'h0000_0000);
        apb_read(ADDR_TDR1, read_data, got_error);
        check32("TDR1 reset", read_data, 32'h0000_0000);
        apb_read(ADDR_TCMP0, read_data, got_error);
        check32("TCMP0 reset", read_data, 32'hFFFF_FFFF);
        apb_read(ADDR_TCMP1, read_data, got_error);
        check32("TCMP1 reset", read_data, 32'hFFFF_FFFF);
        apb_read(ADDR_TIER, read_data, got_error);
        check32("TIER reset", read_data, 32'h0000_0000);
        apb_read(ADDR_TISR, read_data, got_error);
        check32("TISR reset", read_data, 32'h0000_0000);
        apb_read(ADDR_THCSR, read_data, got_error);
        check32("THCSR reset", read_data, 32'h0000_0000);
        check1("Interrupt inactive after reset", tim_int, 1'b0);

        // -------------------------------------------------------------------
        // TEST 2: APB byte strobes and reserved addresses
        // -------------------------------------------------------------------
        $display("\n[TEST 2] APB access, byte strobes and reserved addresses");
        apb_write(ADDR_TCMP0, 32'h1234_5678, 4'b0001, got_error);
        check1("TCMP0 byte-0 write has no error", got_error, 1'b0);
        apb_read(ADDR_TCMP0, read_data, got_error);
        check32("TCMP0 after byte-0 write", read_data, 32'hFFFF_FF78);
        apb_write(ADDR_TCMP0, 32'h1234_5678, 4'b0011, got_error);
        apb_read(ADDR_TCMP0, read_data, got_error);
        check32("TCMP0 after byte-0/1 write", read_data, 32'hFFFF_5678);
        apb_write(ADDR_TCMP0, 32'h1234_5678, 4'b1111, got_error);
        apb_read(ADDR_TCMP0, read_data, got_error);
        check32("TCMP0 full-word write", read_data, 32'h1234_5678);
        apb_write(12'h020, 32'hDEAD_BEEF, 4'hF, got_error);
        check1("Reserved write is ignored without error", got_error, 1'b0);
        apb_read(12'h020, read_data, got_error);
        check32("Reserved address reads as zero", read_data, 32'h0000_0000);

        // -------------------------------------------------------------------
        // TEST 3: TCR validation and divider configuration lock
        // -------------------------------------------------------------------
        $display("\n[TEST 3] TCR divider validation and active configuration lock");
        apb_write(ADDR_TCR, 32'h0000_0302, 4'hF, got_error);
        check1("Valid prescaler configuration accepted", got_error, 1'b0);
        apb_read(ADDR_TCR, read_data, got_error);
        check32("TCR configured to DIV_EN=1, DIV_VAL=3", read_data, 32'h0000_0302);

        apb_write(ADDR_TCR, 32'h0000_0802, 4'hF, got_error);
        check1("DIV_VAL=8 is rejected", got_error, 1'b1);
        apb_read(ADDR_TCR, read_data, got_error);
        check32("TCR unchanged after rejected DIV_VAL", read_data, 32'h0000_0302);

        apb_write(ADDR_TCR, 32'h0000_0003, 4'b0001, got_error);
        check1("Timer enable can be set with byte-0 access", got_error, 1'b0);
        apb_write(ADDR_TCR, 32'h0000_0200, 4'b0010, got_error);
        check1("Prescaler change is rejected while timer is active", got_error, 1'b1);
        apb_write(ADDR_TCR, 32'h0000_0002, 4'b0001, got_error);
        check1("Timer can be stopped without changing prescaler", got_error, 1'b0);
        apb_write(ADDR_TCR, 32'h0000_0400, 4'b0010, got_error);
        check1("Prescaler can be changed after timer stops", got_error, 1'b0);
        apb_read(ADDR_TCR, read_data, got_error);
        check32("TCR after unlocked update", read_data, 32'h0000_0402);

        // -------------------------------------------------------------------
        // TEST 4: 64-bit TDR and split-word access
        // -------------------------------------------------------------------
        $display("\n[TEST 4] 64-bit TDR low/high word access");
        apb_write(ADDR_TDR0, 32'h89AB_CDEF, 4'hF, got_error);
        apb_write(ADDR_TDR1, 32'h0123_4567, 4'hF, got_error);
        apb_read(ADDR_TDR0, read_data, got_error);
        check32("TDR0 programmed low word", read_data, 32'h89AB_CDEF);
        apb_read(ADDR_TDR1, read_data, got_error);
        check32("TDR1 programmed high word", read_data, 32'h0123_4567);
        check64("Combined 64-bit TDR", counter_value, 64'h0123_4567_89AB_CDEF);

        // -------------------------------------------------------------------
        // TEST 5: Compare interrupt and RW1C status handling
        // -------------------------------------------------------------------
        $display("\n[TEST 5] Compare event, TISR RW1C and interrupt output");
        apb_write(ADDR_TDR0, 32'h0000_0000, 4'hF, got_error);
        apb_write(ADDR_TDR1, 32'h0000_0000, 4'hF, got_error);
        apb_write(ADDR_TCMP0, 32'h0000_0005, 4'hF, got_error);
        apb_write(ADDR_TCMP1, 32'h0000_0000, 4'hF, got_error);
        apb_write(ADDR_TIER, 32'h0000_0001, 4'hF, got_error);
        apb_write(ADDR_TCR, 32'h0000_0401, 4'hF, got_error);
        repeat (10) @(negedge sys_clk);
        apb_read(ADDR_TISR, read_data, got_error);
        check32("TISR set after compare match", read_data, 32'h0000_0001);
        check1("tim_int asserted when TIER and TISR are set", tim_int, 1'b1);
        apb_write(ADDR_TISR, 32'h0000_0001, 4'b0010, got_error);
        apb_read(ADDR_TISR, read_data, got_error);
        check32("W1C on wrong byte lane preserves status", read_data, 32'h0000_0001);
        apb_write(ADDR_TISR, 32'h0000_0001, 4'b0001, got_error);
        apb_read(ADDR_TISR, read_data, got_error);
        check32("TISR cleared by byte-0 write-one-to-clear", read_data, 32'h0000_0000);
        check1("tim_int deasserted after W1C", tim_int, 1'b0);

        // -------------------------------------------------------------------
        // TEST 6: Debug halt is qualified by dbg_mode
        // -------------------------------------------------------------------
        $display("\n[TEST 6] Debug halt request and counter freeze/resume");
        apb_write(ADDR_THCSR, 32'h0000_0001, 4'hF, got_error);
        check1("Halt request alone does not halt outside debug mode", halt_ack, 1'b0);
        dbg_mode = 1'b1;
        #1;
        check1("Halt is acknowledged in debug mode", halt_ack, 1'b1);
        count_before = counter_value;
        repeat (5) @(posedge sys_clk);
        #1;
        count_after = counter_value;
        check64("Counter remains frozen while halt is acknowledged", count_after, count_before);
        apb_read(ADDR_THCSR, read_data, got_error);
        check32("THCSR reports halt_req and halt_ack", read_data, 32'h0000_0003);
        dbg_mode = 1'b0;
        repeat (3) @(posedge sys_clk);
        #1;
        count_after = counter_value;
        checks = checks + 1;
        if (count_after <= count_before) begin
            errors = errors + 1;
            $display("[FAIL] Counter resumes after leaving debug mode");
        end else begin
            $display("[PASS] Counter resumes after leaving debug mode");
        end
        apb_write(ADDR_THCSR, 32'h0000_0000, 4'hF, got_error);
        check1("Software clears halt_req", halt_ack, 1'b0);

        // -------------------------------------------------------------------
        // TEST 7: Prescaler period (2^DIV_VAL) and tick count
        // -------------------------------------------------------------------
        $display("\n[TEST 7] Prescaler period and generated tick pulses");
        apb_write(ADDR_TCR, 32'h0000_0400, 4'hF, got_error); // stop, keep div_val=4
        apb_write(ADDR_TDR0, 32'h0000_0000, 4'hF, got_error);
        apb_write(ADDR_TDR1, 32'h0000_0000, 4'hF, got_error);
        apb_write(ADDR_TCR, 32'h0000_0202, 4'hF, got_error); // DIV_EN=1, DIV_VAL=2
        apb_write(ADDR_TCR, 32'h0000_0003, 4'b0001, got_error); // start
        ticks = 0;
        repeat (16) begin
            @(negedge sys_clk);
            if (divider_tick === 1'b1)
                ticks = ticks + 1;
        end
        checks = checks + 1;
        if (ticks != 4) begin
            errors = errors + 1;
            $display("[FAIL] DIV_VAL=2 should produce 4 ticks in 16 clock cycles; got %0d", ticks);
        end else begin
            $display("[PASS] DIV_VAL=2 produces 4 ticks in 16 clock cycles");
        end
        check64("Counter increments once per prescaler tick", counter_value, 64'd4);

        // -------------------------------------------------------------------
        // TEST 8: Asynchronous reset clears the active design
        // -------------------------------------------------------------------
        $display("\n[TEST 8] Asynchronous reset recovery");
        #2 sys_rst_n = 1'b0;
        #1;
        check1("APB PREADY clears during reset", tim_pready, 1'b0);
        check1("Interrupt clears during reset", tim_int, 1'b0);
        check1("Halt acknowledgement clears during reset", halt_ack, 1'b0);
        repeat (2) @(posedge sys_clk);
        @(negedge sys_clk);
        sys_rst_n = 1'b1;
        apb_read(ADDR_TCR, read_data, got_error);
        check32("TCR returns to reset after asynchronous reset", read_data, 32'h0000_0000);
        apb_read(ADDR_TCMP0, read_data, got_error);
        check32("TCMP0 returns to reset after asynchronous reset", read_data, 32'hFFFF_FFFF);

        // -------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------
        $display("\n============================================================");
        $display(" TIMER IP TEST SUMMARY: %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: TEST FAILED - REVIEW THE LOG ABOVE");
        $display("============================================================");
        $finish;
    end

    // Watchdog prevents an accidental infinite wait in an APB task.
    initial begin
        #100000;
        $display("[WATCHDOG] Simulation timeout");
        $finish;
    end

endmodule
