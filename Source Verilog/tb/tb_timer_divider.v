// Regression ownership: Member 3 (Hoang Quoc Tri); tests Member 1 timer-divider behavior.
`timescale 1ns/1ps
module tb_timer_divider;
    reg sys_clk=0, sys_rst_n=0;
    reg timer_en=0, div_en=0, dbg_mode=0, halt_req=0;
    reg [3:0] div_val=0;
    wire halt_ack, div_tick;
    integer errors=0, cycles, last_tick, found, setting_idx;
    reg [3:0] saved_phase;

    timer_divider dut (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .timer_en(timer_en),
        .div_en(div_en), .div_val(div_val), .dbg_mode(dbg_mode),
        .halt_req(halt_req), .halt_ack(halt_ack), .div_tick(div_tick)
    );
    always #10 sys_clk=~sys_clk; // 50 MHz

    task measure_period;
        input [3:0] setting;
        input integer expected_period;
        begin
            div_val=setting; cycles=0; last_tick=-1; found=0;
            while (found<4 && cycles<80) begin
                @(negedge sys_clk); #1; cycles=cycles+1;
                if (div_tick) begin
                    if (last_tick>=0 && cycles-last_tick!=expected_period) begin
                        $display("[FAIL] div_val=%0d interval=%0d expected=%0d",setting,cycles-last_tick,expected_period);
                        errors=errors+1;
                    end
                    last_tick=cycles; found=found+1;
                end
            end
            if (found<4) begin $display("[FAIL] not enough ticks for div_val=%0d",setting); errors=errors+1; end
        end
    endtask

    initial begin
        $dumpfile("results/waveforms/tb_timer_divider.vcd");
        $dumpvars(0, tb_timer_divider);
    end

    initial begin
        repeat(2) @(posedge sys_clk);
        @(negedge sys_clk); sys_rst_n=1;
        #1;
        if (div_tick!==1'b0) begin $display("[FAIL] tick asserted while timer disabled"); errors=errors+1; end

        // Full-speed operation and prescaler period checks.
        timer_en=1; div_en=0;
        repeat(3) @(negedge sys_clk); #1;
        if (div_tick!==1'b1) begin $display("[FAIL] full-speed tick not asserted"); errors=errors+1; end
        div_en=1;
        for (setting_idx=0; setting_idx<8; setting_idx=setting_idx+1)
            measure_period(setting_idx[3:0], setting_idx+1);

        // Debug halt acknowledges only in debug mode and freezes divider phase.
        dbg_mode=0; halt_req=1; #1;
        if (halt_ack!==1'b0) begin $display("[FAIL] halt acknowledged outside debug mode"); errors=errors+1; end
        dbg_mode=1; #1;
        if (halt_ack!==1'b1 || div_tick!==1'b0) begin $display("[FAIL] debug halt behavior"); errors=errors+1; end
        saved_phase = dut.div_count;
        repeat(4) @(posedge sys_clk);
        #1;
        if (dut.div_count !== saved_phase) begin $display("[FAIL] divider phase changed during halt"); errors=errors+1; end
        dbg_mode=0; #1;
        if (halt_ack!==1'b0) begin $display("[FAIL] halt_ack did not deassert"); errors=errors+1; end

        timer_en=0; #1;
        if (div_tick!==1'b0) begin $display("[FAIL] tick not suppressed while timer disabled"); errors=errors+1; end
        @(posedge sys_clk); #1;
        if (dut.div_count !== 4'd0) begin $display("[FAIL] divider phase not cleared when timer disabled"); errors=errors+1; end

        if (errors==0) begin
            $display("[PASS] tb_timer_divider: all checks passed");
            $finish;
        end else begin
            $display("[FAIL] tb_timer_divider: %0d errors",errors);
            $fatal(1, "tb_timer_divider failed");
        end
    end
endmodule
