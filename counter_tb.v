`timescale 1ns/1ps
// ============================================================================
// File   : counter_tb.v
// Purpose: Self-checking unit testbench for `counter` (counter.v)
//          = counter_divider (prescaler 2^N) + counter_core (64-bit counter).
//
// Two kinds of checks run at the same time:
//   1. Directed tests (T1..T13) with hand-computed expected values.
//   2. Scoreboard: the RTL is compared on EVERY clock cycle with the
//      reference model counter_golden_model (GOLDEN_MODEL.v, the Verilog
//      version of GOLDEN_MODEL.py): counter_val, cmp_match_evt, halt_ack,
//      div_cnt and div_tick must be identical. T14 adds 3000 random cycles.
//
// Timing convention (same as timer_top_tb): inputs change on the falling
// edge, the DUT samples on the rising edge, results are read on the next
// falling edge. Clock = 100 MHz (10 ns).
//
// Compile / run in ModelSim:  do run_counter.do
// Expected end of Transcript:
//   COUNTER TB SUMMARY: directed ... failures = 0, scoreboard ... mismatches = 0
//   *** TEST PASSED ***
// ============================================================================
module counter_tb;

    // ------------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------------
    reg sys_clk;
    reg sys_rst_n;

    initial sys_clk = 1'b0;
    always #5 sys_clk = ~sys_clk;

    // ------------------------------------------------------------------
    // DUT inputs
    // ------------------------------------------------------------------
    reg  [11:0] reg_addr;
    reg  [31:0] reg_wdata;
    reg  [3:0]  reg_wstrb;
    reg         wr_en;
    reg         has_error;
    reg         timer_en;
    reg         div_en;
    reg  [3:0]  div_val;
    reg  [63:0] tcmp_val;
    reg  [63:0] tdr_val;
    reg         dbg_mode;
    reg         halt_req;

    // ------------------------------------------------------------------
    // DUT outputs
    // ------------------------------------------------------------------
    wire        halt_ack;
    wire [63:0] counter_val;
    wire        cmp_match_evt;

    // Golden model outputs
    wire        gm_halt_ack;
    wire [63:0] gm_counter_val;
    wire        gm_cmp_match_evt;
    wire [7:0]  gm_div_cnt;
    wire        gm_div_tick;

    // ------------------------------------------------------------------
    // Device under test
    // ------------------------------------------------------------------
    counter dut (
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),
        .reg_addr     (reg_addr),
        .reg_wdata    (reg_wdata),
        .reg_wstrb    (reg_wstrb),
        .wr_en        (wr_en),
        .has_error    (has_error),
        .timer_en     (timer_en),
        .div_en       (div_en),
        .div_val      (div_val),
        .tcmp_val     (tcmp_val),
        .tdr_val      (tdr_val),
        .dbg_mode     (dbg_mode),
        .halt_req     (halt_req),
        .halt_ack     (halt_ack),
        .counter_val  (counter_val),
        .cmp_match_evt(cmp_match_evt)
    );

    // ------------------------------------------------------------------
    // Reference model (GOLDEN_MODEL.v)
    // ------------------------------------------------------------------
    counter_golden_model gm (
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),
        .reg_addr     (reg_addr),
        .reg_wdata    (reg_wdata),
        .reg_wstrb    (reg_wstrb),
        .wr_en        (wr_en),
        .has_error    (has_error),
        .timer_en     (timer_en),
        .div_en       (div_en),
        .div_val      (div_val),
        .tcmp_val     (tcmp_val),
        .tdr_val      (tdr_val),
        .dbg_mode     (dbg_mode),
        .halt_req     (halt_req),
        .halt_ack     (gm_halt_ack),
        .counter_val  (gm_counter_val),
        .cmp_match_evt(gm_cmp_match_evt),
        .gm_div_cnt   (gm_div_cnt),
        .gm_div_tick  (gm_div_tick)
    );

    // Internal DUT signals (hierarchical probes, also shown in the wave)
    wire [7:0] dut_div_cnt  = dut.u_counter_divider.div_cnt;
    wire       dut_div_tick = dut.div_tick_wire;

    // Name of the running test, shown in the wave window (radix ASCII)
    reg [8*24-1:0] test_phase;

    // ------------------------------------------------------------------
    // Bookkeeping
    // ------------------------------------------------------------------
    integer checks;
    integer errors;
    integer sb_cycles;
    integer sb_errors;
    integer seed;
    integer i;
    integer n;
    integer cycles;
    integer cmp_hits;
    reg [63:0] snap;

    // ------------------------------------------------------------------
    // Scoreboard: compare RTL vs golden model 2 ns after every rising edge
    // ------------------------------------------------------------------
    always @(posedge sys_clk) begin
        #2;
        sb_cycles = sb_cycles + 1;
        if ((counter_val   !== gm_counter_val)   ||
            (cmp_match_evt !== gm_cmp_match_evt) ||
            (halt_ack      !== gm_halt_ack)      ||
            (dut_div_cnt   !== gm_div_cnt)       ||
            (dut_div_tick  !== gm_div_tick)) begin
            sb_errors = sb_errors + 1;
            if (sb_errors <= 10)
                $display("[%0t] SCOREBOARD MISMATCH (%0s): cnt dut=%h gm=%h | cmp %b/%b | halt %b/%b | div_cnt %0d/%0d | tick %b/%b",
                         $time, test_phase, counter_val, gm_counter_val,
                         cmp_match_evt, gm_cmp_match_evt, halt_ack, gm_halt_ack,
                         dut_div_cnt, gm_div_cnt, dut_div_tick, gm_div_tick);
        end
    end

    // ------------------------------------------------------------------
    // Check helpers
    // ------------------------------------------------------------------
    task check64(input [8*40-1:0] name, input [63:0] act, input [63:0] exp);
        begin
            checks = checks + 1;
            if (act !== exp) begin
                errors = errors + 1;
                $display("[%0t] FAIL  %0s : got %h, expected %h", $time, name, act, exp);
            end else
                $display("[%0t] PASS  %0s = %h", $time, name, act);
        end
    endtask

    task check1(input [8*40-1:0] name, input act, input exp);
        begin
            checks = checks + 1;
            if (act !== exp) begin
                errors = errors + 1;
                $display("[%0t] FAIL  %0s : got %b, expected %b", $time, name, act, exp);
            end else
                $display("[%0t] PASS  %0s = %b", $time, name, act);
        end
    endtask

    task check_int(input [8*40-1:0] name, input integer act, input integer exp);
        begin
            checks = checks + 1;
            if (act !== exp) begin
                errors = errors + 1;
                $display("[%0t] FAIL  %0s : got %0d, expected %0d", $time, name, act, exp);
            end else
                $display("[%0t] PASS  %0s = %0d", $time, name, act);
        end
    endtask

    // ------------------------------------------------------------------
    // Stimulus helpers (all called right after a falling edge)
    // ------------------------------------------------------------------
    task clocks(input integer k);       // wait k rising edges, end on a falling edge
        integer c;
        begin
            for (c = 0; c < k; c = c + 1)
                @(negedge sys_clk);
        end
    endtask

    task no_write;
        begin
            wr_en     = 1'b0;
            has_error = 1'b0;
            reg_addr  = 12'h000;
            reg_wdata = 32'h0;
            reg_wstrb = 4'b0000;
        end
    endtask

    // Stop the timer for one cycle: counter_val <- tdr, div_cnt <- 0
    task load_and_start(input [63:0] start_val, input den, input [3:0] dval);
        begin
            timer_en = 1'b0;
            tdr_val  = start_val;
            clocks(1);
            div_en   = den;
            div_val  = dval;
            timer_en = 1'b1;
        end
    endtask

    // One-cycle decoded register write (what timer_register sends to counter)
    task reg_write(input [11:0] addr, input [31:0] data, input [3:0] strb, input err);
        begin
            reg_addr  = addr;
            reg_wdata = data;
            reg_wstrb = strb;
            has_error = err;
            wr_en     = 1'b1;
            clocks(1);
            no_write;
        end
    endtask

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    initial begin
        checks = 0; errors = 0; sb_cycles = 0; sb_errors = 0; cmp_hits = 0;
        seed   = 32'h2026_1104;

        // Safe idle values
        sys_rst_n = 1'b0;
        timer_en  = 1'b0;
        div_en    = 1'b0;
        div_val   = 4'd0;
        tcmp_val  = 64'hFFFF_FFFF_FFFF_FFFF;
        tdr_val   = 64'd0;
        dbg_mode  = 1'b0;
        halt_req  = 1'b0;
        no_write;

        $display("==============================================================");
        $display(" COUNTER UNIT TEST (counter.v vs GOLDEN_MODEL.v)");
        $display("==============================================================");

        // ---------------- T1: asynchronous reset ----------------------
        test_phase = "T1_RESET";
        clocks(3);
        check64("T1 counter_val after reset", counter_val, 64'd0);
        check_int("T1 div_cnt after reset", dut_div_cnt, 0);
        check1 ("T1 halt_ack after reset", halt_ack, 1'b0);
        check1 ("T1 cmp_match_evt (TCMP=all 1s)", cmp_match_evt, 1'b0);
        sys_rst_n = 1'b1;
        clocks(1);

        // ---------------- T2: TIMER_EN=0 -> counter follows TDR --------
        test_phase = "T2_TDR_FOLLOW";
        tdr_val = 64'h0000_0000_0000_0010;
        clocks(1);
        check64("T2 counter_val follows TDR", counter_val, 64'h10);
        tdr_val = 64'h1234_5678_9ABC_DEF0;
        clocks(1);
        check64("T2 counter_val follows new TDR", counter_val, 64'h1234_5678_9ABC_DEF0);
        check_int("T2 div_cnt held at 0 (timer off)", dut_div_cnt, 0);
        check1 ("T2 no div_tick while timer off", dut_div_tick, 1'b0);

        // ---------------- T3: DIV_EN=0 -> +1 every clock ---------------
        test_phase = "T3_COUNT_NO_DIV";
        load_and_start(64'h10, 1'b0, 4'd0);
        #1 check1("T3 div_tick=1 every clock", dut_div_tick, 1'b1);
        clocks(5);
        check64("T3 counter_val after 5 clocks", counter_val, 64'h15);

        // ---------------- T4: prescaler period = 2^N (N = 0..7) --------
        test_phase = "T4_PRESCALER";
        for (n = 0; n < 8; n = n + 1) begin
            load_and_start(64'd0, 1'b1, n[3:0]);
            cycles = 0;
            while ((counter_val != 64'd3) && (cycles < 1000)) begin
                clocks(1);
                cycles = cycles + 1;
            end
            check_int("T4 clocks for 3 ticks = 3*2^N", cycles, 3 * (1 << n));
        end

        // ---------------- T5: TDR0 write while running (PSTRB) ---------
        test_phase = "T5_TDR0_WRITE";
        load_and_start(64'h1111_2222_3333_4444, 1'b0, 4'd0);
        clocks(2);
        snap = counter_val;
        reg_write(12'h004, 32'hAABB_CCDD, 4'b0011, 1'b0);
        check64("T5 TDR0 write, PSTRB=0011", counter_val, {snap[63:16], 16'hCCDD});
        snap = counter_val;
        reg_write(12'h004, 32'hAABB_CCDD, 4'b1111, 1'b0);
        check64("T5 TDR0 write, PSTRB=1111", counter_val, {snap[63:32], 32'hAABB_CCDD});

        // ---------------- T6: TDR1 write while running -----------------
        test_phase = "T6_TDR1_WRITE";
        snap = counter_val;
        reg_write(12'h008, 32'h5566_7788, 4'b1111, 1'b0);
        check64("T6 TDR1 write, PSTRB=1111", counter_val, {32'h5566_7788, snap[31:0]});
        snap = counter_val;
        reg_write(12'h008, 32'h9900_0000, 4'b1000, 1'b0);
        check64("T6 TDR1 write, PSTRB=1000", counter_val, {8'h99, snap[55:0]});

        // ---------------- T7: writes that must NOT touch the counter ---
        test_phase = "T7_WRITE_BLOCKED";
        snap = counter_val;
        reg_write(12'h004, 32'hDEAD_BEEF, 4'b1111, 1'b1);       // PSLVERR
        check64("T7 has_error=1: write ignored, +1", counter_val, snap + 64'd1);
        snap = counter_val;
        reg_write(12'h00C, 32'hDEAD_BEEF, 4'b1111, 1'b0);       // TCMP0 address
        check64("T7 other address: ignored, +1", counter_val, snap + 64'd1);
        snap = counter_val;
        reg_write(12'h004, 32'hDEAD_BEEF, 4'b0000, 1'b0);       // no byte lane
        check64("T7 TDR0 PSTRB=0000: hold, no +1", counter_val, snap);

        // ---------------- T8: compare match (level output) -------------
        test_phase = "T8_COMPARE";
        snap     = counter_val;
        tcmp_val = snap + 64'd3;
        clocks(1); check1("T8 cmp_match_evt at TCMP-2", cmp_match_evt, 1'b0);
        clocks(1); check1("T8 cmp_match_evt at TCMP-1", cmp_match_evt, 1'b0);
        clocks(1); check1("T8 cmp_match_evt at TCMP",   cmp_match_evt, 1'b1);
        check64("T8 counter_val == TCMP", counter_val, tcmp_val);
        clocks(1); check1("T8 cmp_match_evt at TCMP+1", cmp_match_evt, 1'b0);
        timer_en = 1'b0;
        tdr_val  = 64'h0000_00AB_0000_00CD;
        tcmp_val = 64'h0000_00AB_0000_00CD;
        clocks(1); check1("T8 match while stopped (level)", cmp_match_evt, 1'b1);
        tcmp_val = 64'hFFFF_FFFF_FFFF_FFFF;

        // ---------------- T9: debug halt -------------------------------
        test_phase = "T9_DEBUG_HALT";
        load_and_start(64'h100, 1'b0, 4'd0);
        clocks(2);
        snap     = counter_val;
        dbg_mode = 1'b1;
        halt_req = 1'b1;
        #1 check1("T9 halt_ack=1 (dbg_mode & halt_req)", halt_ack, 1'b1);
        clocks(5);
        check64("T9 counter frozen during halt", counter_val, snap);
        halt_req = 1'b0;
        #1 check1("T9 halt_ack=0 after halt_req=0", halt_ack, 1'b0);
        clocks(2);
        check64("T9 counting resumes", counter_val, snap + 64'd2);
        dbg_mode = 1'b0;
        halt_req = 1'b1;
        #1 check1("T9 halt_req without dbg_mode: no ack", halt_ack, 1'b0);
        clocks(3);
        check64("T9 halt_req ignored when dbg_mode=0", counter_val, snap + 64'd5);
        halt_req = 1'b0;

        // ---------------- T10: halt keeps the prescaler phase ----------
        test_phase = "T10_HALT_PHASE";
        load_and_start(64'd0, 1'b1, 4'd3);                       // tick every 8 clocks
        clocks(5);
        check_int("T10 div_cnt before halt", dut_div_cnt, 5);
        dbg_mode = 1'b1;
        halt_req = 1'b1;
        clocks(10);
        check_int("T10 div_cnt held during halt", dut_div_cnt, 5);
        check64("T10 counter held during halt", counter_val, 64'd0);
        halt_req = 1'b0;
        dbg_mode = 1'b0;
        clocks(2);
        check64("T10 no tick yet (div_cnt 5->7)", counter_val, 64'd0);
        clocks(1);
        check64("T10 tick when div_cnt == 7", counter_val, 64'd1);

        // ---------------- T11: 32-bit carry and 64-bit wrap ------------
        test_phase = "T11_ROLLOVER";
        load_and_start(64'h0000_0000_FFFF_FFFF, 1'b0, 4'd0);
        clocks(1);
        check64("T11 carry into bit 32", counter_val, 64'h0000_0001_0000_0000);
        load_and_start(64'hFFFF_FFFF_FFFF_FFFE, 1'b0, 4'd0);
        clocks(1);
        check64("T11 counter at max", counter_val, 64'hFFFF_FFFF_FFFF_FFFF);
        clocks(1);
        check64("T11 64-bit wrap to 0", counter_val, 64'd0);

        // ---------------- T12: DIV_VAL >= 8 (blocked by TCR in the IP) -
        // At module level the 8-bit limit becomes 0xFF -> 1 tick / 256 clocks.
        test_phase = "T12_DIVVAL_8";
        load_and_start(64'd0, 1'b1, 4'd8);
        cycles = 0;
        while ((counter_val != 64'd1) && (cycles < 1000)) begin
            clocks(1);
            cycles = cycles + 1;
        end
        check_int("T12 div_val=8 -> 256 clocks per tick", cycles, 256);

        // ---------------- T13: reset in the middle of a cycle ----------
        test_phase = "T13_ASYNC_RESET";
        load_and_start(64'h55AA_55AA_55AA_55AA, 1'b0, 4'd0);
        clocks(3);
        #2 sys_rst_n = 1'b0;                                     // not on a clock edge
        #1 check64("T13 async reset clears counter", counter_val, 64'd0);
        check_int("T13 async reset clears div_cnt", dut_div_cnt, 0);
        @(negedge sys_clk);
        sys_rst_n = 1'b1;
        timer_en  = 1'b0;
        tdr_val   = 64'd0;
        clocks(1);

        // ---------------- T14: random test vs golden model -------------
        test_phase = "T14_RANDOM";
        $display("[%0t] T14: 3000 random cycles, RTL compared with GOLDEN_MODEL every clock", $time);
        for (i = 0; i < 3000; i = i + 1) begin
            // configuration changes every 50 cycles
            if ((i % 50) == 0) begin
                div_en  = $random(seed);
                div_val = $random(seed);                         // 0..15
                tdr_val = {$random(seed), $random(seed)};
            end
            timer_en  = (($random(seed) & 15) != 0);             // mostly running
            wr_en     = (($random(seed) & 7) == 0);
            case ($random(seed) & 3)
                0: reg_addr = 12'h004;
                1: reg_addr = 12'h008;
                2: reg_addr = 12'h00C;
                default: reg_addr = 12'h000;
            endcase
            reg_wdata = $random(seed);
            reg_wstrb = $random(seed);
            has_error = (($random(seed) & 3) == 0);
            tcmp_val  = (($random(seed) & 1) ? (counter_val + ($random(seed) & 3))
                                             : {$random(seed), $random(seed)});
            dbg_mode  = (($random(seed) & 7) == 0);
            halt_req  = (($random(seed) & 3) == 0);
            sys_rst_n = (($random(seed) % 500) != 0);
            clocks(1);
            if (cmp_match_evt) cmp_hits = cmp_hits + 1;
        end
        sys_rst_n = 1'b1;
        no_write;
        dbg_mode  = 1'b0;
        halt_req  = 1'b0;
        clocks(2);
        $display("[%0t] T14: compare match seen in %0d random cycles", $time, cmp_hits);

        // ---------------- Summary --------------------------------------
        test_phase = "DONE";
        $display("==============================================================");
        $display(" COUNTER TB SUMMARY: directed checks = %0d, failures = %0d", checks, errors);
        $display("                     scoreboard cycles = %0d, mismatches = %0d", sb_cycles, sb_errors);
        if ((errors == 0) && (sb_errors == 0))
            $display(" *** TEST PASSED ***");
        else
            $display(" *** TEST FAILED ***");
        $display("==============================================================");
        $finish;
    end

endmodule
