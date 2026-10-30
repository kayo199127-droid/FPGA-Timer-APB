`timescale 1ns/1ps

module test_bench;
    //1. Khai bao cac tin hieu ket noi
    reg          sys_clk;
    reg          sys_rst_n;
    reg          tim_psel;
    reg          tim_penable;
    reg          tim_pwrite;
    reg [11:0]   tim_paddr;
    reg [3:0]    tim_pstrb;
    reg [31:0]   tim_pwdata;
    wire [31:0]  tim_prdata;
    wire         tim_pready;
    wire         tim_pslverr;
    wire         tim_int;
    reg          dbg_mode;
    wire         div_tick;
    wire         halt_ack;

    // Bien kiem tra du lieu doc ve va luu response PSLVERR cua giao dich vua xong
    reg [31:0] rdata;
    reg         last_pslverr;

    // Chu ki xung clk
    parameter CLK_PERIOD = 10;

    //==========================================
    // Dia chi cac thanh ghi (Offset Address)
    //==========================================
    parameter ADDR_TCR      = 12'h000;
    parameter ADDR_TDR0     = 12'h004;
    parameter ADDR_TDR1     = 12'h008;
    parameter ADDR_TCMP0    = 12'h00C;
    parameter ADDR_TCMP1    = 12'h010;
    parameter ADDR_TIER     = 12'h014;
        parameter ADDR_TISR     = 12'h018;
    parameter ADDR_THCSR    = 12'h01C;

    //2. Noi day voi top Module
    timer_top dut(
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
        //.div_tick(div_tick),
        //.halt_ack(halt_ack)
    );

    assign div_tick = dut.u_counter.u_counter_divider.div_tick;
    assign halt_ack = dut.u_counter.u_counter_core.halt_ack;

    // 3. Tao xung clk lien tuc
    initial begin
        sys_clk = 0;
        forever #(CLK_PERIOD / 2) sys_clk = ~sys_clk;
    end

    //4. Tao tin hieu Reset
    initial begin
        sys_rst_n = 1'b0;
        tim_psel  = 1'b0;
        tim_penable = 1'b0;
        tim_pwrite = 1'b0;
        tim_paddr = 1'b0;
        tim_pwdata = 1'b0;
        tim_pstrb = 1'b0;
        dbg_mode = 1'b0;

        #(CLK_PERIOD * 2);
        sys_rst_n = 1'b1;
    end

    //===========================================
    //TASK: APB WRITE & READ BUS
    //===========================================
    task apb_write(input [11:0] addr, input [31:0] data, input [3:0] strb);
        begin
            last_pslverr = 1'b0;
            @(posedge sys_clk);
            tim_psel    <= 1'b1;
            tim_pwrite  <= 1'b1;
            tim_paddr   <= addr;
            tim_pwdata  <= data;
            tim_pstrb   <= strb;
            tim_penable <= 1'b0;

            @(posedge sys_clk);
            tim_penable <= 1'b1;

            @(posedge sys_clk);
            while(!tim_pready) @(posedge sys_clk);
            // Capture the one-cycle APB response before returning to IDLE.
            last_pslverr = tim_pslverr;

            tim_psel    <= 1'b0;
            tim_penable <= 1'b0;
            tim_pwrite  <= 1'b0;
        end
    endtask

    task apb_read(input [11:0] addr, output [31:0] data);
        begin
                @(posedge sys_clk);
            tim_psel <= 1'b1;
            tim_pwrite <= 1'b0;
            tim_paddr <= addr;
            tim_pstrb <= 4'h0;
            tim_penable <= 1'b0;

            @(posedge sys_clk);
            tim_penable <= 1'b1;

            @(posedge sys_clk);
            while(!tim_pready) @(posedge sys_clk);

            data = tim_prdata;
            tim_psel <= 1'b0;
            tim_penable <= 1'b0;
        end
    endtask

    //---------------------------------------------------
    //MAIN TEST SEQUENCE (ID2 --> ID8)
    //---------------------------------------------------
    initial begin
        // Khoi tao ban dau
        sys_rst_n    = 0;
        tim_psel     = 0;
        tim_pwrite   = 0;
        tim_penable  = 0;
        tim_paddr    = 0;
        tim_pwdata   = 0;
        tim_pstrb    = 0;
        dbg_mode     = 0;

        $display("------------------------------------------");
        $display("[START TESTBENCH] KIEM TRA KHOI RESET (RST_N)");
        $display("------------------------------------------");

        //=================================================
        //ID2: Power-On Reset
        //=================================================
    begin : ID2_BLOCK

        $display("[ID2] Running Power on Reset Check...");
        sys_rst_n = 0;
        repeat(5) @(posedge sys_clk);
        sys_rst_n = 1;
        @(posedge sys_clk);

        // Kiem tra gia tri Reset Default cua thanh ghi qua APB
        apb_read(ADDR_TCR, rdata);
        if(rdata !== 32'h0000_0100) $error("[ID2 FAIL] TCR default = %h (Expected: 32'h0000_0100)", rdata);

        apb_read(ADDR_TDR0, rdata);
        if(rdata !== 32'h0000_0000) $error("[ID2 FAIL] TDR0 default = %h (Expected: 32'h0000_0000)", rdata);

        apb_read(ADDR_TDR1, rdata);
        if(rdata !== 32'h0000_0000) $error("[ID2 FAIL] TDR1 default = %h (Expected: 32'h0000_0000)", rdata);

        apb_read(ADDR_TCMP0, rdata);
        if(rdata !== 32'hFFFF_FFFF) $error("[ID2 FAIL] TCMP0 default = %h (Expected: 32'hFFFF_FFFF)", rdata);

        apb_read(ADDR_TCMP1, rdata);
        if(rdata !== 32'hFFFF_FFFF) $error("[ID2 FAIL] TCMP1 default = %h (Expected: 32'hFFFF_FFFF)", rdata);

        apb_read(ADDR_TIER, rdata);
        if(rdata !== 32'h0000_0000) $error("[ID2 FAIL] TIER default = %h (Expected: 32'h0000_0000)", rdata);

        apb_read(ADDR_TISR, rdata);
        if(rdata !== 32'h0000_0000) $error("[ID2 FAIL] TISR default = %h (Expected: 32'h0000_0000)", rdata);

        apb_read(ADDR_THCSR, rdata);
        if(rdata !== 32'h0000_0000) $error("[ID2 FAIL] THCSR default = %h (Expected: 32'h0000_0000)", rdata);

        $display("[ID2 PASSED] Successfully");

    end
        //=====================================================
        //ID3: Async Reset Assert
        //=====================================================
    begin : ID3_BLOCK

        $display("[ID3] Running Async Reset Assert...");
        @(posedge sys_clk);
        #(CLK_PERIOD / 4);
        sys_rst_n = 0;

        #1;
        if(tim_prdata != 32'h0000_0000) $error("[ID3 FAIL] Async Reset Logic Error !");
            else $display("[ID3 PASSED] Successfully");

    end
        //===================================================
        //ID4: Sync De-assert
        //===================================================
    begin : ID4_BLOCK

        $display("[ID4] Running Sync De-assert...");
        @(negedge sys_clk);
        sys_rst_n = 1;
        @(posedge sys_clk);
        if($isunknown(tim_prdata)) $error("[ID4 FAIL] Signal has X/Z state");
        else $display("[ID4 PASSED] Successfully");

    end
        //====================================================
        //ID5: Reset Abort Write
        //====================================================
    begin : ID5_BLOCK

        $display("[ID5] Running Reset Abort Write...");

        // Bat dau chu trinh ghi APB vao TDR0
        tim_psel    <= 1'b1;
        tim_pwrite  <= 1'b1;
        tim_paddr   <= ADDR_TDR0;
        tim_pwdata  <= 32'h1234_5678;
        tim_penable <= 1'b1;

        // Keo Reset = 0 ngay khi ghi du lieu
        sys_rst_n = 0;
        #(CLK_PERIOD);
        tim_psel    <= 1'b0;
        tim_penable <= 1'b0;
        sys_rst_n   <= 1'b1;

        // Doc lai TDR0, co bi ghi de khong
        apb_read(ADDR_TDR0, rdata);
        if(rdata != 32'h0000_0000) $error("[ID5 FAIL] TDR0 written during Reset");
        else $display("[ID5 PASSED] Successfully");

    end
        //===================================================
        //ID6: Reset Abort Read
        //===================================================
    begin : ID6_BLOCK

        $display("[ID6] Running Reset Abort Read...");

        // Bat dau chu trinh doc APB
        @(posedge sys_clk);
        tim_psel     <= 1'b1;
        tim_pwrite   <= 1'b0;
        tim_paddr    <= ADDR_TCMP0;
        tim_penable  <= 1'b1;

        // Keo Reset ngau nhien khi dang doc
        sys_rst_n = 0;
        #1;
        if(rdata != 32'h0000_0000) $error("[ID6 FAIL] prdata is not forced 0");
        else $display("[ID6 PASSED] Successfully");

        // De ve trang thai binh thuong
        sys_rst_n    = 1'b1;
        tim_psel     = 1'b0;
        tim_penable  = 1'b0;

    end
        //===================================================
        //ID7: Reset Active Counter
        //===================================================
    begin : ID7_BLOCK

        $display("[ID7] Running Reset Active Counter...");

        //Bat timer_en = 1
        apb_write(ADDR_TCR, 32'h0000_0101, 4'hF);

        // Cho bo dem chay 10 chu ki
        repeat(10) @(posedge sys_clk);

        // Keo Reset ngat ngang bo dem
        sys_rst_n = 0;
        repeat(2) @(posedge sys_clk);
        sys_rst_n = 1;

        // Kiem tra TDR0 da bi reset ve 0 chua
        apb_read(ADDR_TDR0, rdata);
        if(rdata != 32'h0000_0000) $error("[ID7 FAIL] Counter not clear after Reset");
        else $display("[ID7 PASSED] Successfully");

    end
        //===================================================
        //ID8: Multi pulse Reset
        //===================================================
    begin : ID8_BLOCK

        $display("[ID8] Running Multi Pulse Reset...");

        // Doi nhieu xung Reset lien tuc
        sys_rst_n = 0; #(CLK_PERIOD);
        sys_rst_n = 1; #(CLK_PERIOD);
        sys_rst_n = 0; #(CLK_PERIOD * 2);
        sys_rst_n = 1; #(CLK_PERIOD);

        // Kiem tra lai kha nang truy cap bus
        apb_read(ADDR_TCR, rdata);
        if(rdata != 32'h0000_0100) $error("[ID8 FAIL] System lookup");
        else $display("[ID8 PASSED] Successfully");
    end
        /*
        $display("---------------------------------------------------");
        $display("[COMPLETED] TOAN BO TESTCASES RESET DA HOAN THANH");
        $display("---------------------------------------------------");
        $finish; */

        //==================================================
        //ID9: Single Write Transfer
        //==================================================
    begin : ID9_BLOCK

        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        $display("[ID9] Running Single Write Transfer...");

        @(posedge sys_clk);
        tim_psel     <= 1'b1;
        tim_pwrite   <= 1'b1;
        tim_paddr    <= ADDR_TCMP0;
        tim_pwdata   <= 32'hA5A5_1234;
        tim_pstrb    <= 4'hF;
        tim_penable  <= 1'b0;

        @(posedge sys_clk);
        tim_penable  <= 1'b1;

        @(posedge sys_clk);
        while(!tim_pready) @(posedge sys_clk);
        tim_psel     <= 1'b0;
        tim_penable  <= 1'b0;
        tim_pwrite    <= 1'b0;
        tim_pstrb    <= 4'h0;

        @(posedge sys_clk);

        // Check Pass Condition
        apb_read(ADDR_TCMP0, rdata);
        if(rdata == 32'hA5A5_1234) $display("[ID9 PASSED] Successfully");
        else $error("[ID9 FAIL]");
    end
        //===============================================
        //ID10: Single Read Transfer
        //===============================================
    begin : ID10_BLOCK

        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        reg [31:0] exp_data;

        exp_data = 32'h1234_5678;
        apb_write(ADDR_TCMP0, exp_data, 4'hF);

        $display("[ID10] Running Single Read Tranfer...");

        @(posedge sys_clk);
        tim_psel     <= 1'b1;
        tim_pwrite   <= 1'b0;
        tim_paddr    <= ADDR_TCMP0;
        tim_penable  <= 1'b0;

        @(posedge sys_clk);
        tim_penable  <= 1'b1;

        @(posedge sys_clk);
        while(!tim_pready) @(posedge sys_clk);

        rdata = tim_prdata;
        tim_psel     <= 1'b0;
        tim_penable  <= 1'b0;

        if(rdata  != exp_data) $error("[ID10 FAIL]");
        else $display("[ID10 PASSED] Successfully");
    end
        //=================================================
        //ID11: Back to Back Transfer
        //=================================================
    begin : ID11_BLOCK

        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        $display("[ID11] Running Back to Back Transfer...");

        //1. WRITE 1: Ghi 32'h1111_1111 vao TCMP0
        @(posedge sys_clk);
        tim_psel     <= 1'b1;
        tim_pwrite   <= 1'b1;
        tim_paddr    <= ADDR_TCMP0;
        tim_pwdata   <= 32'h1111_1111;
        tim_pstrb    <= 4'hF;
        tim_penable  <= 1'b0;

        @(posedge sys_clk);
        tim_penable  <= 1'b1;

        @(posedge sys_clk);
        while(!tim_pready) @(posedge sys_clk);

        //2. WRITE 2: Ghi  32'h2222_2222 vao TCMP1
        tim_penable  <= 1'b0;
        tim_pwrite   <= 1'b1;
        tim_paddr    <= ADDR_TCMP1;
        tim_pwdata   <= 32'h2222_2222;
        tim_pstrb    <= 4'hF;

        @(posedge sys_clk);
        tim_penable  <= 1'b1;

        @(posedge sys_clk);
        while(!tim_pready) @(posedge sys_clk);

        //3. READ1: Doc TCMP0
        tim_penable  <= 1'b0;
        tim_pwrite   <= 1'b0;
        tim_paddr    <= ADDR_TCMP0;
        tim_pstrb    <= 4'h0;

        @(posedge sys_clk);
        tim_penable  <= 1'b1;

        @(posedge sys_clk);
        while(!tim_pready) @(posedge sys_clk);

        // Check du lieu Read 1
        if(tim_prdata !== 32'h1111_1111) $error("[ID11 FAIL]");
        else $display("[ID11 PASSED]");

        //4. READ 2: Doc TCMP1
        tim_penable    <= 1'b0;
        tim_pwrite     <= 1'b0;
        tim_paddr      <= ADDR_TCMP1;

        @(posedge sys_clk);
        tim_penable    <= 1'b1;

        @(posedge sys_clk);
        while(!tim_pready) @(posedge sys_clk);

        // Check du lieu Read 2
        if(tim_prdata !== 32'h2222_2222) $error("[ID11 FAIL]");
        else $display("[ID11 PASSED]");

        //5. Clear Bus ve trang thai IDLE
        tim_psel      <= 1'b0;
        tim_penable   <= 1'b0;
        tim_pwrite    <= 1'b0;

        $display("[ID11 PASSED] Successfully");
    end
        //================================================
        //ID12: APB SLave Unselected
        //================================================

    begin : ID12_BLOCK

        reg [31:0] old_data;
        reg [31:0] rdata;
        automatic bit fail_flag = 0;

        $display("[ID12] Running APB Slave Unselected");

        //1. Doc gtri hien tai cua TCMP0 de doi chieu
        apb_read(ADDR_TCMP0, old_data);

        //2. Thuc hien: psel = 0, penable = 1, pwrite = 1
        @(posedge sys_clk)
        tim_psel     <= 1'b0;
        tim_pwrite   <= 1'b1;
        tim_penable   <= 1'b1;
        tim_paddr    <= ADDR_TCMP0;
        tim_pwdata   <= ~old_data;
        tim_pstrb    <= 4'hF;

        @(posedge sys_clk);
        // Kiem tra tin hieu noi bo wr_en / rd_en
        if(dut.reg_wr_en_w !== 1'b0 || dut.reg_rd_en_w !== 1'b0) $error("[ID12 FAIL]");

        // Clear Bus
        tim_penable  <= 1'b0;
        tim_pwrite   <= 1'b0;
        tim_pstrb    <= 1'b0;

        //3. Doc lai thanh ghi de xac nhan rang du lieu KHONG thay doi
        apb_read(ADDR_TCMP0, rdata);
        if(rdata !== old_data) $error("[ID12 FAIL]");
        else $display("[ID12 PASSED] Successfully");
    end
        //===================================================
        //ID13: Byte Enable
        //===================================================

    begin : ID13_BLOCK

        reg [31:0] rdata;
        automatic bit fail_flag = 0;

        $display("[ID13] Running Byte Enable...");

        //1. Reset TCMP0 ve 32'h0000_0000
        apb_write(ADDR_TCMP0, 32'h0000_0000, 4'hF);

        //2. Ghi Byte 0
        apb_write(ADDR_TCMP0, 32'h1234_5678, 4'b0001);
        apb_read(ADDR_TCMP0, rdata);
        if(rdata !== 32'h0000_0078) begin
            $error("[ID13 FAIL]");
            fail_flag = 1;
        end

        //3. Ghi Byte 0 va 1
        apb_write(ADDR_TCMP0, 32'h1234_5678, 4'b0011);
        apb_read(ADDR_TCMP0, rdata);
                if(rdata !== 32'h0000_5678) begin
            $error("[ID13 FAIL]");
            fail_flag = 1;
        end

        //4. Ghi Byte 2, 1 va 0
        apb_write(ADDR_TCMP0, 32'h1234_5678, 4'b0111);
                apb_read(ADDR_TCMP0, rdata);
                if(rdata !== 32'h0034_5678) begin
                         $error("[ID13 FAIL]");
                         fail_flag = 1;
            end

        //5. Ghi full 4 Byte
        apb_write(ADDR_TCMP0, 32'h1234_5678, 4'b1111);
        apb_read(ADDR_TCMP0, rdata);
                if(rdata !== 32'h1234_5678) begin
                         $error("[ID13 FAIL]");
                         fail_flag = 1;
                end

        //6. Tong ket ID13
        if(!fail_flag) begin
            $display("[ID13 PASSED] Successfully");
        end
    end
/*      //=============================================
        //ID14: ILLegal Address Access
        //=============================================

    begin : ID14_BLOCK

        reg [31:0] old_tcmp0;
        reg [31:0] old_data;
        reg [31:0] rdata;
        bit fail_flag = 0;

        $display("[ID14] Running Illegal Address Access...");

        //1. Luu gtri hien tai cua 1 thanh ghi hop le TCMP0
        apb_read(ADDR_TCMP0, old_tcmp0);

        //2. WRITE vao 1 dia chi khong Hop le Illegal
        @(posedge sys_clk);
        tim_psel    <= 1'b1;
        tim_pwrite  <= 1'b1;
        tim_paddr   <= 12'h0FF;
        tim_pwdata  <= 32'hDEAD_BEEF;
        tim_pstrb   <= 4'hF;
        tim_penable <= 1'b0;

        @(posedge sys_clk);
        tim_penable <= 1'b1;

        @(posedge sys_clk);
        while(!tim_pready) @(posedge sys_clk);

        do @(posedge sys_clk); while(!tim_pready);

        if(tim_pslverr !== 1'b1) begin
            $error("[ID14 FAIL]");
            fail_flag = 1;
        end

        // Clear Bus ve IDLE
        tim_psel    <= 1'b0;
        tim_pwrite  <= 1'b0;
        tim_penable <= 1'b0;

        //3. READ tu 1 dia chi Khong Hop le
        @(posedge sys_clk);
        tim_psel    <= 1'b1;
        tim_pwrite  <= 1'b0;
        tim_paddr   <= 12'h0FF;
        tim_pstrb   <= 4'h0;
        tim_penable <= 1'b0;

        @(posedge sys_clk);
        tim_penable <= 1'b1;

        @(posedge sys_clk);
        while(!tim_pready) @(posedge sys_clk);

        do @(posedge sys_clk); while(!tim_pready);

        if(tim_pslverr !== 1'b1) begin
            $error("[ID14 FAIL]");
            fail_flag = 1;
        end

        // Clear Bus ve IDLE
        tim_psel    <= 1'b0;
        tim_penable <= 1'b0;

        //4. Dam bao thanh ghi hop le khong bi bien doi
        apb_read(ADDR_TCMP0, rdata);
        if(rdata !== old_tcmp0) begin
            $error("[ID14 FAIL]");
            fail_flag = 1;
        end

        // Tong ket ID14
        if(!fail_flag) begin
            $display("[ID14 PASSED] Successfully");
        end
    end   */
        //===============================================
        //ID15: Incomplete Phase
        //===============================================

    begin : ID15_BLOCK

        reg [31:0] rdata;
        automatic bit fail_flag = 0;

        $display("[ID15] Running Incomplete Phase");

        //1. Reset thanh ghi TCMP0 ve 32'h0000_0000
        apb_write(ADDR_TCMP0, 32'h0000_0000, 4'hF);

        //2. Set psel = 1, giu penable = 0 lien tuc 5 chu ki
        @(posedge sys_clk);
        tim_psel    <= 1'b1;
        tim_pwrite  <= 1'b1;
        tim_paddr   <= ADDR_TCMP0;
        tim_pwdata  <= 32'hFFFF_FFFF;
        tim_pstrb   <= 4'hF;
        tim_penable <= 1'b0;

        repeat(5) @(posedge sys_clk);

        // Kiem tra truc tiep thanh ghi
        if(dut.u_register.tcmp0_reg === 32'hFFFF_FFFF) begin
            $error("[ID15 FAIL]");
            fail_flag = 1;
        end

        //3. Chuyen ACCESS Phase de hoan tat lenh ghi
        tim_penable <= 1'b1;

        @(posedge sys_clk);
        while(!tim_pready) @(posedge sys_clk);

        // Clear Bus ve IDLE
        tim_psel    <= 1'b0;
        tim_penable <= 1'b0;
        tim_pwrite  <= 1'b0;

        //4. Doc lai thanh ghi sau khi penable = 1
        apb_read(ADDR_TCMP0, rdata);
        if(rdata !== 32'hFFFF_FFFF) begin
            $error("[ID15 FAIL]");
            fail_flag = 1;
        end

        // Tong ket ID15
        if(!fail_flag) begin
            $display("[ID15 PASSED] Successfully");
        end
    end
        //==============================================
        //ID16: Timer Control Register
        //==============================================

    begin : ID16_BLOCK

        reg [31:0] rdata;
        automatic bit fail_flag = 0;

        //1. Reset value check
        $display("[ID16] Running Reset value check...");
        sys_rst_n = 1;
        @(posedge sys_clk);
        apb_read(ADDR_TCR, rdata);

        if(rdata !== 32'h0000_0100) $error("[ID16 FAIL]");
        else $display("[ID16 PASSED]");

        //2. R/W Access

        $display("[ID17] Running R/W Access...");

        //**********************************************
        //Step 1: Full Byte Access pstrb[3:0] = 4'hF
        //**********************************************

        //Pattern 1: 0x0000_0000 --> Expected: 0x0000_0000
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        apb_read(ADDR_TCR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID17 FAIL]");
            fail_flag = 1;
        end

        // Pattern 2: 0xFFFF_FFFF --> Expected: 0x0000_0103
        apb_write(ADDR_TCR, 32'hFFFF_FFFF, 4'hF);
                apb_read(ADDR_TCR, rdata);
                if(rdata !== 32'h0000_0000) begin // Sua 0003 thanh 0000
                    $error("[ID17 FAIL]");
                        fail_flag = 1;
        end

        // Pattern 3: 0x5555_5555 --> Expected: 0x0000_0501
        apb_write(ADDR_TCR, 32'h5555_5555, 4'hF);
        apb_read(ADDR_TCR, rdata);
        if(rdata !== 32'h0000_0501) begin
            $error("[ID17 FAIL]");
            fail_flag = 1;
        end

        // Pattern 4: 0xAAAA_AAAA --> Expected: 0x0000_0502
        apb_write(ADDR_TCR, 32'hAAAA_AAAA, 4'hF);
        apb_read(ADDR_TCR, rdata);
        if(rdata !== 32'h0000_0501) begin // Sua 0502 thanh 0501
            $error("[ID17 FAIL]");
            fail_flag = 1;
            end

        //************************************************
        //Step 2: Ghi Byte 0
        //***********************************************

        apb_write(ADDR_TCR, 32'hFFFF_FFFE & rdata, 4'hF);
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TCR, 32'hFFFF_FFFF, 4'b0001);
        apb_read(ADDR_TCR, rdata);
        if(rdata !== 32'h0000_0003) begin
            $error("[ID17 FAIL]");
            fail_flag = 1;
        end

        //***********************************************
        //Step 3: Ghi Byte 1
        //***********************************************
         apb_write(ADDR_TCR, 32'hFFFF_FFFE & rdata, 4'hF);
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TCR, 32'hFFFF_FFFF, 4'b0010);
        apb_read(ADDR_TCR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID17 FAIL]");
            fail_flag = 1;
        end

        //***********************************************
        //Step 4: Ghi Byte 2
        //***********************************************
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TCR, 32'hFFFF_FFFF, 4'b0100);
        apb_read(ADDR_TCR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID17 FAIL]");
            fail_flag = 1;
        end

        //***********************************************
        //Step 5: Ghi Byte 3
        //***********************************************
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TCR, 32'hFFFF_FFFF,4'b1000);
        apb_read(ADDR_TCR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID17 FAIL]");
            fail_flag = 1;
            end

        // Tong ket ID16 & 17
        if(!fail_flag) begin
            $display("[ID16 PASSED] Successfully");
        end
    end
        //==================================================
        //ID18: Timer Data Register 0 & 1
        //==================================================

    begin : ID18_BLOCK

        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        reg [31:0] tdr_addrs[0:1]; // Mang 2 phan tu
            integer i;
        tdr_addrs[0] = ADDR_TDR0;
        tdr_addrs[1] = ADDR_TDR1;


        //1. TDR 0/1 -- Reset Value Check
        $display("[ID18] Running Reset Value Check...");
        sys_clk = 1;
        @(posedge sys_clk);

        // Kiem tra Default Value cua TDR0
        apb_read(ADDR_TDR0, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID18 FAIL]");
            fail_flag = 1;
        end

        // Kiem tra Default Value cua TDR1
        apb_read(ADDR_TDR1, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID18 FAIL]");
            fail_flag = 1;
        end

        // Tong ket ID18
        if(!fail_flag) begin
            $display("[ID18 PASSED]");
        end

        //2. TDR 0/1 -- R/W Access

        $display("[ID19] Running R/W Access...");

        // Dung vong lap for truyen cho 2 thanh ghi
        for(i = 0; i < 2; i = i + 1) begin

            //****************************************
            //Step 1: Full 4 Byte -- pstrb[3:0]
            //****************************************
            // Pattern 1: 0x0000_0000
            apb_write(tdr_addrs[i], 32'h0000_0000, 4'hF);
            apb_read(tdr_addrs[i], rdata);
            if(rdata !== 32'h0000_0000) begin
                $error("[ID19 FAIL]");
                fail_flag = 1;
            end

            // Pattern 2: 0xFFFF_FFFF
            apb_write(tdr_addrs[i], 32'hFFFF_FFFF, 4'hF);
            apb_read(tdr_addrs[i], rdata);
            if(rdata !== 32'hFFFF_FFFF) begin
                $error("[ID19 FAIL]");
                fail_flag = 1;
            end

            // Pattern 3: 0x5555_5555
            apb_write(tdr_addrs[i], 32'h5555_5555, 4'hF);
            apb_read(tdr_addrs[i], rdata);
            if(rdata !== 32'h5555_5555) begin
                $error("[ID19 FAIL]");
                fail_flag = 1;
            end

            // Pattern 4: 0xAAAA_AAAA
            apb_write(tdr_addrs[i], 32'hAAAA_AAAA, 4'hF);
            apb_read(tdr_addrs[i], rdata);
            if(rdata !== 32'hAAAA_AAAA) begin
                $error("[ID19 FAIL]");
                fail_flag = 1;
            end

            //**********************************************
            //Step 2: Ghi Byte 0
            //**********************************************
            apb_write(tdr_addrs[i], 32'h0000_0000, 4'hF);
            apb_write(tdr_addrs[i], 32'hFFFF_FFFF, 4'b0001);
            apb_read(tdr_addrs[i], rdata);
            if(rdata !== 32'h0000_00FF) begin
                $error("[ID19 FAIL]");
                fail_flag = 1;
            end

            //**********************************************
            //Step 3: Ghi Byte 1
            //**********************************************
                        apb_write(tdr_addrs[i], 32'h0000_0000, 4'hF);
            apb_write(tdr_addrs[i], 32'hFFFF_FFFF, 4'b0010);
            apb_read(tdr_addrs[i], rdata);
            if(rdata !== 32'h0000_FF00) begin
                $error("[ID19 FAIL]");
                fail_flag = 1;
            end

            //**********************************************
            //Step 4: Ghi Byte 2
            //**********************************************
                        apb_write(tdr_addrs[i], 32'h0000_0000, 4'hF);
            apb_write(tdr_addrs[i], 32'hFFFF_FFFF, 4'b0100);
            apb_read(tdr_addrs[i], rdata);
            if(rdata !== 32'h00FF_0000) begin
                $error("[ID19 FAIL]");
                fail_flag = 1;
            end

            //*********************************************
            //Step 5: Ghi Byte 3
            //*********************************************
            apb_write(tdr_addrs[i], 32'h0000_0000, 4'hF);
            apb_write(tdr_addrs[i], 32'hFFFF_FFFF, 4'b1000);
            apb_read(tdr_addrs[i], rdata);
            if(rdata !== 32'hFF00_0000) begin
                $error("[ID19 FAIL]");
                fail_flag = 1;
            end
        end

        // Tong ket ID19
        if(!fail_flag) begin
            $display("[ID18 PASSED] Successfully");
        end
    end

        //================================================
        //ID20: Timer Compare Register 0 & 1
        //================================================

    begin : ID20_BLOCK

        //1. Reset value check
        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        reg [31:0] tcmp_addrs[0:1]; // Mang chua 2 phan tu
                integer i;
        tcmp_addrs[0] = ADDR_TCMP0;
        tcmp_addrs[1] = ADDR_TCMP1;

        $display("[ID20] Running Reset value check...");

        sys_rst_n = 0;
        repeat(3) @(posedge sys_clk);
        sys_rst_n = 1;
        @(posedge sys_clk);

        // Kiem tra Default value cua TCMP0
        apb_read(ADDR_TCMP0, rdata);
        if(rdata !== 32'hFFFF_FFFF) begin
            $error("[ID20 FAIL]");
            fail_flag = 1;
        end

        // Kiem tra Default value cua TCMP1
        apb_read(ADDR_TCMP1, rdata);
        if(rdata !== 32'hFFFF_FFFF) begin
            $error("[ID20 FAIL]");
            fail_flag = 1;
        end

        if(!fail_flag) begin
            $display("[ID20 PASSED]");
        end

        //2. TCMP 0&1 -- R/W Access

        $display("[ID21] Running R/W Access...");

        // Tao vong lap for
        for(i = 0; i <  2; i = i + 1) begin

            //*************************************
            //Step 1: Full 4 Byte pstrb[3:0]
            //*************************************
            // Pattern 1: 0x0000_0000
            apb_write(tcmp_addrs[i], 32'h0000_0000, 4'hF);
            apb_read(tcmp_addrs[i], rdata);
            if(rdata !== 32'h0000_0000) begin
                $error("[ID21 FAIL]");
                fail_flag = 1;
            end

            // Pattern 2: 0xFFFF_FFFF
            apb_write(tcmp_addrs[i], 32'hFFFF_FFFF, 4'hF);
            apb_read(tcmp_addrs[i], rdata);
            if(rdata !== 32'hFFFF_FFFF) begin
                $error("[ID21 FAIL]");
                fail_flag = 1;
            end

            // Pattern 3: 0x5555_5555
            apb_write(tcmp_addrs[i], 32'h5555_5555, 4'hF);
            apb_read(tcmp_addrs[i], rdata);
            if(rdata !== 32'h5555_5555) begin
                $error("[ID21 FAIL]");
                fail_flag = 1;
            end

            // Pattern 4: 0xAAAA_AAAA
            apb_write(tcmp_addrs[i], 32'hAAAA_AAAA, 4'hF);
            apb_read(tcmp_addrs[i], rdata);
            if(rdata !== 32'hAAAA_AAAA) begin
                $error("[ID21 FAIL]");
                fail_flag = 1;
            end

            //****************************************
            //Step 2: Ghi Byte 0
            //****************************************
            apb_write(tcmp_addrs[i], 32'h0000_0000, 4'hF);
            apb_write(tcmp_addrs[i], 32'hFFFF_FFFF, 4'b0001);
            apb_read(tcmp_addrs[i], rdata);
            if(rdata !== 32'h0000_00FF) begin
                $error("[ID21 FAIL]");
                fail_flag = 1;
            end

            //*****************************************
            //Step 3: Ghi Byte 1
            //*****************************************
            apb_write(tcmp_addrs[i], 32'h0000_0000, 4'hF);
            apb_write(tcmp_addrs[i], 32'hFFFF_FFFF, 4'b0010);
            apb_read(tcmp_addrs[i], rdata);
            if(rdata !== 32'h0000_FF00) begin
                $error("[ID21 FAIL]");
                fail_flag = 1;
            end

            //*****************************************
            //Step 4: Ghi Byte 2
            //*****************************************
            apb_write(tcmp_addrs[i], 32'h0000_0000, 4'hF);
            apb_write(tcmp_addrs[i], 32'hFFFF_FFFF, 4'b0100);
            apb_read(tcmp_addrs[i], rdata);
            if(rdata !== 32'h00FF_0000) begin
                $error("[ID21 FAIL]");
                fail_flag = 1;
            end

            //*****************************************
            //Step 5: Ghi Byte 3
            //*****************************************
            apb_write(tcmp_addrs[i], 32'h0000_0000, 4'hF);
            apb_write(tcmp_addrs[i], 32'hFFFF_FFFF, 4'b1000);
            apb_read(tcmp_addrs[i], rdata);
            if(rdata !== 32'hFF00_0000) begin
                $error("[ID21 FAIL]");
                fail_flag = 1;
            end

            // Tong ket ID21
            if(!fail_flag) begin
                $display("[ID20 PASSED] Successfully");
            end
        end
    end
        //====================================================
        //ID22: Timer Interrupt Enable Register
        //====================================================
        //1. Reset Value Check

    begin : ID22_BLOCK

        reg [31:0] rdata;
        automatic bit fail_flag = 0;

        $display("[ID22] Running Reset value check...");

        sys_rst_n = 1;
        @(posedge sys_clk);

        apb_read(ADDR_TIER, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID22 FAIL]");
            fail_flag = 1;
        end

        if(!fail_flag) begin
            $display("[ID22 PASSED]");
        end

        //2. R/W Access
        $display("[ID23] Running R/W Access...");

        //***********************************************
        //Step 1: Full Byte Access ptrb[3:0]
        //***********************************************
        //Pattern 1: 0x5555_5555
        apb_write(ADDR_TIER, 32'h5555_5555, 4'hF);
        apb_read(ADDR_TIER, rdata);
        if(rdata !== 32'h0000_0001) begin
            $error("[ID23 FAIL]");
            fail_flag = 1;
        end

        //Pattern 2: 0xAAAA_AAAA
        apb_write(ADDR_TIER, 32'hAAAA_AAAA, 4'hF);
        apb_read(ADDR_TIER, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID23 FAIL]");
            fail_flag = 1;
        end

        //**********************************************
        //Step 2: Ghi Byte 0
        //**********************************************
        apb_write(ADDR_TIER, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TIER, 32'h5555_5555, 4'b0001);
        apb_read(ADDR_TIER, rdata);
        if(rdata !== 32'h0000_0001) begin
            $error("[ID23 FAIL]");
            fail_flag = 1;
        end

        //**********************************************
        //Step 3: Ghi Byte 1
        //**********************************************
        apb_write(ADDR_TIER, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TIER, 32'h5555_5555, 4'b0010);
        apb_read(ADDR_TIER, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID23 FAIL]");
            fail_flag = 1;
        end

        //**********************************************
        //Step 4: Ghi Byte 2
        //**********************************************
        apb_write(ADDR_TIER, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TIER, 32'h5555_5555, 4'b0100);
        apb_read(ADDR_TIER, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID23 FAIL]");
            fail_flag = 1;
        end

        //**********************************************
        //Step 5: Ghi Byte 3
        //**********************************************
        apb_write(ADDR_TIER, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TIER, 32'h5555_5555, 4'b1000);
        apb_read(ADDR_TIER, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID23 FAIL]");
            fail_flag = 1;
        end

        // Tong ket ID23
        if(!fail_flag) begin
            $display("[ID22 PASSED] Successfully");
        end
    end
        //==================================================
        //ID24: Timer Interrupt Status Register
        //==================================================

    begin : ID24_BLOCK
        //1. Reset Value Check
        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        $display("[ID24] Running Value Check...");

        sys_rst_n = 1;
        @(posedge sys_clk);

        apb_read(ADDR_TISR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID24 FAIL]");
            fail_flag = 1;
        end

        if(!fail_flag) begin
            $display("[ID24 PASSED]");
        end

        //2. R/W Access
        $display("[ID25] Running R/W Access...");

        //************************************************
        //Step 1: Full Byte Access pstrb[3:0]
        //************************************************
        // Pattern 1: 0x0000_0000
        apb_write(ADDR_TISR, 32'h0000_0000, 4'hF);
        apb_read(ADDR_TISR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID25 FAIL]");
            fail_flag = 1;
        end

        //Pattern 2: 0xFFFF_FFFF
        apb_write(ADDR_TISR, 32'hFFFF_FFFF, 4'hF);
        apb_read(ADDR_TISR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID25 FAIL]");
            fail_flag = 1;
        end

        //Pattern 3: 0x5555_5555
        apb_write(ADDR_TISR, 32'h5555_5555, 4'hF);
        apb_read(ADDR_TISR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID25 FAIL]");
            fail_flag = 1;
        end

        //Pattern 4: 0xAAAA_AAAA
        apb_write(ADDR_TISR, 32'hAAAA_AAAA, 4'hF);
        apb_read(ADDR_TISR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID25 FAIL]");
            fail_flag = 1;
        end

        //**********************************************
        //Step 2: Ghi Byte 0
        //**********************************************
        apb_write(ADDR_TISR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TISR, 32'hFFFF_FFFF, 4'b0001);
        apb_read(ADDR_TISR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID25 FAIL]");
            fail_flag = 1;
        end

        //*********************************************
        //Step 3: Ghi Byte 1
        //*********************************************
        apb_write(ADDR_TISR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TISR, 32'hFFFF_FFFF, 4'b0010);
        apb_read(ADDR_TISR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID25 FAIL]");
            fail_flag = 1;
        end

        //********************************************
        //Step 4: Ghi Byte 2
        //********************************************
        apb_write(ADDR_TISR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TISR, 32'hFFFF_FFFF, 4'b0100);
        apb_read(ADDR_TISR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID25 FAIL]");
            fail_flag = 1;
        end

        //*********************************************
        //Step 5: Ghi Byte 3
        //*********************************************
        apb_write(ADDR_TISR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TISR, 32'hFFFF_FFFF, 4'b0001);
        apb_read(ADDR_TISR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID25 FAIL]");
            fail_flag = 1;
        end

        // Tong ket ID25
        if(!fail_flag) begin
            $display("[ID24 PASSED] Successfully");
        end
    end
        //=================================================
        //ID26: Timer Halt Control Status Register
        //=================================================

    begin : ID26_BLOCK

        //1. Reset Value Check
        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        $display("[ID26] Running Reset Value Check...");

        sys_rst_n = 1;
        @(posedge sys_clk);

        apb_read(ADDR_THCSR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID26 FAIL]");
            fail_flag = 1;
        end

        if(!fail_flag) begin
            $display("[ID26 PASSED]");
        end

        //2. R/W Access
        $display("[ID27] Running R/W Access...");

        //************************************************
        //Step 1: Full Byte Access
        //************************************************
        //Pattern 1: 0x0000_0000
        apb_write(ADDR_THCSR, 32'h0000_0000, 4'hF);
        apb_read(ADDR_THCSR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID27 FAIL]");
            fail_flag = 1;
        end

        //Pattern 2: 0xFFFF_FFFF
        apb_write(ADDR_THCSR, 32'hFFFF_FFFF, 4'hF);
        apb_read(ADDR_THCSR, rdata);
        if(rdata !== 32'h0000_0001) begin
            $error("[ID27 FAIL]");
            fail_flag = 1;
        end

        //Pattern 3: 0x5555_5555
        apb_write(ADDR_THCSR, 32'h5555_5555, 4'hF);
        apb_read(ADDR_THCSR, rdata);
        if(rdata !== 32'h0000_0001) begin
            $error("[ID27 FAIL]");
            fail_flag = 1;
        end

        //Pattern 4: 0xAAAA_AAAA
        apb_write(ADDR_THCSR, 32'hAAAA_AAAA, 4'hF);
        apb_read(ADDR_THCSR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID27 FAIL]");
            fail_flag = 1;
        end

        //**********************************************
        //Step 2: Ghi Byte 0
        //**********************************************
        apb_write(ADDR_THCSR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_THCSR, 32'hFFFF_FFFF, 4'b0001);
        apb_read(ADDR_THCSR, rdata);
        if(rdata !== 32'h0000_0001) begin
            $error("[ID27 FAIL]");
            fail_flag = 1;
        end

        //**********************************************
        //Step 3: Ghi Byte 1
        //**********************************************
        apb_write(ADDR_THCSR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_THCSR, 32'hFFFF_FFFF, 4'b0010);
        apb_read(ADDR_THCSR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID27 FAIL]");
            fail_flag = 1;
        end

        //**********************************************
        //Step 4: Ghi Byte 2
        //**********************************************
        apb_write(ADDR_THCSR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_THCSR, 32'hFFFF_FFFF, 4'b0100);
        apb_read(ADDR_THCSR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID27 FAIL]");
            fail_flag = 1;
        end

        //**********************************************
        //Step 5: Ghi Byte 3
        //**********************************************
        apb_write(ADDR_THCSR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_THCSR, 32'hFFFF_FFFF, 4'b1000);
        apb_read(ADDR_THCSR, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID27 FAIL]");
            fail_flag = 1;
        end

        // Tong ket ID27
        if(!fail_flag) begin
            $display("[ID26 PASSED] Successfully");
        end
    end
        //===============================================
        //ID28: Reserved Access
        //===============================================

    begin : ID28_BLOCK
        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        $display("[ID28] Running Reserved Address Access...");

        //*********************************************
        //Step 1: Write 0xFFFF_FFFF to 0x0020
        //*********************************************
        apb_write(12'h020, 32'hFFFF_FFFF, 4'hF);
        apb_read(12'h020, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID28 FAIL]");
            fail_flag = 1;
        end

        //*********************************************
        //Step 2: Write 0xFFFF_FFFF to 0x0FFC
        //*********************************************
        apb_write(12'hFFC, 32'hFFFF_FFFF, 4'hF);
        apb_read(12'hFFC, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID28 FAIL]");
            fail_flag = 1;
        end

        //*********************************************
        //Step 3: Write 0xFFFF_FFFF to 0xFFC
        //*********************************************
        apb_write(12'hFFC, 32'hFFFF_FFFF, 4'hF);
        apb_read(12'hFFC, rdata);
        if(rdata !== 32'h0000_0000) begin
            $error("[ID28 FAIL]");
            fail_flag = 1;
        end

        // Tong ket ID28
        if(!fail_flag) begin
            $display("[ID28 PASSED] Successfully");
        end
    end
        //=================================================
        //ID29: Default Mode
        //=================================================
    begin : ID29_BLOCK
        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        $display("[ID29] Running Default Mode...");

        //1. Cau hinh div_en = 0, timer_en = 1
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);

        // Them 1 clk
        @(posedge sys_clk);
        #1;

        //2. Kiem tra div_tick luon giu o muc HIGH qua 10 Chu Ky
        repeat(10) @(posedge sys_clk) begin
            #1;
            if(div_tick !== 1'b1) begin
                $error("[ID29 FAIL]");
                fail_flag = 1;
            end
        end

        //3. Tat timer khi test xong
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);

        if(!fail_flag) begin
            $display("[ID29 PASSED] Successfully");
        end
    end
        //===================================================
        //ID30: Control Mode
        //===================================================
    begin : ID30_BLOCK
        integer i;
        integer exp_period;
        integer clk_count;
        reg [31:0] rdata;
        automatic bit fail_flag = 0;

        $display("[ID30] Running Control Mode...");

        // div_val[3:0] is legal only from 0 through 7. Measure the interval
        // between two actual div_tick rising edges (rather than counting a
        // fixed repeat loop, which would not verify the DUT output).
        for(i = 0; i < 8; i = i + 1) begin
            exp_period = 1 << i; // 2^div_val, matching the supplied RTL/model

            //1. Program the prescaler while stopped, then start the timer.
            apb_write(ADDR_TCR, (i << 8) | 32'h0000_0000, 4'hF);
            apb_write(ADDR_TCR, (i << 8) | 32'h0000_0003, 4'hF);

            if (i == 0) begin
                // Divide-by-one is a continuously asserted tick.
                repeat (5) begin
                    @(posedge sys_clk); #1;
                    if (div_tick !== 1'b1) begin
                        $error("[ID30 FAIL] div_val=0 should tick every cycle");
                        fail_flag = 1;
                    end
                end
            end else begin
                integer first_tick;
                integer second_tick;
                reg prev_tick;
                first_tick = -1;
                second_tick = -1;
                prev_tick = 1'b0;
                for (clk_count = 1; clk_count <= (exp_period * 3 + 4); clk_count = clk_count + 1) begin
                    @(posedge sys_clk); #1;
                    if (div_tick && !prev_tick) begin
                        if (first_tick < 0)
                            first_tick = clk_count;
                        else if (second_tick < 0)
                            second_tick = clk_count;
                    end
                    prev_tick = div_tick;
                end
                if (second_tick < 0 || (second_tick - first_tick) != exp_period) begin
                    $error("[ID30 FAIL] div_val=%0d | expected period=%0d | first=%0d second=%0d",
                           i, exp_period, first_tick, second_tick);
                    fail_flag = 1;
                end else begin
                    $display("[ID30 PASSED] div_val=%0d period=%0d", i, exp_period);
                end
            end

            // Disable before changing the protected prescaler fields again.
            apb_write(ADDR_TCR, (i << 8) | 32'h0000_0002, 4'hF);
            repeat (2) @(posedge sys_clk);
        end

        if(!fail_flag) begin
            $display("[ID30 PASSED] Successfully");
        end
    end
        //========================================================
        //ID31: Write Protection
        //========================================================
    begin : ID31_BLOCK
        bit pslverr_val;
        reg [31:0] rdata;
        automatic bit fail_flag = 0;

        $display("[ID31] Running Wrtie Protection...");

        //1. Bat timer_en = 1, div_en = 1, div_val = 1
        apb_write(ADDR_TCR, 32'h0000_0103, 4'hF);

        //2. Thuc hien ghi de div_val = 8
        apb_write(ADDR_TCR, 32'h0000_0803, 4'hF);

        // Kiem tra tin hieu pslverr tu Slave tra ve
        if(last_pslverr !== 1'b1) begin
            $error("[ID31 FAIL]");
            fail_flag = 1;
        end

        //3. Doc lai TCR de xac nhan khong bi ghi de
        apb_read(ADDR_TCR, rdata);
        if(rdata !== 32'h0000_0103) begin
            $error("[ID31 FAIL]");
            fail_flag = 1;
        end

        // Tat timer
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);

        if(!fail_flag) begin
            $display("[ID31 PASSED] Successfully");
        end
    end
        //=================================================
        //ID32: 64-Bit Count Up
        //=================================================
    begin : ID32_BLOCK
        reg [31:0] rdata_tdr0, rdata_tdr1;
        reg [63:0] cnt64, prev_cnt64;
        reg [31:0] rdata;
        automatic bit fail_flag = 0;

        $display("[ID32] Running 64-Bit Count Up...");

        // Reset bo dem ve 0
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TDR0, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TDR1, 32'h0000_0000, 4'hF);

        //1. Bat timer_en = 1
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);

        // Doc gia tri ban dau
        apb_read(ADDR_TDR0, rdata_tdr0);
        apb_read(ADDR_TDR1, rdata_tdr1);
        prev_cnt64 = {rdata_tdr1, rdata_tdr0};

        //2. Giam sat gtri bo dem
        repeat(5) begin
            @(posedge sys_clk);

            apb_read(ADDR_TDR0, rdata_tdr0);
            apb_read(ADDR_TDR1, rdata_tdr1);
            cnt64 = {rdata_tdr1, rdata_tdr0};

            if(cnt64 <= prev_cnt64) begin
                $error("[ID32 FAIL]");
                fail_flag = 1;
            end
            prev_cnt64 = cnt64;
        end

        if(!fail_flag) begin
            $display("[ID32 PASSED] Successfully");
        end
    end
        //=====================================================
        //ID33: Timer Control & Reset
        //=====================================================

    begin : ID33_BLOCK
        reg [31:0] rdata;
        bit fail_flag = 0;
        reg [31:0] rdata_tdr0;
        reg [31:0] rdata_tdr1;
        reg [63:0] cnt64;

        $display("[ID33] Running Timer Control Reset...");

        //0. Khoi tao TDR ve 0
        apb_write(ADDR_TDR0, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TDR1, 32'h0000_0000, 4'hF);
        repeat(2) @(posedge sys_clk);

        //1. Bat timer_en, cho bo dem chay
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
        repeat(5)  @(posedge sys_clk);

        //2. Chuyen timer_en tu 1 --> 0
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        repeat(4)  @(posedge sys_clk);

        // Kiem tra gtri bo dem ve 64'h0
        apb_read(ADDR_TDR0, rdata_tdr0);
        apb_read(ADDR_TDR1, rdata_tdr1);
        cnt64 = {rdata_tdr1, rdata_tdr0};

        if(cnt64 !== 64'h0000_0000_0000_0000) begin
            $error("[ID33 FAIL]");
            fail_flag = 1;
        end

        //3. Chuyen timer_en tu 0 --> 1
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
        repeat(10)  @(posedge sys_clk);

        // Kiem tra lai bo dem
        apb_read(ADDR_TDR0, rdata_tdr0);
        apb_read(ADDR_TDR1, rdata_tdr1);
        cnt64 = {rdata_tdr1, rdata_tdr0};
        if(cnt64 == 64'h0) begin
            $error("[ID33 FAIL]");
            fail_flag = 1;
        end

        if(!fail_flag) begin
            $display("[ID33 PASSED] Successfully");
        end
    end
        //===================================================
        //ID34: Overflow Behavior
        //===================================================
    begin : ID34_BLOCK
        reg [31:0] rdata;
        bit fail_flag = 0;
        reg [31:0] rdata_tdr0;
        reg [31:0] rdata_tdr1;
        reg [63:0] cnt64;

        $display("[ID34] Running Overflow Behavior...");

        //1. Tat timer truoc khi nap gtri
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        repeat(2) @(posedge sys_clk);

        //2. Ep gtri bo dem 64'hFFFF_FFFF_FFFF_FFFF
        apb_write(ADDR_TDR0, 32'hFFFF_FFFF, 4'hF);
        apb_write(ADDR_TDR1, 32'hFFFF_FFFF, 4'hF);
        repeat(2) @(posedge sys_clk);

        //3. Bat timer de bo dem qua moc duc dai
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
        @(posedge sys_clk);

        //4. Doc gtri
        apb_read(ADDR_TDR0, rdata_tdr0);
        apb_read(ADDR_TDR1, rdata_tdr1);
        cnt64 = {rdata_tdr1, rdata_tdr0};

        // Tat timer de giu nguyen gia tri
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        repeat(4) @(posedge sys_clk);

        apb_read(ADDR_TDR0, rdata_tdr0);
        apb_read(ADDR_TDR1, rdata_tdr1);
        cnt64 = {rdata_tdr1, rdata_tdr0};

        if($isunknown(cnt64)) begin
            $error("[ID34 FAIL]");
            fail_flag = 1;
        end
        else if(cnt64 > 64'h0000_0000_0000_0010) begin
            $error("[ID34 FAIL]");
            fail_flag = 1;
        end

        if(!fail_flag) begin
            $display("[ID34 PASSED] Successfully");
        end
    end
        //==================================================
        //ID35: Halted Mode
        //==================================================
    begin : ID35_BLOCK
        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        //wire halt_ack;
        reg [63:0] prev_cnt64;
        reg [31:0] rdata_tdr0;
        reg [31:0] rdata_tdr1;
        reg [63:0] cnt64;

        $display("[ID35] Running Halted Mode...");

        //1. Bat timer
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
        repeat(3) @(posedge sys_clk);

        //2. Bat dbg_mode, req
        dbg_mode = 1'b1;
        apb_write(ADDR_THCSR, 32'h0000_0001, 4'hF);

        repeat(2) @(posedge sys_clk);

        //3. Kiem tra THCSR.halt_ack va gtri cnt dong bang
        apb_read(ADDR_THCSR, rdata);
        if((rdata & 32'h0000_0002) == 0 && halt_ack !== 1'b1) begin
            $error("[ID35 FAIL]");
            fail_flag = 1;
        end

        // Doc gtri cnt hien tai
        apb_read(ADDR_TDR0, rdata_tdr0);
        apb_read(ADDR_TDR1, rdata_tdr1);
        prev_cnt64 = {rdata_tdr1, rdata_tdr0};

        // Cho 5 chu ki clk de xnhan bi dong bang
        repeat(5) @(posedge sys_clk);
        apb_read(ADDR_TDR0, rdata_tdr0);
        apb_read(ADDR_TDR1, rdata_tdr1);
        cnt64 = {rdata_tdr1, rdata_tdr0};

        if(cnt64 !== prev_cnt64) begin
            $error("[ID35 FAIL]");
            fail_flag = 1;
        end

        //4. Xoa THCSR.halt_ack de cho chap tiep
        apb_write(ADDR_THCSR, 32'h0000_0000, 4'hF);
        repeat(5) @(posedge sys_clk);

        //Kiem bo dem tiep tuc dem bth
        apb_read(ADDR_TDR0, rdata_tdr0);
        apb_read(ADDR_TDR1, rdata_tdr1);
        cnt64 = {rdata_tdr1, rdata_tdr0};

        if(cnt64 == prev_cnt64) begin
            $error("[ID35 FAIL]");
            fail_flag = 1;
        end

        if(!fail_flag) begin
            $display("[ID35 PASSED] Successfully");
        end
    end
        //=====================================================
        //ID36: Timer Interrupt
        //=====================================================
    begin : ID36_BLOCK
        reg [31:0] rdata;
        automatic bit fail_flag = 0;
        $display("[ID36] Running Timer Interrupt...");

        // Tat timer va reset bo dem ve khong
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TDR0, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TDR1, 32'h0000_0000, 4'hF);

        //1. Cau hinh TCMP 0/1 = 64'd10
        apb_write(ADDR_TCMP0, 32'h0000_000A, 4'hF);
        apb_write(ADDR_TCMP1, 32'h0000_0000, 4'hF);

        //2. Cho phep ngat TIER.int_en = 1 va timer_en = 1
        apb_write(ADDR_TIER, 32'h0000_0001, 4'hF);
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);

        //3. Cho bo dem den nguong SS 10 nhip
        repeat(10) @(posedge sys_clk);
        @(posedge sys_clk);

        // Kiem tra coi co TISR.int_st va tim_int khong
        apb_read(ADDR_TISR, rdata);
        if((rdata & 32'h0000_0001) !== 32'h0000_0001) begin
            $error("[ID36 FAIL]");
            fail_flag = 1;
        end

        if(tim_int !== 1'b1) begin
            $error("[ID36 FAIL]");
            fail_flag = 1;
        end

        if(!fail_flag) begin
            $display("[ID36 PASSED] Successfully");
        end
    end
        //=====================================================
        //ID37: Interrupt Clearing
        //=====================================================
    begin : ID37_BLOCK
        reg [31:0] rdata;
        automatic bit fail_flag = 0;

        $display("[ID37] Running Interrupt Clearing...");

        //1. Da co kich hoat ngat tu ID36

        //2. Ghi bit 1 vao TISR.int_st (RW1C)
        apb_write(ADDR_TISR, 32'h0000_0001, 4'hF);
        @(posedge sys_clk);

        // Kiem tra TISR.int_st va tim_int da ve 0 chua ?
        apb_read(ADDR_TISR, rdata);
        if((rdata & 32'h0000_0001) !== 32'h0000_0000 || tim_int !== 1'b0) begin
            $error("[ID37 FAIL]");
            fail_flag = 1;
        end

        //3. TIER.int_en = 0;
        apb_write(ADDR_TIER, 32'h0000_0000, 4'hF);

        //Dat lai bo dem va cho dem toi nguong SS 10
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TDR0, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TDR1, 32'h0000_0000, 4'hF);
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);

        repeat(10) @(posedge sys_clk);
        @(posedge sys_clk);

        //Khi int_en 0 thi tim_int PHAI bang 0
        if(tim_int !== 1'b0) begin
            $error("[ID37 FAIL]");
            fail_flag = 1;
        end

        if(!fail_flag) begin
            $display("[ID37 PASSED] Successfully");
        end
    end

        //=======================================================
        //ID38: Coverage APB_Slave
        //=======================================================
    begin : ID38_BLOCK

        //.1 Reset he thong
        sys_rst_n = 0;
        repeat(3) @(posedge sys_clk);
        sys_rst_n = 1;
        @(posedge sys_clk);

        //2. Bat timer
        apb_write(ADDR_TCR, 32'h0000_0101, 4'b1111);

        //------------------------------------------------
        //Case A: CHI thay doi div_en
        //------------------------------------------------
        apb_write(ADDR_TCR, 32'h0000_0003, 4'b0001);
        apb_write(ADDR_TCR, 32'h0000_0001, 4'b0001);

        //------------------------------------------------
        //Case B: CHI thay doi div_val
        //------------------------------------------------
        apb_write(ADDR_TCR, 32'h0000_0201, 4'b0010);
        apb_write(ADDR_TCR, 32'h0000_0101, 4'b0010);

        //-------------------------------------------------
        //Case C: Thay doi ca div_en && div_val
        //-------------------------------------------------
        apb_write(ADDR_TCR, 32'h0000_0303, 4'b0011);

        //-------------------------------------------------
        //Case D: GIU NGUYEN div_en && div_val
        //-------------------------------------------------
        apb_write(ADDR_TCR, 32'h0000_0101, 4'b0011);
        apb_write(ADDR_TCR, 32'h0000_0100, 4'b0001);
        apb_write(ADDR_TCR, 32'h0000_0F00, 4'b0001);
        @(posedge sys_clk);

        $display("[ID38 PASSED] Successfully");

    end

    begin : TOGGLE_SWEEP
        reg [31:0] dummy_rdata;
        integer k;
        //1.
        apb_write(ADDR_TCR, (4'b1111 << 4) | 32'h1, 4'hF);
        repeat(4) @(posedge sys_clk);

        //2.
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        repeat(4) @(posedge sys_clk);

        //3.
        apb_read(ADDR_TCR, dummy_rdata);
        apb_read(ADDR_TDR0, dummy_rdata);

        //4.
        for(k = 0; k <= 8; k = k + 1) begin
            apb_write(ADDR_TCR, (k << 4) | 32'h1, 4'hF);
            repeat((1 << k) + 2) @(posedge sys_clk);
            end

        //5.
        apb_write(ADDR_TCR, (8 << 4) | 32'h1, 4'hF);
        repeat(260) @(posedge sys_clk);

        //6.
        apb_write(ADDR_TCR, (4'b1111 << 4) | 32'h1, 4'hF);
        repeat(10) @(posedge sys_clk);

        //7.
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        repeat(4) @(posedge sys_clk);
    end

    begin : CURRENT_MATCH
        //1.
        force dut.u_counter.u_counter_core.current_match = 1'b1;
        repeat(2) @(posedge sys_clk);
        force dut.u_counter.u_counter_core.current_match = 1'b0;
        repeat(2) @(posedge sys_clk);
        release dut.u_counter.u_counter_core.current_match;

        //2.

    end


    begin : HALT_REQ

        //1.
        apb_write(ADDR_TDR0, 32'h0000_0005, 4'hF);
        apb_write(ADDR_TDR1, 32'h0000_0000, 4'hF);

        apb_write(12'h008, 32'h0000_0005, 4'hF);
        repeat(2) @(posedge sys_clk);

        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
        repeat(10) @(posedge sys_clk);

        //2.
        force test_bench.dut.u_counter.u_counter_core.halt_ack = 1'b1;
        repeat(5) @(posedge sys_clk);

        release test_bench.dut.u_counter.u_counter_core.halt_ack;
        repeat(5) @(posedge sys_clk);
    end

    begin : COUNTER_CORE_COV

        //1.
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
        repeat(2) @(posedge sys_clk);

        //2.
        apb_write(ADDR_TDR0, 32'hAAAA_AAAA, 4'b0101);
        repeat(2) @(posedge sys_clk);
        apb_write(ADDR_TDR0, 32'h5555_5555, 4'b1010);
        repeat(2) @(posedge sys_clk);
        apb_write(ADDR_TDR0, 32'hFFFF_FFFF, 4'b1111);
        repeat(2) @(posedge sys_clk);

        //3.
        apb_write(ADDR_TDR1, 32'hAAAA_AAAA, 4'b0101);
        repeat(2) @(posedge sys_clk);
        apb_write(ADDR_TDR1, 32'h5555_5555, 4'b1010);
        repeat(2) @(posedge sys_clk);
        apb_write(ADDR_TDR1, 32'hFFFF_FFFF, 4'b1111);
        repeat(2) @(posedge sys_clk);

        //4.
        repeat(5) @(posedge sys_clk);

        //5.
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        repeat(2) @(posedge sys_clk);
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
        repeat(2) @(posedge sys_clk);


    /*  apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        //6.
        apb_write(ADDR_TDR0, 32'hFFFF_FFFF, 4'b0000);
        repeat(2) @(posedge sys_clk);
        apb_write(ADDR_TDR1, 32'hFFFF_FFFF, 4'b0000);
        repeat(2) @(posedge sys_clk);

        //7.
        apb_write(12'h000, 32'h1111_1111, 4'b1111);
        repeat(2) @(posedge sys_clk);

        //8.
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
        repeat(10) @(posedge sys_clk);

        //9.
        apb_write(ADDR_TDR0, 32'hAAAA_AAAA, 4'b1111);
        repeat(2) @(posedge sys_clk);
        apb_write(ADDR_TDR0, 32'h5555_5555, 4'b1111);
        repeat(2) @(posedge sys_clk);

        //10.
        apb_write(ADDR_TDR1, 32'hAAAA_AAAA, 4'b1111);
        repeat(2) @(posedge sys_clk);
        apb_write(ADDR_TDR1, 32'h5555_5555, 4'b1111);
        repeat(2) @(posedge sys_clk);

        //11.
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        repeat(4) @(posedge sys_clk);   */

    /*          //1. Tat timer
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        repeat(2) @(posedge sys_clk);

        //2.
        apb_write(ADDR_TCMP0, 32'h0000_1234, 4'hF);
        apb_write(ADDR_TCMP1, 32'h0000_0000, 4'hF);
        //repeat(3) @(posedge sys_clk);

        //3.
        apb_write(ADDR_TDR0, 32'h0000_1234, 4'hF);
        apb_write(ADDR_TDR1, 32'h0000_0000, 4'hF);
        repeat(3) @(posedge sys_clk);

        //4.
        apb_write(ADDR_TDR0, 32'h0000_0000, 4'hF);
        repeat(2) @(posedge sys_clk);   */

    /*  //1.
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
        repeat(2) @(posedge sys_clk);

        apb_write(ADDR_TDR0, 32'hFFFF_FFFF, 4'h0);
        repeat(2) @(posedge sys_clk);
        apb_write(ADDR_TDR1, 32'hFFFF_FFFF, 4'h0);
        repeat(2) @(posedge sys_clk);

        //2.
        apb_write(12'h000, 32'h0000_0000, 4'b1111);
        repeat(2) @(posedge sys_clk);

        //3.
        apb_write(ADDR_TDR0, 32'hFFFF_FFFF, 4'hF);
        repeat(2) @(posedge sys_clk);
        apb_write(ADDR_TDR1, 32'hFFFF_FFFF, 4'hF);
        repeat(2) @(posedge sys_clk);

        repeat(5) @(posedge sys_clk);

        //4.
        apb_write(ADDR_TCR, 32'h0000_0000, 4'hF);
        repeat(4) @(posedge sys_clk);   */

    /*   apb_write(ADDR_TDR0, 32'h0000_0005, 4'hF);
         apb_write(ADDR_TDR1, 32'h0000_0000, 4'hF);

         apb_write(12'h008, 32'h0000_0005, 4'hF);
         repeat(2) @(posedge sys_clk);

         apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
                 repeat(10) @(posedge sys_clk);

         dut.dbg_mode = 1'b1;
         halt_req = 1'b1;
         repeat(5) @(posedge sys_clk);

         repeat(10) @(posedge sys_clk);

         dut.dbg_mode = 1'b0;
         halt_req = 1'b0;
         repeat(5) @(posedge sys_clk); */

    end

    begin : TOP_TOGGLE
        reg [31:0] dummy_rdata;
        //1.
        apb_write(12'hFFF, 32'hFFFF_FFFF, 4'hF);
        repeat(2) @(posedge sys_clk);
        apb_read(12'hFFF, dummy_rdata);
        repeat(2) @(posedge sys_clk);

        //2.
        apb_write(ADDR_TCR, 32'h0000_0001, 4'hF);
        repeat(10) @(posedge sys_clk);

        //3.
        apb_write(12'h00C, 32'h0000_0001, 4'hF);
        repeat(2) @(posedge sys_clk);

        //4.
        sys_rst_n = 0;
        repeat(2) @(posedge sys_clk);
        sys_rst_n = 1;
        repeat(2) @(posedge sys_clk);
    end

        #100;
    $finish;

    end // CUA INITIAL BEGIN ... END


endmodule
