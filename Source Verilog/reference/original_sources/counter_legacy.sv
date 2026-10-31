// ===============================================
// 1. SUB-MODULE 1: COUNTER-DIVIDER
// ==============================================
/* verilator lint_off DECLFILENAME */
module counter_divider(
	// Clock, Reset 
	input wire       sys_clk,
	input wire       sys_rst_n,

	input wire       timer_en,
	input wire       div_en,
	input wire [3:0] div_val,
	input wire 	 dbg_mode,
	input wire 	 halt_req,

	output wire 	 halt_ack,
	output wire 	 div_tick // counter_en
);

	// Internal Signals 
	reg [7:0] 	 div_cnt;
	wire [7:0]	 div_cnt_next;
	wire [7:0] 	 div_limit;
	wire 		 match;
	wire 		 clr_div_cnt;
        wire 		 is_halted;

	//1. Khoi decoder giai ma tu div_val[3:0] sang div_limit
	assign div_limit = (8'd1 << div_val) - 8'd1; // (2 mu div_val)-1
	
	//2. Khoi Comparator (==?)
	assign match = (div_cnt == div_limit);

	//3. Cong MUX 1
	assign clr_div_cnt = match || (!timer_en); 
	assign div_cnt_next = clr_div_cnt ? 8'd0 : (div_cnt + 8'd1);

	//4. Khoi Register (Counter_Divider)
	assign is_halted = dbg_mode && halt_req;
   	assign halt_ack  = is_halted;	
	
	always @(negedge sys_rst_n or posedge sys_clk) begin
		if(!sys_rst_n) begin
			div_cnt <= 8'h0;       
		end        
		else if(!is_halted) begin
			div_cnt <= div_cnt_next;       
		end 
	end 

	//5. Cong MUX2
	assign div_tick = !is_halted && (div_en ? (match && timer_en) : timer_en);

endmodule 

// ================================================
//2. SUB-MODULE 2: COUNTER-CORE 
//=================================================
/* verilator lint_off UNUSEDSIGNAL */
module counter_core(
	// Reset Clock
	input wire        sys_rst_n,
	input wire        sys_clk,

	// Tin hieu dieu khien APB/Bus
	input wire [11:0] reg_addr,
	input wire [31:0] reg_wdata,
	input wire [3:0]  reg_wstrb,
	input wire        wr_en,
	input wire        has_error,

	// Tin hieu dieu khien 
	input wire        timer_en,
	input wire        div_tick,
	input wire        halt_ack,
	input wire        dbg_mode,
	input wire [63:0] tcmp_val,
	input wire [63:0] tdr_val, // Nhan gtri nap ban dau tu Register
	input wire        tdr_clr_req,

	// Dau ra 
	output reg [63:0] counter_val,
	output wire       cmp_match_evt // Interrupt
);

	// Internal Signals 
	wire        and_gate_out;

	// Tao xung ngat 1 chu ki 
	/* verilator lint_off UNUSEDSIGNAL */
	wire        current_match;
	/* verilator lint_on UNUSEDSIGNAL */

	//1. Cong AND (tick && !halt_ack)
	assign and_gate_out = div_tick && (!halt_ack);


	//2. Logic cap nhat Counter Core 
	always @(negedge sys_rst_n or posedge sys_clk) begin
		if(!sys_rst_n) begin
			counter_val <= 64'h0;       
		end        
		
	       	//1.  Neu timer tat --> luon bam theo TDR
	       	else if(!timer_en) begin
			counter_val <= tdr_val;       
		end 

		//2. Timer dang bat ma CPU co tinh ghi de -->  Ghi vao TDR0
                else if(wr_en && !has_error && (reg_addr[11:0] == 12'h004)) begin
                         if(reg_wstrb[0]) counter_val[7:0]    <= reg_wdata[7:0];
                         if(reg_wstrb[1]) counter_val[15:8]   <= reg_wdata[15:8];
                         if(reg_wstrb[2]) counter_val[23:16]  <= reg_wdata[23:16];
                         if(reg_wstrb[3]) counter_val[31:24]  <= reg_wdata[31:24];
                end
                //3.  Timer dang bat ma CPU co tinh ghi de --> Ghi vao TDR1
                else if(wr_en && !has_error && (reg_addr[11:0] == 12'h008)) begin
                         if(reg_wstrb[0]) counter_val[39:32]    <= reg_wdata[7:0];
			 if(reg_wstrb[1]) counter_val[47:40]   <= reg_wdata[15:8];
			 if(reg_wstrb[2]) counter_val[55:48]  <= reg_wdata[23:16];
			 if(reg_wstrb[3]) counter_val[63:56]  <= reg_wdata[31:24];
		end   
	      	
		//4. Neu k co ai ghi de --> Dem tien binh thuong
		else if(and_gate_out) begin
			counter_val <= counter_val + 64'd1;       
		end 
	end 

	assign cmp_match_evt = (counter_val == tcmp_val);	

endmodule

// ===============================================
//3. MODULE COUNTER (TOP)
//================================================
module counter(
	// Reset Clock 
	input wire         sys_rst_n,
	input wire         sys_clk,

	// Signal tu APB sang 
	input wire [11:0] reg_addr,
	input wire [31:0] reg_wdata,
	input wire [3:0]  reg_wstrb,
	input wire        wr_en,
	input wire        has_error,

	// Signals tu Register Block 
	input wire         timer_en,
	input wire         div_en,
	input wire [3:0]   div_val,
	input wire [63:0]  tcmp_val,
	input wire [63:0]  tdr_val,
	input wire         tdr_clr_req,

	// Signals Debug Mode && Halted 
	input wire         dbg_mode,
	input wire         halt_req,
	output wire        halt_ack,

	// Dau ra 
	output wire [63:0] counter_val,
	output wire        cmp_match_evt
);

	// Day ket noi giua 2 sub-modules 
	wire tick_w;

	// Instantiate 1: Bo dem chia tan Counter_Divider
	counter_divider u_counter_divider(
		.sys_rst_n	(sys_rst_n),
		.sys_clk	(sys_clk),
		.timer_en	(timer_en),
		.div_en		(div_en),
		.div_val	(div_val),
		.dbg_mode	(dbg_mode),
		.halt_req	(halt_req),
		.halt_ack	(halt_ack),
		.div_tick	(tick_w)
	);

	// Instantiate 2: Bo dem chinh Counter_Core 
	counter_core u_counter_core(
		.sys_rst_n	(sys_rst_n),
		.sys_clk	(sys_clk),
		.reg_addr       (reg_addr),
		.reg_wdata      (reg_wdata),
		.reg_wstrb      (reg_wstrb),
		.wr_en          (wr_en),
		.has_error      (has_error),
		.timer_en	(timer_en),
		.div_tick	(tick_w),
		.halt_ack	(halt_ack),
		.dbg_mode       (dbg_mode),
		.tcmp_val	(tcmp_val),
		.tdr_val        (tdr_val),
		.tdr_clr_req    (tdr_clr_req),
		.counter_val	(counter_val),
		.cmp_match_evt	(cmp_match_evt)
	);

endmodule
