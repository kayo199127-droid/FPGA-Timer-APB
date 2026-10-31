# Design Decisions and Source Reconciliation

The supplied project archive contains several RTL/testbench versions. The final source uses one coherent interpretation, recorded below. Decisions that conflict with supplied documents are highlighted for lecturer/team approval.

| ID | Supplied-source conflict | Chosen implementation | Reason / approval status |
|---|---|---|---|
| DD-01 | `Logic Diagram` says one increment every `div_val + 1` cycles; `counter.sv` implements a `2^div_val` style interval; `prj_FAP/timer_divider.v` uses a power-of-two divisor table. | Use the explicit linear `(div_val + 1)` interval. | Matches the examples in the Logic Diagram: 0→1 cycle, 1→2 cycles, 2→3 cycles, 3→4 cycles. Instructor confirmation remains recommended. |
| DD-02 | Register RTL and `register_tb.v` expect TCR reset `0`; older integrated `test_bench.sv` expects `0x100`. | TCR reset to `0x000`. | Two register-level artifacts agree; legacy integration expectation is treated as stale and must be updated. |
| DD-03 | Design SPEC requires software W1C clear to have highest priority; the supplied `register.v` writes the hardware set after software clear, and its unit TB expects hardware set to win. | Software W1C clear wins. | Follows the written Design SPEC. The updated register TB checks that policy. |
| DD-04 | Logic Diagram says the counter clears on timer disable; the supplied counter core follows `tdr_val` while stopped; register block exposes TDR load signals. | Clear once on timer-enable falling edge; explicit TDR writes are accepted as preload operations while stopped. | Preserves the specified disable transition clear and the provided TDR write interface. Confirm with lecturer if TDR writes should instead be prohibited while stopped. |
| DD-05 | Design SPEC table describes `PSLVERR` as tied high, while the APB slave and register logic include dynamic errors. | Assert `PSLVERR` only on completed writes that violate TCR configuration rules. | Constant-high PSLVERR would mark every transfer as an error and conflicts with the supplied `reg_err` logic. This discrepancy requires formal confirmation. |
| DD-06 | Source versions differ between `tim_enable` and `tim_penable`; APB protocol calls the ACCESS control signal `PENABLE`. | Use `tim_penable` at the top-level; document that the SPEC's `tim_enable` means PENABLE. | Matches the supplied system testbench and APB terminology. |
| DD-07 | Older APB source uses 32-bit address and 8-bit internal register address; Design SPEC and system TB specify 12-bit address. | Use a 12-bit APB address and 12-bit register interface. | Matches Design SPEC and system testbench address map. |

| DD-08 | Original `counter_core` and Golden Model generate compare equality from `counter_val == tcmp_val`, without timer_en gating; later draft RTL versions differed. | Keep the compare event as a direct equality comparison. | Matches the original counter RTL and Golden Model. Confirm if compare should be masked while timer_en is low. |

## Team responsibility mapping (approved from the supplied assignment screenshot)

| Member | Name | Student ID | Ownership |
|---:|---|---|---|
| 1 | Phùng Văn Tân | SE203222 | Timer Divider (`rtl/timer_divider.v`) |
| 2 | Hoàng Trung Hiếu | SE203208 | APB Slave Interface (`rtl/apb_slave.v`) |
| 3 | Hoàng Quốc Trí | SE203836 | System Integration and Verification (`rtl/counter.sv`, `rtl/timer_top.v`, system-level testbench and regression) |
| 4 | Lê Dương Hoàng Khang | SE204508 | Timer Core (`rtl/timer_core.v`) |
| 5 | Trần Định Quốc | CE202008 | Register Bank (`rtl/register.v`) |

## Final sign-off rule

Do not state that the project is 100% compliant until the instructor confirms DD-01 through DD-08, HDL simulation is run, and the assigned Gowin target is synthesized and tested. The source code in this package is internally consistent with the decisions above, not a claim that unresolved external requirements have been approved.
