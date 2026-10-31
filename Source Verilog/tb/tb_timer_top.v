// Member 3 (Hoang Quoc Tri): integrated system-level regression.
`timescale 1ns/1ps
module tb_timer_top;
    reg sys_clk=0, sys_rst_n=0;
    reg tim_psel=0, tim_penable=0, tim_pwrite=0;
    reg [11:0] tim_paddr=0;
    reg [31:0] tim_pwdata=0;
    reg [3:0] tim_pstrb=0;
    reg dbg_mode=0;
    wire [31:0] tim_prdata;
    wire tim_pready, tim_pslverr, tim_int;
    integer errors=0;
    integer last_error=0;
    integer i, cycle_no, last_tick, tick_count;
    reg [31:0] rd;
    reg [63:0] saved_count;

    timer_top dut (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .tim_psel(tim_psel), .tim_penable(tim_penable), .tim_pwrite(tim_pwrite),
        .tim_paddr(tim_paddr), .tim_pwdata(tim_pwdata), .tim_pstrb(tim_pstrb),
        .tim_prdata(tim_prdata), .tim_pready(tim_pready), .tim_pslverr(tim_pslverr),
        .dbg_mode(dbg_mode), .tim_int(tim_int)
    );
    always #10 sys_clk=~sys_clk; // 50 MHz, 20 ns period

    task apb_write;
        input [11:0] addr; input [31:0] data; input [3:0] strb;
        begin
            @(negedge sys_clk);
            tim_psel=1; tim_penable=0; tim_pwrite=1;
            tim_paddr=addr; tim_pwdata=data; tim_pstrb=strb;
            @(negedge sys_clk); tim_penable=1;
            wait (tim_pready === 1'b1);
            #1; // Allow combinational PSLVERR/reg_error to settle after PREADY rises.
            last_error=tim_pslverr;
            @(posedge sys_clk);
            @(negedge sys_clk);
            tim_psel=0; tim_penable=0; tim_pwrite=0; tim_pstrb=0; tim_pwdata=0;
        end
    endtask

    task apb_read;
        input [11:0] addr; output [31:0] data;
        begin
            @(negedge sys_clk);
            tim_psel=1; tim_penable=0; tim_pwrite=0;
            tim_paddr=addr; tim_pstrb=0;
            @(negedge sys_clk); tim_penable=1;
            wait (tim_pready === 1'b1);
            #1; // Allow the selected register read mux to settle.
            data=tim_prdata;
            @(posedge sys_clk);
            @(negedge sys_clk);
            tim_psel=0; tim_penable=0;
        end
    endtask

    task check32;
        input [8*56-1:0] label; input [31:0] got; input [31:0] expected;
        begin
            if (got !== expected) begin
                $display("[FAIL] %0s got=0x%08h expected=0x%08h @%0t",label,got,expected,$time);
                errors=errors+1;
            end else $display("[PASS] %0s = 0x%08h",label,got);
        end
    endtask
    task check64;
        input [8*56-1:0] label; input [63:0] got; input [63:0] expected;
        begin
            if (got !== expected) begin
                $display("[FAIL] %0s got=0x%016h expected=0x%016h @%0t",label,got,expected,$time);
                errors=errors+1;
            end else $display("[PASS] %0s = 0x%016h",label,got);
        end
    endtask

    // Prevent a broken APB handshake from hanging the regression indefinitely.
    initial begin
        #2_000_000;
        $fatal(1, "tb_timer_top watchdog timeout");
    end

    initial begin
        $dumpfile("results/waveforms/tb_timer_top.vcd");
        $dumpvars(0,tb_timer_top);
        // Asynchronous reset must suppress APB completion and force PRDATA to zero.
        tim_psel=1'b1; tim_penable=1'b1; #1;
        if (tim_pready !== 1'b0) begin $display("[FAIL] PREADY asserted during reset"); errors=errors+1; end
        if (tim_prdata !== 32'b0) begin $display("[FAIL] PRDATA not zero during reset"); errors=errors+1; end
        tim_psel=1'b0; tim_penable=1'b0;
        repeat(3) @(posedge sys_clk);
        @(negedge sys_clk); sys_rst_n=1;

        // PRDATA is forced to zero while the peripheral is not selected.
        #1; check32("PRDATA while not selected",tim_prdata,32'b0);

        // APB setup must not complete; ACCESS completes after the inserted wait state.
        @(negedge sys_clk); tim_psel=1; tim_penable=0; tim_pwrite=0; tim_paddr=12'h000;
        @(negedge sys_clk); tim_penable=1;
        if (tim_pready !== 1'b0) begin $display("[FAIL] PREADY asserted before ACCESS wait cycle"); errors=errors+1; end
        @(posedge sys_clk); #1;
        if (tim_pready !== 1'b1) begin $display("[FAIL] PREADY did not assert after wait cycle"); errors=errors+1; end
        @(posedge sys_clk);
        @(negedge sys_clk); tim_psel=0; tim_penable=0;

        apb_read(12'h000,rd); check32("TCR reset",rd,32'h0000_0000);
        apb_read(12'h003,rd); check32("Unaligned address uses word-aligned register address",rd,32'h0000_0000);
        apb_read(12'h00C,rd); check32("TCMP0 reset",rd,32'hFFFF_FFFF);
        apb_read(12'h010,rd); check32("TCMP1 reset",rd,32'hFFFF_FFFF);
        apb_read(12'h014,rd); check32("TIER reset",rd,32'h0);
        apb_read(12'h018,rd); check32("TISR reset",rd,32'h0);
        apb_read(12'h01C,rd); check32("THCSR reset",rd,32'h0);

        // Byte access to compare register.
        apb_write(12'h00C,32'hAABB_CCDD,4'b0101);
        apb_read(12'h00C,rd); check32("TCMP0 byte strobes",rd,32'hFFBB_FFDD);

        // Invalid divider values (8..15) must be rejected without changing TCR.
        apb_write(12'h000,32'h0000_0802,4'hF);
        if (last_error !== 1) begin $display("[FAIL] PSLVERR for forbidden div_val"); errors=errors+1; end
        apb_read(12'h000,rd); check32("TCR unchanged after invalid write",rd,32'h0);

        // Reserved address: read-as-zero and write ignored.
        apb_write(12'h020,32'hFFFF_FFFF,4'hF);
        if (last_error !== 0) begin $display("[FAIL] reserved write unexpectedly errored"); errors=errors+1; end
        apb_read(12'h020,rd); check32("Reserved address RAZ",rd,32'h0);

        // Preload 64-bit counter while stopped; then test carry across bit 31.
        apb_write(12'h004,32'hFFFF_FFFE,4'hF);
        apb_write(12'h008,32'h0000_0000,4'hF);
        apb_write(12'h000,32'h0000_0001,4'hF); // timer_en=1, divider disabled => full speed
        repeat(2) @(posedge sys_clk); #1;
        check64("64-bit carry",dut.counter_val,64'h0000_0001_0000_0000);

        // Divider control: div_en=1, div_val=1 => one tick every two clocks.
        apb_write(12'h000,32'h0000_0000,4'hF); // stop timer first
        repeat(2) @(posedge sys_clk);
        apb_write(12'h000,32'h0000_0102,4'hF); // div_en=1, div_val=1, timer off
        apb_write(12'h000,32'h0000_0103,4'hF); // timer on
        cycle_no=0; last_tick=-1; tick_count=0;
        while (tick_count < 3 && cycle_no < 20) begin
            @(negedge sys_clk); #1; cycle_no=cycle_no+1;
            if (dut.div_tick) begin
                if (last_tick>=0 && cycle_no-last_tick!=2) begin
                    $display("[FAIL] integrated divider interval %0d, expected 2",cycle_no-last_tick);
                    errors=errors+1;
                end
                last_tick=cycle_no; tick_count=tick_count+1;
            end
        end
        if (tick_count!=3) begin $display("[FAIL] integrated divider did not produce 3 ticks"); errors=errors+1; end

        // Divider configuration is locked while timer is running.
        apb_write(12'h000,32'h0000_0203,4'hF);
        if (last_error !== 1) begin $display("[FAIL] divider write protection missing"); errors=errors+1; end

        // Stop event clears the 64-bit counter; later preload is retained while stopped.
        apb_write(12'h000,32'h0000_0102,4'hF);
        repeat(2) @(posedge sys_clk); #1;
        check64("Counter cleared on timer disable",dut.counter_val,64'd0);
        // TDR byte writes update only selected byte lanes while the timer is stopped.
        apb_write(12'h004,32'hAABB_CCDD,4'hF);
        apb_write(12'h004,32'h1122_3344,4'b0101);
        apb_read(12'h004,rd); check32("TDR0 byte-strobe merge",rd,32'hAA22_CC44);
        apb_write(12'h004,32'h0000_0005,4'hF);
        check64("Counter preload while stopped",dut.counter_val,64'd5);

        // Compare/interrupt path.
        apb_write(12'h00C,32'h0000_000A,4'hF);
        apb_write(12'h010,32'h0000_0000,4'hF);
        apb_write(12'h014,32'h0000_0001,4'hF);
        apb_write(12'h000,32'h0000_0001,4'hF); // start at preloaded 5
        repeat(8) @(posedge sys_clk); #1;
        apb_read(12'h018,rd);
        if (rd[0] !== 1'b1 || tim_int !== 1'b1) begin
            $display("[FAIL] compare interrupt status/output: TISR=%h tim_int=%b",rd,tim_int);
            errors=errors+1;
        end else $display("[PASS] compare interrupt asserted");

        // W1C status clear.
        apb_write(12'h018,32'h0000_0001,4'hF);
        apb_read(12'h018,rd); check32("TISR W1C",rd,32'h0);
        if (tim_int !== 1'b0) begin $display("[FAIL] tim_int did not clear after W1C"); errors=errors+1; end

        // Debug halt only acknowledges inside debug mode and freezes the count.
        dbg_mode=1;
        apb_write(12'h01C,32'h0000_0001,4'hF);
        repeat(2) @(posedge sys_clk); #1;
        saved_count=dut.counter_val;
        repeat(5) @(posedge sys_clk);
        check64("Counter frozen in debug halt",dut.counter_val,saved_count);
        apb_read(12'h01C,rd); check32("THCSR halt_ack",rd,32'h3);
        apb_write(12'h01C,32'h0000_0000,4'hF);
        repeat(2) @(posedge sys_clk); #1;
        if (dut.counter_val == saved_count) begin $display("[FAIL] counter did not resume"); errors=errors+1; end
        else $display("[PASS] counter resumed after halt request cleared");
        dbg_mode=0;

        apb_write(12'h000,32'h0000_0000,4'hF);
        repeat(2) @(posedge sys_clk); #1;
        check64("Final hardware clear",dut.counter_val,64'd0);

        if (errors==0) begin
            $display("\n[PASS] tb_timer_top: all checks passed");
            $finish;
        end else begin
            $display("\n[FAIL] tb_timer_top: %0d checks failed",errors);
            $fatal(1, "tb_timer_top failed");
        end
    end
endmodule
