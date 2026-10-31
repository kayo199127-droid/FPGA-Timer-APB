# Gowin FPGA Implementation Handoff

## Team ownership relevant to FPGA handoff

- Member 1, Phùng Văn Tân (SE203222): Timer Divider.
- Member 2, Hoàng Trung Hiếu (SE203208): APB Slave Interface.
- Member 3, Hoàng Quốc Trí (SE203836): System Integration and Verification; owns the integrated `timer_top` handoff.
- Member 4, Lê Dương Hoàng Khang (SE204508): Timer Core.
- Member 5, Trần Định Quốc (CE202008): Register Bank.


`timer_top` is an IP peripheral, not a standalone board-level top. A board project must contain or connect an APB master/interconnect that drives the peripheral.

Before creating a Gowin `.cst` file, record:

1. Exact board name and revision.
2. Exact Gowin FPGA device/part number.
3. Board system-clock frequency and physical clock pin.
4. Reset pin, polarity and any board-level conditioning.
5. APB master or SoC wrapper and base-address mapping.
6. Available debug-mode and interrupt routing.

## Implementation checklist

- [ ] Create/open the Gowin project and select the exact device.
- [ ] Add `rtl/apb_slave.v`, `rtl/register.v`, `rtl/timer_divider.v`, `rtl/timer_core.v`, `rtl/counter.sv`, and `rtl/timer_top.v`.
- [ ] Add the board-level APB master/wrapper and select that wrapper as the synthesis top.
- [ ] Create clock and pin constraints from the official board schematic/pinout.
- [ ] Run synthesis and resolve all errors and unexplained critical warnings.
- [ ] Run place-and-route and timing analysis.
- [ ] Generate the bitstream and program the board.
- [ ] Perform APB read/write, counter, interrupt and debug-halt tests on hardware.
- [ ] Archive implementation logs and hardware evidence under `results/`.

Do not guess pin numbers, VCCIO standards or the Gowin part number.
