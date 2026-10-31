class CounterGoldenModel:
    """
    Cycle-accurate & Bit-accurate Golden Model cho module `counter`
    (bao gồm `counter_divider` và `counter_core`).
    """

    MASK_8  = 0xFF
    MASK_12 = 0xFFF
    MASK_32 = 0xFFFFFFFF
    MASK_64 = 0xFFFFFFFFFFFFFFFF

    def __init__(self):
        # Thanh ghi nội bộ (State Registers)
        self.div_cnt = 0      # reg [7:0] div_cnt trong counter_divider
        self.counter_val = 0  # reg [63:0] counter_val trong counter_core

        # Các đường dây tổ hợp (Combinational Wires)
        self.halt_ack = 0
        self.div_tick = 0
        self.cmp_match_evt = 0

    def reset_async(self):
        """Mô phỏng sườn âm negedge sys_rst_n (sys_rst_n == 0)"""
        self.div_cnt = 0
        self.counter_val = 0
        self.halt_ack = 0
        self.div_tick = 0
        self.cmp_match_evt = 0

    def eval_combinational(
        self,
        timer_en: int,
        div_en: int,
        div_val: int,
        dbg_mode: int,
        halt_req: int,
        tcmp_val: int
    ) -> dict:
        """
        Tính toán các tín hiệu tổ hợp dựa trên trạng thái thanh ghi hiện tại
        và tín hiệu đầu vào hiện tại (trước hoặc sau sườn posedge sys_clk).
        """
        timer_en &= 0x1
        div_en   &= 0x1
        div_val  &= 0xF
        dbg_mode &= 0x1
        halt_req &= 0x1
        tcmp_val &= self.MASK_64

        # --- Tổ hợp trong counter_divider ---
        # assign div_limit = (8'd1 << div_val) - 8'd1;
        shifted_8bit = (1 << div_val) & self.MASK_8
        div_limit = (shifted_8bit - 1) & self.MASK_8

        # assign match = (div_cnt == div_limit);
        match = 1 if (self.div_cnt == div_limit) else 0

        # assign clr_div_cnt = match || (!timer_en);
        clr_div_cnt = 1 if (match or not timer_en) else 0

        # assign div_cnt_next = clr_div_cnt ? 8'd0 : (div_cnt + 8'd1);
        div_cnt_next = 0 if clr_div_cnt else ((self.div_cnt + 1) & self.MASK_8)

        # assign is_halted = dbg_mode && halt_req;
        # assign halt_ack  = is_halted;
        is_halted = 1 if (dbg_mode and halt_req) else 0
        self.halt_ack = is_halted

        # assign div_tick = !is_halted && (div_en ? (match && timer_en) : timer_en);
        if is_halted:
            self.div_tick = 0
        else:
            if div_en:
                self.div_tick = 1 if (match and timer_en) else 0
            else:
                self.div_tick = timer_en

        # --- Tổ hợp trong counter_core ---
        # assign and_gate_out = div_tick && (!halt_ack);
        and_gate_out = 1 if (self.div_tick and not self.halt_ack) else 0

        # assign cmp_match_evt = (counter_val == tcmp_val);
        self.cmp_match_evt = 1 if (self.counter_val == tcmp_val) else 0

        return {
            "is_halted": is_halted,
            "div_cnt_next": div_cnt_next,
            "and_gate_out": and_gate_out,
        }

    def step_clk(
        self,
        sys_rst_n: int = 1,
        reg_addr: int = 0,
        reg_wdata: int = 0,
        reg_wstrb: int = 0,
        wr_en: int = 0,
        has_error: int = 0,
        timer_en: int = 0,
        div_en: int = 0,
        div_val: int = 0,
        tcmp_val: int = 0xFFFFFFFFFFFFFFFF,
        tdr_val: int = 0,
        tdr_clr_req: int = 0,  # Không được sử dụng trong RTL hiện tại
        dbg_mode: int = 0,
        halt_req: int = 0,
    ) -> dict:
        """
        Mô phỏng 1 chu kỳ xung nhịp (posedge sys_clk):
        1. Đánh giá mạch tổ hợp trước sườn clock (Pre-clock).
        2. Cập nhật đồng thời các thanh ghi (Non-blocking <=).
        3. Cập nhật lại ngõ ra tổ hợp sau khi thanh ghi đổi trạng thái (Post-clock).
        """
        # Ép kiểu bit-width chuẩn xác như đầu vào phần cứng
        sys_rst_n &= 0x1
        reg_addr  &= self.MASK_12
        reg_wdata &= self.MASK_32
        reg_wstrb &= 0xF
        wr_en     &= 0x1
        has_error &= 0x1
        timer_en  &= 0x1
        div_en    &= 0x1
        div_val   &= 0xF
        tcmp_val  &= self.MASK_64
        tdr_val   &= self.MASK_64
        dbg_mode  &= 0x1
        halt_req  &= 0x1

        # 1. Xử lý Reset bất đồng bộ nếu sys_rst_n == 0
        if not sys_rst_n:
            self.reset_async()
            return self.get_outputs()

        # 2. Pha 1: Tính giá trị tổ hợp ngay trước sườn lên sys_clk
        comb = self.eval_combinational(
            timer_en=timer_en,
            div_en=div_en,
            div_val=div_val,
            dbg_mode=dbg_mode,
            halt_req=halt_req,
            tcmp_val=tcmp_val
        )

        # Biến tạm giữ giá trị kế tiếp của thanh ghi (mô phỏng <= trong Verilog)
        next_div_cnt = self.div_cnt
        next_counter_val = self.counter_val

        # --- Cập nhật thanh ghi của counter_divider ---
        if not comb["is_halted"]:
            next_div_cnt = comb["div_cnt_next"]

        # --- Cập nhật thanh ghi của counter_core ---
        if not timer_en:
            # 1. Nếu timer tắt --> luôn bám theo TDR
            next_counter_val = tdr_val
        elif wr_en and (not has_error) and (reg_addr == 0x004):
            # 2. Ghi đè trực tiếp vào TDR0 (32-bit thấp)
            for byte_idx in range(4):
                if (reg_wstrb >> byte_idx) & 0x1:
                    shift = byte_idx * 8
                    byte_mask = ~(0xFF << shift) & self.MASK_64
                    byte_val = ((reg_wdata >> shift) & 0xFF) << shift
                    next_counter_val = (next_counter_val & byte_mask) | byte_val
        elif wr_en and (not has_error) and (reg_addr == 0x008):
            # 3. Ghi đè trực tiếp vào TDR1 (32-bit cao)
            for byte_idx in range(4):
                if (reg_wstrb >> byte_idx) & 0x1:
                    src_shift = byte_idx * 8
                    dst_shift = 32 + (byte_idx * 8)
                    byte_mask = ~(0xFF << dst_shift) & self.MASK_64
                    byte_val = ((reg_wdata >> src_shift) & 0xFF) << dst_shift
                    next_counter_val = (next_counter_val & byte_mask) | byte_val
        elif comb["and_gate_out"]:
            # 4. Đếm tiến bình thường
            next_counter_val = (self.counter_val + 1) & self.MASK_64

        # 3. Pha 2: Chốt thanh ghi tại sườn dương sys_clk
        self.div_cnt = next_div_cnt
        self.counter_val = next_counter_val

        # 4. Pha 3: Cập nhật lại các đầu ra tổ hợp sau khi thanh ghi đã đổi giá trị
        self.eval_combinational(
            timer_en=timer_en,
            div_en=div_en,
            div_val=div_val,
            dbg_mode=dbg_mode,
            halt_req=halt_req,
            tcmp_val=tcmp_val
        )

        return self.get_outputs()

    def get_outputs(self) -> dict:
        """Trả về toàn bộ các cổng output của module top `counter`"""
        return {
            "counter_val": self.counter_val,
            "cmp_match_evt": self.cmp_match_evt,
            "halt_ack": self.halt_ack,
            # Tín hiệu nội bộ phục vụ debug sâu nếu cần
            "internal_div_cnt": self.div_cnt,
            "internal_div_tick": self.div_tick,
        }


# =====================================================================
# KỊCH BẢN CHẠY THỬ & SINH TEST VECTOR (SELF-TEST)
# =====================================================================
if __name__ == "__main__":
    gm = CounterGoldenModel()

    print("=== 1. TEST RESET ===")
    out = gm.step_clk(sys_rst_n=0)
    print(f"Reset -> counter_val={out['counter_val']:#x}, div_cnt={out['internal_div_cnt']}")

    print("\n=== 2. TEST NẠP TDR KHI TIMER TẮT (timer_en = 0) ===")
    out = gm.step_clk(sys_rst_n=1, timer_en=0, tdr_val=0x0000_0000_0000_0010)
    print(f"Load TDR -> counter_val={out['counter_val']:#x}")

    print("\n=== 3. TEST ĐẾM CHIA TẦN (div_en = 1, div_val = 2 -> chia 4) ===")
    for cycle in range(1, 9):
        out = gm.step_clk(
            sys_rst_n=1,
            timer_en=1,
            div_en=1,
            div_val=2,  # div_limit = (1<<2)-1 = 3 (đếm 0,1,2,3 -> tăng counter_val)
            tcmp_val=0x12
        )
        print(
            f"Cycle {cycle:02d} | div_cnt={out['internal_div_cnt']} "
            f"| counter_val={out['counter_val']:#x} | cmp_match_evt={out['cmp_match_evt']}"
        )

    print("\n=== 4. TEST GHI ĐÈ KHI TIMER ĐANG CHẠY (reg_addr = 0x004, wstrb = 4'b0011) ===")
    out = gm.step_clk(
        sys_rst_n=1,
        timer_en=1,
        wr_en=1,
        has_error=0,
        reg_addr=0x004,
        reg_wdata=0xAABB_CCDD,
        reg_wstrb=0b0011  # Chỉ ghi 2 byte thấp (0xCCDD)
    )
    print(f"Overwrite TDR0 -> counter_val={out['counter_val']:#x}")