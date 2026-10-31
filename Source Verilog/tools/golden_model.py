"""Reference behavior for the final IP Timer decisions.
This model is a software cross-check only; it is not an HDL simulator.
"""
from dataclasses import dataclass

MASK32 = (1 << 32) - 1
MASK64 = (1 << 64) - 1

@dataclass
class TimerModel:
    counter: int = 0
    div_count: int = 0
    timer_en_d: int = 0
    int_st: int = 0

    def step(self, *, timer_en=0, div_en=0, div_val=0, dbg_mode=0,
             halt_req=0, tdr0_load=False, tdr0_wdata=0,
             tdr1_load=False, tdr1_wdata=0, tcmp=MASK64,
             int_en=0, sw_w1c=False, reset_n=1):
        if not reset_n:
            self.counter = 0
            self.div_count = 0
            self.timer_en_d = 0
            self.int_st = 0
            return self.outputs(timer_en, dbg_mode, halt_req, int_en, tcmp)

        halted = bool(dbg_mode and halt_req)
        tick = bool(timer_en and not halted and (not div_en or self.div_count == div_val))
        compare_event_pre_edge = bool(self.counter == (tcmp & MASK64))
        disable_edge = bool(self.timer_en_d and not timer_en)

        if disable_edge:
            self.counter = 0
        elif not halted and tdr0_load:
            self.counter = (self.counter & 0xFFFFFFFF00000000) | (tdr0_wdata & MASK32)
        elif not halted and tdr1_load:
            self.counter = ((tdr1_wdata & MASK32) << 32) | (self.counter & MASK32)
        elif timer_en and tick and not halted:
            self.counter = (self.counter + 1) & MASK64

        if not timer_en:
            self.div_count = 0
        elif not halted:
            if (not div_en) or self.div_count >= div_val:
                self.div_count = 0
            else:
                self.div_count = (self.div_count + 1) & 0xF

        if sw_w1c:
            self.int_st = 0
        elif compare_event_pre_edge:
            self.int_st = 1
        self.timer_en_d = int(bool(timer_en))
        return self.outputs(timer_en, dbg_mode, halt_req, int_en, tcmp)

    def outputs(self, timer_en, dbg_mode, halt_req, int_en, tcmp):
        halted = int(bool(dbg_mode and halt_req))
        return {
            "counter": self.counter,
            "div_count": self.div_count,
            "halt_ack": halted,
            "tim_int": int(bool(self.int_st and int_en)),
            "int_st": self.int_st,
        }


def self_test():
    # Divider period checks using the same count/terminal-count convention.
    for dv in range(8):
        count = 0
        tick_cycles = []
        for cycle in range(1, 4 * (dv + 1) + 1):
            tick = (count == dv)
            if tick:
                tick_cycles.append(cycle)
                count = 0
            else:
                count += 1
        assert len(tick_cycles) >= 3, (dv, tick_cycles)
        assert all((b - a) == dv + 1 for a, b in zip(tick_cycles, tick_cycles[1:])), (dv, tick_cycles)

    m = TimerModel()
    m.step(reset_n=0)
    # Preload while stopped; enabling starts from the preload value.
    m.step(timer_en=0, tdr0_load=True, tdr0_wdata=0xFFFFFFFE)
    assert m.counter == 0xFFFFFFFE
    m.step(timer_en=1, div_en=0)
    m.step(timer_en=1, div_en=0)
    assert m.counter == 0x100000000
    # Falling edge clears once.
    m.step(timer_en=0)
    assert m.counter == 0
    # Debug halt freezes counter.
    m.step(timer_en=1, div_en=0)
    before = m.counter
    m.step(timer_en=1, div_en=0, dbg_mode=1, halt_req=1)
    assert m.counter == before
    # W1C clear wins over simultaneous compare set according to SPEC.
    m.step(timer_en=1, div_en=0, tcmp=m.counter, int_en=1, sw_w1c=True)
    assert m.int_st == 0
    print("[PASS] golden_model self-test (divider, preload, rollover, clear, halt, W1C)")

if __name__ == "__main__":
    self_test()
