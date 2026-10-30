`timescale 1ns/1ps
//==============================================================================
// Testbench tu kiem tra cho module register
//==============================================================================
module register_tb;

    // ---------------- DUT signals ----------------
    reg         sys_clk, sys_rst_n;
    reg         reg_wr_en;
    reg  [11:0] reg_addr;
    reg  [31:0] reg_wdata;
    reg  [3:0]  reg_pstrb;
    wire [31:0] reg_rdata;
    wire        reg_err;

    wire        timer_en, div_en;
    wire [3:0]  div_val;
    wire [63:0] tcmp;
    wire        int_en, halt_req, tim_int;
    wire        tdr0_load, tdr1_load;
    wire [31:0] tdr0_wdata, tdr1_wdata;

    reg  [31:0] tdr0_rdata, tdr1_rdata;   // gia lap timer_core
    reg         int_set, halt_ack;

    register dut (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .reg_wr_en(reg_wr_en), .reg_addr(reg_addr), .reg_wdata(reg_wdata),
        .reg_pstrb(reg_pstrb), .reg_rdata(reg_rdata), .reg_err(reg_err),
        .timer_en(timer_en), .div_en(div_en), .div_val(div_val),
        .tcmp(tcmp), .int_en(int_en), .halt_req(halt_req), .tim_int(tim_int),
        .tdr0_load(tdr0_load), .tdr0_wdata(tdr0_wdata),
        .tdr1_load(tdr1_load), .tdr1_wdata(tdr1_wdata),
        .tdr0_rdata(tdr0_rdata), .tdr1_rdata(tdr1_rdata),
        .int_set(int_set), .halt_ack(halt_ack)
    );

    // ---------------- Dia chi ----------------
    localparam TCR=12'h00, TDR0=12'h04, TDR1=12'h08, TCMP0=12'h0C,
               TCMP1=12'h10, TIER=12'h14, TISR=12'h18, THCSR=12'h1C;

    // ---------------- Clock ----------------
    initial sys_clk = 1'b0;
    always #5 sys_clk = ~sys_clk;

    // ---------------- Bien ghi nhan ----------------
    integer errors = 0;
    integer checks = 0;
    reg         g_err;
    reg [31:0]  g_rdata;
    reg         s_t0_load, s_t1_load;
    reg [31:0]  s_t0_data, s_t1_data;

    // ---------------- Task ----------------
    task check;
        input [255:0] name;
        input [63:0]  got;
        input [63:0]  exp;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("[FAIL] %0s : got=0x%0h exp=0x%0h (t=%0t)", name, got, exp, $time);
            end else
                $display("[ ok ] %0s : 0x%0h", name, got);
        end
    endtask

    // Ghi APB (1 chu ky). Lay mau reg_err va tdr load/wdata truoc canh clock.
    task apb_write;
        input [11:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            @(negedge sys_clk);
            reg_addr = addr; reg_wdata = data; reg_pstrb = strb; reg_wr_en = 1'b1;
            #1;
            g_err     = reg_err;
            s_t0_load = tdr0_load; s_t0_data = tdr0_wdata;
            s_t1_load = tdr1_load; s_t1_data = tdr1_wdata;
            @(posedge sys_clk); #1;
            reg_wr_en = 1'b0; reg_wdata = 32'h0; reg_pstrb = 4'h0;
        end
    endtask

    task apb_read;
        input [11:0] addr;
        begin
            @(negedge sys_clk);
            reg_addr = addr; reg_wr_en = 1'b0;
            #1;
            g_rdata = reg_rdata;
        end
    endtask

    task pulse_int_set;
        begin
            @(negedge sys_clk); int_set = 1'b1;
            @(posedge sys_clk); #1 int_set = 1'b0;
        end
    endtask

    task do_reset;
        begin
            #3 sys_rst_n = 1'b0;
            #12 sys_rst_n = 1'b1;
        end
    endtask

    // ---------------- Kich ban kiem tra ----------------
    initial begin
        $dumpfile("register_tb.vcd");
        $dumpvars(0, register_tb);

        sys_rst_n = 1'b1; reg_wr_en = 0; reg_addr = 0; reg_wdata = 0; reg_pstrb = 0;
        tdr0_rdata = 32'h0; tdr1_rdata = 32'h0; int_set = 0; halt_ack = 0;
        do_reset;

        //----------------------------------------------------------------
        $display("\n=== T1: Gia tri reset ===");
        apb_read(TCR);   check("TCR reset",   g_rdata, 32'h0);
        apb_read(TCMP0); check("TCMP0 reset", g_rdata, 32'hFFFF_FFFF);
        apb_read(TCMP1); check("TCMP1 reset", g_rdata, 32'hFFFF_FFFF);
        apb_read(TIER);  check("TIER reset",  g_rdata, 32'h0);
        apb_read(TISR);  check("TISR reset",  g_rdata, 32'h0);
        apb_read(THCSR); check("THCSR reset", g_rdata, 32'h0);
        check("tcmp out reset", tcmp, 64'hFFFF_FFFF_FFFF_FFFF);

        //----------------------------------------------------------------
        $display("\n=== T2: Ghi/doc TCR hop le (timer_en = 0) ===");
        apb_write(TCR, 32'h0000_0302, 4'hF);
        check("T2 err",   g_err, 0);
        apb_read(TCR);    check("T2 TCR", g_rdata, 32'h0000_0302);
        check("T2 div_en", div_en, 1); check("T2 div_val", div_val, 3);
        check("T2 timer_en", timer_en, 0);

        //----------------------------------------------------------------
        $display("\n=== T3: Bit reserved cua TCR: doc 0, ghi bi bo qua ===");
        apb_write(TCR, 32'hFFFF_F0F2, 4'hF);   // div_val = 0, div_en = 1
        check("T3 err", g_err, 0);
        apb_read(TCR);  check("T3 TCR", g_rdata, 32'h0000_0002);

        //----------------------------------------------------------------
        $display("\n=== T4: Gia tri cam div_val (>= 8) ===");
        apb_write(TCR, 32'h0000_0802, 4'hF);
        check("T4 err 8", g_err, 1);
        apb_read(TCR);  check("T4 TCR giu nguyen", g_rdata, 32'h0000_0002);
        apb_write(TCR, 32'h0000_0F02, 4'hF);
        check("T4 err F", g_err, 1);
        apb_read(TCR);  check("T4 TCR giu nguyen 2", g_rdata, 32'h0000_0002);
        apb_write(TCR, 32'h0000_0702, 4'hF);   // bien hop le lon nhat
        check("T4 err 7", g_err, 0);
        apb_read(TCR);  check("T4 TCR div_val=7", g_rdata, 32'h0000_0702);
        // Byte 1 khong duoc strobe -> khong xet div_val, khong loi
        apb_write(TCR, 32'h0000_0800, 4'b0001);
        check("T4 err byte0 only", g_err, 0);
        apb_read(TCR);  check("T4 TCR sau byte0", g_rdata, 32'h0000_0700);

        //----------------------------------------------------------------
        $display("\n=== T5: Byte access qua pstrb ===");
        apb_write(TCR, 32'h0000_0500, 4'b0010);          // chi byte 1
        check("T5 err a", g_err, 0);
        apb_read(TCR);  check("T5 byte1", g_rdata, 32'h0000_0500);
        apb_write(TCR, 32'hFFFF_FFFF, 4'b0100);          // byte 2: reserved
        check("T5 err b", g_err, 0);
        apb_read(TCR);  check("T5 byte2 bi bo qua", g_rdata, 32'h0000_0500);
        apb_write(TCR, 32'h0000_0002, 4'b0001);          // byte 0: div_en = 1
        apb_read(TCR);  check("T5 byte0", g_rdata, 32'h0000_0502);
        apb_write(TCR, 32'h0000_0001, 4'b0000);          // pstrb = 0: khong ghi
        check("T5 err pstrb=0", g_err, 0);
        apb_read(TCR);  check("T5 pstrb=0 khong doi", g_rdata, 32'h0000_0502);

        //----------------------------------------------------------------
        $display("\n=== T6: Bao ve TCR khi timer_en = 1 ===");
        apb_write(TCR, 32'h0000_0503, 4'hF);             // bat timer, giu div
        check("T6 err start", g_err, 0);
        check("T6 timer_en", timer_en, 1);
        apb_write(TCR, 32'h0000_0300, 4'b0010);          // doi div_val
        check("T6 err div_val", g_err, 1);
        apb_read(TCR);  check("T6 TCR giu nguyen 1", g_rdata, 32'h0000_0503);
        apb_write(TCR, 32'h0000_0001, 4'b0001);          // doi div_en 1->0
        check("T6 err div_en", g_err, 1);
        apb_read(TCR);  check("T6 TCR giu nguyen 2", g_rdata, 32'h0000_0503);
        apb_write(TCR, 32'h0000_0F03, 4'hF);             // gia tri cam
        check("T6 err cam", g_err, 1);
        apb_read(TCR);  check("T6 TCR giu nguyen 3", g_rdata, 32'h0000_0503);
        apb_write(TCR, 32'h0000_0503, 4'hF);             // ghi lai dung gia tri
        check("T6 err cung gia tri", g_err, 0);
        apb_write(TCR, 32'h0000_0502, 4'hF);             // tat timer, giu div
        check("T6 err stop", g_err, 0);
        check("T6 timer_en stop", timer_en, 0);
        apb_write(TCR, 32'h0000_0300, 4'hF);             // timer tat -> doi duoc
        check("T6 err doi div khi tat", g_err, 0);
        apb_read(TCR);  check("T6 TCR moi", g_rdata, 32'h0000_0300);

        //----------------------------------------------------------------
        $display("\n=== T7: TDR0/TDR1 ===");
        tdr0_rdata = 32'hAABB_CCDD; tdr1_rdata = 32'h1122_3344;
        apb_read(TDR0); check("T7 doc TDR0", g_rdata, 32'hAABB_CCDD);
        apb_read(TDR1); check("T7 doc TDR1", g_rdata, 32'h1122_3344);
        apb_write(TDR0, 32'h5566_7788, 4'b0101);
        check("T7 t0_load", s_t0_load, 1);
        check("T7 t1_load", s_t1_load, 0);
        check("T7 t0_data", s_t0_data, 32'hAA66_CC88);
        apb_write(TDR1, 32'hDEAD_BEEF, 4'hF);
        check("T7 t1_load b", s_t1_load, 1);
        check("T7 t0_load b", s_t0_load, 0);
        check("T7 t1_data", s_t1_data, 32'hDEAD_BEEF);
        apb_write(TDR0, 32'h1234_5678, 4'h0);
        check("T7 pstrb=0 khong load", s_t0_load, 0);
        check("T7 err", g_err, 0);

        //----------------------------------------------------------------
        $display("\n=== T8: TCMP0/TCMP1 ===");
        apb_write(TCMP0, 32'h1234_5678, 4'hF);
        apb_read(TCMP0); check("T8 TCMP0", g_rdata, 32'h1234_5678);
        apb_write(TCMP1, 32'hAAAA_BBBB, 4'b0011);
        apb_read(TCMP1); check("T8 TCMP1 byte", g_rdata, 32'hFFFF_BBBB);
        check("T8 tcmp out", tcmp, 64'hFFFF_BBBB_1234_5678);

        //----------------------------------------------------------------
        $display("\n=== T9: TIER / TISR (W1C) ===");
        pulse_int_set;
        apb_read(TISR); check("T9 int_st set", g_rdata, 1);
        check("T9 tim_int khi int_en=0", tim_int, 0);
        apb_write(TIER, 32'hFFFF_FFFF, 4'hF);
        apb_read(TIER); check("T9 TIER reserved=0", g_rdata, 32'h1);
        check("T9 tim_int khi int_en=1", tim_int, 1);
        apb_write(TISR, 32'h0, 4'hF);
        apb_read(TISR); check("T9 ghi 0 khong xoa", g_rdata, 1);
        apb_write(TISR, 32'h1, 4'b0010);
        apb_read(TISR); check("T9 sai byte lane khong xoa", g_rdata, 1);
        apb_write(TISR, 32'h1, 4'hF);
        apb_read(TISR); check("T9 W1C xoa", g_rdata, 0);
        check("T9 tim_int sau xoa", tim_int, 0);
        // set va clear cung luc -> set thang
        int_set = 1'b1;
        apb_write(TISR, 32'h1, 4'hF);
        int_set = 1'b0;
        apb_read(TISR); check("T9 set uu tien hon clear", g_rdata, 1);
        apb_write(TISR, 32'h1, 4'hF);
        apb_read(TISR); check("T9 xoa lai", g_rdata, 0);
        apb_write(TIER, 32'h0, 4'hF);

        //----------------------------------------------------------------
        $display("\n=== T10: THCSR ===");
        apb_write(THCSR, 32'h1, 4'hF);
        check("T10 halt_req out", halt_req, 1);
        apb_read(THCSR); check("T10 doc", g_rdata, 32'h1);
        halt_ack = 1'b1;
        apb_read(THCSR); check("T10 halt_ack", g_rdata, 32'h3);
        apb_write(THCSR, 32'h0, 4'hF);
        apb_read(THCSR); check("T10 xoa halt_req", g_rdata, 32'h2);
        apb_write(THCSR, 32'h2, 4'hF);                   // ghi vao RO
        apb_read(THCSR); check("T10 halt_ack RO", g_rdata, 32'h2);
        check("T10 halt_req van 0", halt_req, 0);
        halt_ack = 1'b0;

        //----------------------------------------------------------------
        $display("\n=== T11: Dia chi reserved (RAZ/WI) ===");
        apb_write(12'h020, 32'hFFFF_FFFF, 4'hF);
        check("T11 err 0x20", g_err, 0);
        check("T11 no tdr load", s_t0_load | s_t1_load, 0);
        apb_write(12'h03C, 32'hFFFF_FFFF, 4'hF);
        check("T11 err 0x3C", g_err, 0);
        apb_write(12'h100, 32'hFFFF_FFFF, 4'hF);
        apb_write(12'hFFC, 32'hFFFF_FFFF, 4'hF);
        check("T11 err 0xFFC", g_err, 0);
        apb_read(12'h020); check("T11 doc 0x20", g_rdata, 0);
        apb_read(12'h03C); check("T11 doc 0x3C", g_rdata, 0);
        apb_read(12'h100); check("T11 doc 0x100", g_rdata, 0);
        apb_read(12'hFFC); check("T11 doc 0xFFC", g_rdata, 0);
        apb_read(TCR);   check("T11 TCR khong doi",   g_rdata, 32'h0000_0300);
        apb_read(TCMP0); check("T11 TCMP0 khong doi", g_rdata, 32'h1234_5678);
        apb_read(TIER);  check("T11 TIER khong doi",  g_rdata, 0);
        apb_read(THCSR); check("T11 THCSR khong doi", g_rdata, 0);

        //----------------------------------------------------------------
        $display("\n=== T12: Reset bat dong bo giua chung ===");
        apb_write(TCR, 32'h0000_0301, 4'hF);
        check("T12 timer_en=1", timer_en, 1);
        #2 sys_rst_n = 1'b0;
        #1 check("T12 timer_en sau reset", timer_en, 0);
        check("T12 tcmp sau reset", tcmp, 64'hFFFF_FFFF_FFFF_FFFF);
        #10 sys_rst_n = 1'b1;
        apb_read(TCR); check("T12 TCR sau reset", g_rdata, 0);

        //----------------------------------------------------------------
        $display("\n==============================================");
        if (errors == 0)
            $display(" TAT CA %0d KIEM TRA DEU PASS", checks);
        else
            $display(" %0d / %0d KIEM TRA FAIL", errors, checks);
        $display("==============================================\n");
        $finish;
    end

    // Watchdog
    initial begin
        #200000;
        $display("[TIMEOUT]");
        $finish;
    end

endmodule
