`timescale 1ns/1ps

// Member 3 integration regression: standalone verification of Member 4 timer core.
module tb_timer_core;
    reg sys_clk = 1'b0;
    reg sys_rst_n = 1'b0;
    reg timer_en = 1'b0;
    reg div_tick = 1'b0;
    reg halt_ack = 1'b0;
    reg [63:0] tcmp_val = 64'hFFFF_FFFF_FFFF_FFFF;
    reg tdr0_load = 1'b0;
    reg [31:0] tdr0_wdata = 32'd0;
    reg tdr1_load = 1'b0;
    reg [31:0] tdr1_wdata = 32'd0;
    wire [63:0] counter_val;
    wire cmp_match_evt;
    integer errors = 0;

    timer_core dut (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .timer_en(timer_en),
        .div_tick(div_tick), .halt_ack(halt_ack), .tcmp_val(tcmp_val),
        .tdr0_load(tdr0_load), .tdr0_wdata(tdr0_wdata),
        .tdr1_load(tdr1_load), .tdr1_wdata(tdr1_wdata),
        .counter_val(counter_val), .cmp_match_evt(cmp_match_evt)
    );
    always #10 sys_clk = ~sys_clk;

    task check64;
        input [8*48-1:0] label;
        input [63:0] got;
        input [63:0] expected;
        begin
            if (got !== expected) begin
                $display("[FAIL] %0s: got=%h expected=%h", label, got, expected);
                errors = errors + 1;
            end else $display("[PASS] %0s = %h", label, got);
        end
    endtask

    initial begin
        $dumpfile("results/waveforms/tb_timer_core.vcd");
        $dumpvars(0, tb_timer_core);
        repeat (2) @(posedge sys_clk);
        @(negedge sys_clk);
        sys_rst_n = 1'b1;
        #1;
        check64("Asynchronous reset clears counter", counter_val, 64'd0);

        // Preload the low and high words while stopped.
        @(negedge sys_clk); tdr0_load = 1'b1; tdr0_wdata = 32'hFFFF_FFFE;
        @(posedge sys_clk); #1; check64("TDR0 preload", counter_val, 64'h0000_0000_FFFF_FFFE);
        @(negedge sys_clk); tdr0_load = 1'b0; tdr1_load = 1'b1; tdr1_wdata = 32'h0000_0001;
        @(posedge sys_clk); #1; check64("TDR1 preload", counter_val, 64'h0000_0001_FFFF_FFFE);
        @(negedge sys_clk); tdr1_load = 1'b0; tdr1_wdata = 32'd0;

        // Full-speed increment and 64-bit carry.
        timer_en = 1'b1; div_tick = 1'b1;
        @(posedge sys_clk); #1; check64("Counter increments", counter_val, 64'h0000_0001_FFFF_FFFF);
        @(posedge sys_clk); #1; check64("Low-word overflow carries into high word", counter_val, 64'h0000_0002_0000_0000);

        // Stop edge has priority over a simultaneous preload.
        @(negedge sys_clk); timer_en = 1'b0; tdr0_load = 1'b1; tdr0_wdata = 32'h1234_5678;
        @(posedge sys_clk); #1; check64("Disable edge clears counter with priority", counter_val, 64'd0);
        @(negedge sys_clk); tdr0_load = 1'b0; div_tick = 1'b0;
        @(posedge sys_clk); #1; check64("Stopped counter holds zero without preload", counter_val, 64'd0);

        // Start, freeze during debug halt, and resume.
        @(negedge sys_clk); timer_en = 1'b1; div_tick = 1'b1;
        @(posedge sys_clk); #1; check64("Counter restarts after enable", counter_val, 64'd1);
        @(negedge sys_clk); halt_ack = 1'b1;
        repeat (3) @(posedge sys_clk);
        #1; check64("Debug halt freezes counter", counter_val, 64'd1);
        @(negedge sys_clk); halt_ack = 1'b0;
        @(posedge sys_clk); #1; check64("Counter resumes after halt", counter_val, 64'd2);

        // Compare event is asserted when the active count equals the compare value.
        tcmp_val = 64'd2; #1;
        if (cmp_match_evt !== 1'b1) begin
            $display("[FAIL] Compare event missing at match value"); errors = errors + 1;
        end else $display("[PASS] Compare event asserted at match value");

        if (errors == 0) begin
            $display("[PASS] tb_timer_core: all checks passed");
            $finish;
        end else begin
            $display("[FAIL] tb_timer_core: %0d checks failed", errors);
            $fatal(1, "tb_timer_core failed");
        end
    end

    initial begin
        #100000;
        $fatal(1, "tb_timer_core watchdog timeout");
    end
endmodule
