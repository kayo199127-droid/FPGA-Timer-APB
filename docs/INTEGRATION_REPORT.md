# FAP201 IP Timer – Member 5 Integration Report

## 1. Responsibility

Member 5 is responsible for integrating the APB slave, register bank, timer
prescaler and 64-bit counter into one top-level IP, preparing system-level
verification in ModelSim, and handing the integrated block to the board team
for Gowin FPGA synthesis and programming.

## 2. Integrated hierarchy

```text
timer_top
├── u_apb_slave : apb_slave
├── u_register  : register
└── u_counter   : counter
    ├── u_counter_divider : counter_divider
    └── u_counter_core    : counter_core
```

The top-level keeps the instance names and selected internal nets accessed by
the supplied system testbench. The APB data path is 32-bit, the address path is
12-bit, and byte writes use `tim_pstrb[3:0]`.

## 3. Integration work completed

- Connected APB request/response signals and generated a one-cycle register
  access pulse only after the APB ACCESS phase is ready.
- Connected register outputs to divider, counter and interrupt logic; routed
  live counter values back to TDR0/TDR1 reads.
- Implemented byte-merged TDR preloads while stopped and direct byte-lane
  counter writes while running.
- Gated `PREADY` during reset and forced `PRDATA` to zero while reset is active,
  preventing a partially active APB transfer during reset.
- Added a one-cycle clear request on the falling edge of `timer_en`, while
  retaining the ability to preload TDR0/TDR1 after the timer is stopped.
- Made simultaneous TISR W1C-clear priority configurable. `timer_top` defaults
  to software-clear priority as stated in the Design SPEC; the standalone
  `register` module retains the supplied register-testbench default.
- Connected debug halt so `halt_ack` is asserted only when `dbg_mode` and
  `halt_req` are both high, freezing the divider and counter until release.

## 4. Verification assets

| Testbench | Purpose |
|---|---|
| `tb/register_tb.v` | Focused checks of the register bank using its legacy default parameter values |
| `tb/integration_smoke_tb.sv` | Top-level reset, APB, interrupt, timer-disable clear, TDR preload, W1C collision and debug halt/resume checks |
| `tb/test_bench.sv` | Supplied extended course testbench; divider-period measurement and APB error capture were corrected, and timer clear/overflow cases enabled |

Run all tests with `do sim/run_modelsim.do` in ModelSim/Questa, or use
`./sim/run_iverilog.sh` where Icarus Verilog is installed. Keep the complete
simulator transcript as grading evidence.

## 5. Specification differences to confirm

The integrated counter source, Golden Model and supplied system testbench
expect a prescale period of `2^div_val`. The Logic Diagram describes
`div_val + 1` cycles and an older standalone divider uses `2^(div_val+1)`.
The integrated implementation follows the provided integrated RTL/model and
system-test expectation. This difference is documented for instructor review.

The Design SPEC gives software W1C clear priority, whereas the standalone
register testbench expects hardware-set priority. The `SW_CLEAR_PRIORITY`
parameter makes the top-level and stand-alone test modes explicit.

## 6. Gowin handoff status

The reusable peripheral RTL is ready to be instantiated in the course's
Gowin board-level project. It requires a parent APB master/SoC interconnect;
`timer_top` is not a standalone LED/switch board application. The supplied
files do not identify the exact Gowin board, FPGA part number, clock/reset pin
assignments or parent APB master. No `.gprj`, `.cst`, bitstream or board-program
result is fabricated. Use the actual board project and official pinout, following
`gowin/README.md`.

## 7. Verification status

The supplied Golden Model self-test and project/file consistency checks run in
the preparation environment. No HDL simulator executable (ModelSim/Questa,
Icarus Verilog or Verilator) is available here, so HDL simulation, synthesis,
place-and-route, bitstream generation and physical board programming remain
unverified. Do not mark those stages PASS until the corresponding tool logs
are produced.
