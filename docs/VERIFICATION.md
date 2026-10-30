# Verification plan

## Supplied testbenches

| Testbench | DUT | Coverage |
|---|---|---|
| `tb/integration_smoke_tb.sv` | `timer_top` | Deterministic top-level checks for reset output, APB accesses, compare interrupt, counter clear on disable, TDR preload, W1C collision policy and debug halt/resume |
| `tb/test_bench.sv` | `timer_top` | Supplied extended course bench (IDs 2–38 plus coverage exercises); APB error capture and divider-period measurement are corrected, and timer-disable/overflow tests are enabled |
| `tb/register_tb.v` | `register` | Reset values, TCR validation/locking, byte strobes, TDR merge, TCMP access, TIER/TISR, THCSR, reserved offsets; legacy set-priority default |

The system testbench uses hierarchical names `dut.reg_wr_en_w`,
`dut.reg_rd_en_w`, `dut.u_register.tcmp0_reg`, and
`dut.u_counter.u_counter_core.current_match`; the integration preserves those
names for compatibility with the provided tests.

## Expected checks

1. Reset leaves counter at zero, compare registers at all ones, interrupt and
   halt control clear. The system-level default TCR is `0x0000_0100`.
2. APB setup phase does not write registers. Access completes only after the
   slave's wait cycle and `PREADY` assertion.
3. `PSTRB` updates only the selected byte lanes.
4. Illegal prescaler values and protected prescaler changes are reported as
   `PSLVERR` and do not modify TCR.
5. TDR0/TDR1 form one 64-bit counter; the counter increments at the configured
   tick rate and wraps naturally at `64'hFFFF_FFFF_FFFF_FFFF`.
6. Disabling a running timer clears the counter; writing TDR while stopped can
   preload it again.
7. `halt_ack` asserts only for `dbg_mode && halt_req`; while asserted, count is
   frozen and resumes when the halt condition is removed.
8. Counter/compare equality sets TISR. `TIER.int_en` gates `tim_int`; at the
   integrated top, software W1C clear wins if it coincides with hardware set.

## Run status in this environment

The current execution environment does not contain Icarus Verilog, Verilator,
ModelSim or Questa. Therefore the HDL testbenches have been prepared and reviewed
but could not be compiled or simulated here. Do not report HDL simulation as
PASS until `sim/run_modelsim.do` or `sim/run_iverilog.sh` has completed on a
machine with the appropriate simulator. Preserve the simulator transcript for
the course submission.
