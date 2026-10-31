# IP Timer Interface Agreement

## Team ownership

| Member | Name | Student ID | Assigned block |
|---:|---|---|---|
| 1 | Phùng Văn Tân | SE203222 | Timer Divider (`timer_divider.v`) |
| 2 | Hoàng Trung Hiếu | SE203208 | APB Slave Interface (`apb_slave.v`) |
| 3 | Hoàng Quốc Trí | SE203836 | System Integration and Verification (`counter.sv`, `timer_top.v`, system testbenches) |
| 4 | Lê Dương Hoàng Khang | SE204508 | Timer Core (`timer_core.v`) |
| 5 | Trần Định Quốc | CE202008 | Register Bank (`register.v`) |


This file is the single interface reference for integrating the five member modules. If the instructor approves a different interface, update this file and all RTL/testbenches together.

## 1. External `timer_top` interface

| Port | Direction | Width | Description |
|---|---|---:|---|
| `sys_clk` | Input | 1 | System clock |
| `sys_rst_n` | Input | 1 | Active-low asynchronous reset |
| `tim_psel` | Input | 1 | APB peripheral select |
| `tim_penable` | Input | 1 | APB ACCESS phase enable (the Design SPEC table calls this `tim_enable`) |
| `tim_pwrite` | Input | 1 | 1 = write, 0 = read |
| `tim_paddr` | Input | 12 | Byte address |
| `tim_pwdata` | Input | 32 | APB write data |
| `tim_pstrb` | Input | 4 | Byte write strobes |
| `tim_prdata` | Output | 32 | APB read data |
| `tim_pready` | Output | 1 | APB access completion |
| `tim_pslverr` | Output | 1 | Error on a completed illegal write |
| `dbg_mode` | Input | 1 | SoC debug-mode indication |
| `tim_int` | Output | 1 | Timer interrupt request |

## 2. APB behavior

- SETUP: `PSEL=1`, `PENABLE=0`.
- ACCESS: `PSEL=1`, `PENABLE=1`.
- The slave inserts one ACCESS wait cycle. `PREADY` is asserted after the ACCESS phase has been observed for one clock.
- Register writes commit on the clock edge at which the ACCESS transfer completes (`PREADY=1`).
- `PSLVERR` is meaningful only with a completed write (`PREADY=1`, `PWRITE=1`).
- `PRDATA` is forced to zero during reset and when the peripheral is not selected.
- Register offsets are byte addresses; the two low bits are ignored by the register bank. An address such as `0x003` therefore selects the word at `0x000`; it is not treated as a separate alignment error in this implementation.

## 3. Internal module connections

| Source | Destination | Signals |
|---|---|---|
| `apb_slave` | `register` | `reg_valid`, `reg_write`, `reg_addr[11:0]`, `reg_wdata[31:0]`, `reg_strb[3:0]` |
| `register` | `timer_divider` | `timer_en`, `div_en`, `div_val[3:0]`, `halt_req` |
| `timer_divider` | `timer_core` | `div_tick`, `halt_ack` |
| `register` | `timer_core` | `tdr0_load/wdata`, `tdr1_load/wdata`, `tcmp[63:0]` |
| `timer_core` | `register` | `counter_val[63:0]`, `cmp_match_evt` as `int_set` |
| `register` | SoC | `tim_int` |

## 4. Register map

| Offset | Name | Fields | Description |
|---:|---|---|---|
| `0x000` | TCR | bit 0 `timer_en`; bit 1 `div_en`; bits [11:8] `div_val` | Timer control and divider configuration |
| `0x004` | TDR0 | [31:0] | Counter low word, read/write load interface |
| `0x008` | TDR1 | [31:0] | Counter high word, read/write load interface |
| `0x00C` | TCMP0 | [31:0] | Compare low word |
| `0x010` | TCMP1 | [31:0] | Compare high word |
| `0x014` | TIER | bit 0 `int_en` | Interrupt enable |
| `0x018` | TISR | bit 0 `int_st` | Sticky interrupt status; write 1 to clear |
| `0x01C` | THCSR | bit 0 `halt_req`; bit 1 `halt_ack` (RO) | Debug halt control/status |

## 5. Error and access policy

- `div_val[3]=1` (values 8–15) is prohibited when byte lane 1 is written.
- While `timer_en=1`, changes to `div_en` or `div_val` are rejected. Disabling the timer without changing divider fields is allowed; divider configuration may be changed in a later transaction after the timer is stopped.
- Reserved addresses read as zero; writes are ignored and do not assert `PSLVERR`.
- Reserved bits read as zero and are ignored on writes.
- Writes to `THCSR.halt_ack` are ignored because it is read-only.
- `TISR.int_st` is W1C. Software clear has priority over a same-cycle hardware set, following the Design SPEC.

## 6. Clock-divider definition

When `timer_en=0`, `div_tick=0` and the divider state is cleared. When `timer_en=1` and `div_en=0`, `div_tick=1` (full speed). When `timer_en=1` and `div_en=1`, one tick occurs every `(div_val + 1)` system-clock cycles. Legal divider values are 0–7.

## 7. Counter and halt definition

- Counter reset value is zero.
- Counter increments by one on each active `div_tick` unless debug halt is acknowledged.
- A `timer_en` HIGH-to-LOW transition clears the 64-bit counter.
- Explicit TDR0/TDR1 writes load the corresponding counter word; while stopped, the loaded value is held until the timer is enabled or another TDR write occurs. A timer-disable falling-edge clear has priority over a TDR write on that same clock edge.
- `halt_ack = dbg_mode && halt_req`. During halt, the divider phase and counter value are frozen. The counter resumes after halt is released.
