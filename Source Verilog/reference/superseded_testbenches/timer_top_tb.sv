`timescale 1ns/1ps

module timer_top_tb;
    reg sys_clk = 1'b0;
    reg sys_rst_n = 1'b0;
    reg tim_psel = 1'b0;
    reg tim_penable = 1'b0;
    reg tim_pwrite = 1'b0;
    reg [11:0] tim_paddr = 12'b0;
    reg [31:0] tim_pwdata = 32'b0;
    reg [3:0] tim_pstrb = 4'b0;
    reg dbg_mode = 1'b0;
    wire [31:0] tim_prdata;
    wire tim_pready;
    wire tim_pslverr;
    wire tim_int;

    localparam [11:0] TCR=12'h000, TDR0=12'h004, TDR1=12'h008,
                      TCMP0=12'h00C, TCMP1=12'h010, TIER=12'h014,
                      TISR=12'h018, THCSR=12'h01C;

    integer checks = 0;
    integer failures = 0;

    timer_top #(.TCR_RESET_DIV_VAL(4'd1), .DIVIDER_EXP_OFFSET(0)) dut (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .tim_psel(tim_psel), .tim_penable(tim_penable),
        .tim_pwrite(tim_pwrite), .tim_paddr(tim_paddr),
        .tim_pwdata(tim_pwdata), .tim_pstrb(tim_pstrb),
        .tim_prdata(tim_prdata), .tim_pready(tim_pready),
        .tim_pslverr(tim_pslverr), .tim_int(tim_int), .dbg_mode(dbg_mode)
    );

    // 50 MHz system clock: 20 ns period.
    always #10 sys_clk = ~sys_clk;

    task automatic check32(input [8*80-1:0] label, input [31:0] got, input [31:0] expected);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                failures = failures + 1;
                $display("[FAIL] %0s got=0x%08h expected=0x%08h at %0t", label, got, expected, $time);
            end else begin
                $display("[PASS] %0s = 0x%08h", label, got);
            end
        end
    endtask

    task automatic check1(input [8*80-1:0] label, input got, input expected);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                failures = failures + 1;
                $display("[FAIL] %0s got=%b expected=%b at %0t", label, got, expected, $time);
            end else begin
                $display("[PASS] %0s = %b", label, got);
            end
        end
    endtask

    task automatic apb_write(
        input [11:0] addr, input [31:0] data, input [3:0] strb,
        output reg error
    );
        begin
            @(negedge sys_clk);
            tim_psel = 1'b1; tim_penable = 1'b0; tim_pwrite = 1'b1;
            tim_paddr = addr; tim_pwdata = data; tim_pstrb = strb;
            @(negedge sys_clk);
            tim_penable = 1'b1;
            while (tim_pready !== 1'b1) @(negedge sys_clk);
            error = tim_pslverr;
            @(posedge sys_clk);
            @(negedge sys_clk);
            tim_psel = 1'b0; tim_penable = 1'b0; tim_pwrite = 1'b0;
            tim_pstrb = 4'b0;
        end
    endtask

    task automatic apb_read(input [11:0] addr, output reg [31:0] data, output reg error);
        begin
            @(negedge sys_clk);
            tim_psel = 1'b1; tim_penable = 1'b0; tim_pwrite = 1'b0;
            tim_paddr = addr; tim_pstrb = 4'b0;
            @(negedge sys_clk);
            tim_penable = 1'b1;
            while (tim_pready !== 1'b1) @(negedge sys_clk);
            data = tim_prdata;
            error = tim_pslverr;
            @(posedge sys_clk);
            @(negedge sys_clk);
            tim_psel = 1'b0; tim_penable = 1'b0;
        end
    endtask

    reg [31:0] rd;
    reg err;
    reg [63:0] count_before;
    reg [63:0] count_after;
    integer i;

    initial begin
        $dumpfile("results/waveforms/timer_top_tb.vcd");
        $dumpvars(0, timer_top_tb);
        repeat (3) @(negedge sys_clk);
        sys_rst_n = 1'b1;
        repeat (2) @(posedge sys_clk);

        $display("\n=== IP TIMER INTEGRATION REGRESSION ===");
        apb_read(TCR, rd, err); check32("Integrated TCR reset", rd, 32'h0000_0100); check1("TCR reset no error", err, 1'b0);
        apb_read(TCMP0, rd, err); check32("TCMP0 reset", rd, 32'hFFFF_FFFF);
        apb_read(TCMP1, rd, err); check32("TCMP1 reset", rd, 32'hFFFF_FFFF);
        apb_read(12'h020, rd, err); check32("Reserved address reads zero", rd, 32'h0); check1("Reserved aligned access no error", err, 1'b0);

        apb_write(TCMP0, 32'h1234_5678, 4'b0011, err); check1("TCMP0 partial write accepted", err, 1'b0);
        apb_read(TCMP0, rd, err); check32("TCMP0 byte-strobe merge", rd, 32'hFFFF_5678);
        apb_write(12'h01F, 32'hDEAD_BEEF, 4'hF, err); check1("Unaligned address reports error", err, 1'b1);

        apb_write(TCR, 32'h0000_0800, 4'hF, err); check1("Forbidden divider value rejected", err, 1'b1);
        apb_read(TCR, rd, err); check32("Invalid TCR write leaves value unchanged", rd, 32'h0000_0100);

        // Preload the 64-bit counter through its two APB data registers.
        apb_write(TDR0, 32'hFFFF_FFFC, 4'hF, err); check1("TDR0 preload accepted", err, 1'b0);
        apb_write(TDR1, 32'h0000_0001, 4'hF, err); check1("TDR1 preload accepted", err, 1'b0);
        apb_read(TDR0, rd, err); check32("TDR0 preload readback", rd, 32'hFFFF_FFFC);
        apb_read(TDR1, rd, err); check32("TDR1 preload readback", rd, 32'h0000_0001);

        // Enable timer, then verify divider configuration is protected while running.
        apb_write(TCR, 32'h0000_0101, 4'hF, err); check1("Timer enable accepted", err, 1'b0);
        repeat (8) @(posedge sys_clk);
        apb_write(TCR, 32'h0000_0203, 4'hF, err); check1("Live divider reconfiguration rejected", err, 1'b1);
        apb_read(TCR, rd, err); check32("Protected TCR remains unchanged", rd, 32'h0000_0101);

        // Read current count and confirm it advanced from the preload value.
        apb_read(TDR0, rd, err); count_after[31:0] = rd;
        apb_read(TDR1, rd, err); count_after[63:32] = rd;
        check1("64-bit counter advances", count_after > 64'h0000_0001_FFFF_FFFC, 1'b1);

        // Stop timer; falling edge must clear the count. Re-enable afterwards.
        apb_write(TCR, 32'h0000_0100, 4'hF, err);
        repeat (3) @(posedge sys_clk);
        apb_read(TDR0, rd, err); count_after[31:0] = rd;
        apb_read(TDR1, rd, err); count_after[63:32] = rd;
        check32("Hardware clear lower word", count_after[31:0], 32'h0);
        check32("Hardware clear upper word", count_after[63:32], 32'h0);

        // Compare-match interrupt and W1C clear.
        apb_write(TCMP0, 32'd5, 4'hF, err);
        apb_write(TCMP1, 32'd0, 4'hF, err);
        apb_write(TIER, 32'd1, 4'hF, err);
        apb_write(TCR, 32'h0000_0101, 4'hF, err);
        i = 0;
        while ((tim_int !== 1'b1) && (i < 30)) begin @(posedge sys_clk); i = i + 1; end
        check1("Compare event raises timer interrupt", tim_int, 1'b1);
        apb_read(TISR, rd, err); check32("TISR status is latched", rd, 32'h1);
        apb_write(TISR, 32'h1, 4'b0001, err);
        apb_read(TISR, rd, err); check32("TISR W1C clears status", rd, 32'h0);
        check1("W1C deasserts timer interrupt", tim_int, 1'b0);

        // Debug halt freezes the counter; releasing the request resumes counting.
        dbg_mode = 1'b1;
        apb_write(THCSR, 32'h1, 4'hF, err);
        repeat (2) @(posedge sys_clk);
        apb_read(TDR0, rd, err); count_before[31:0] = rd;
        apb_read(TDR1, rd, err); count_before[63:32] = rd;
        check1("Debug halt acknowledgement", dut.u_counter.u_counter_divider.halt_ack, 1'b1);
        repeat (5) @(posedge sys_clk);
        apb_read(TDR0, rd, err); count_after[31:0] = rd;
        apb_read(TDR1, rd, err); count_after[63:32] = rd;
        check1("Counter is frozen during halt", count_after == count_before, 1'b1);
        apb_write(THCSR, 32'h0, 4'hF, err);
        dbg_mode = 1'b0;
        repeat (5) @(posedge sys_clk);
        apb_read(TDR0, rd, err); count_after[31:0] = rd;
        apb_read(TDR1, rd, err); count_after[63:32] = rd;
        check1("Counter resumes after debug halt", count_after > count_before, 1'b1);

        // Final summary.
        $display("\nREGRESSION SUMMARY: %0d checks, %0d failures", checks, failures);
        if (failures == 0) $display("ALL INTEGRATION CHECKS PASSED");
        else $display("INTEGRATION REGRESSION FAILED");
        #20;
        $finish;
    end

    initial begin
        #2_000_000;
        $display("[FATAL] Testbench watchdog timeout");
        $finish;
    end
endmodule
