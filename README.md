# FAP201 Final Project – IP Timer

A modular Verilog/SystemVerilog implementation of an APB-accessible 64-bit timer peripheral.

## Team and Assigned Responsibilities

| No. | Full name | Student ID | Assigned responsibility |
|---:|---|---|---|
| 1 | Phùng Văn Tân | SE203222 | Timer Divider (`timer_divider.v`) |
| 2 | Hoàng Trung Hiếu | SE203208 | APB Slave Interface (`apb_slave.v`) |
| 3 | Hoàng Quốc Trí | SE203836 | System Integration and Verification (`counter.sv`, `timer_top.v`, system testbenches) |
| 4 | Lê Dương Hoàng Khang | SE204508 | Timer Core (`timer_core.v`) |
| 5 | Trần Định Quốc | CE202008 | Register Bank (`register.v`) |

## Features

- 32-bit APB data bus and 12-bit byte address bus.
- 4-bit write strobe (`PSTRB`).
- APB ACCESS wait state and completion/error response.
- Memory-mapped TCR, TDR0, TDR1, TCMP0, TCMP1, TIER, TISR and THCSR registers.
- Configurable timer tick using the approved interpretation `tick period = div_val + 1` when `div_en=1`.
- 64-bit up-counter with low/high word access.
- Hardware counter clear on the `timer_en` HIGH-to-LOW transition.
- Compare-event interrupt, sticky W1C status and debug halt.

## Repository structure

```text
IP-Timer-FAP201-Final/
├── rtl/                 # Synthesizable RTL
│   ├── apb_slave.v
│   ├── register.v
│   ├── timer_divider.v
│   ├── timer_core.v
│   ├── counter.sv
│   └── timer_top.v
├── tb/                  # Unit and integration testbenches
├── sim/                 # ModelSim/Questa and Icarus scripts
├── docs/                # Interface agreement, design decisions, architecture
├── results/             # Simulation logs, VCD waveforms and FPGA evidence
│   └── waveforms/       # Created by the simulation runners
├── constraints/         # Board-specific pin/clock constraints (not guessed)
├── reference/           # Original supplied sources for traceability
├── README.md
└── Makefile
```

## Top-level module

`timer_top` is the IP-level top. Its external ports are:

- `sys_clk`, `sys_rst_n` (active-low asynchronous reset)
- `tim_psel`, `tim_penable`, `tim_pwrite`
- `tim_paddr[11:0]`, `tim_pwdata[31:0]`, `tim_pstrb[3:0]`
- `tim_prdata[31:0]`, `tim_pready`, `tim_pslverr`
- `dbg_mode`, `tim_int`

The system/board top must additionally provide an APB master or APB interconnect. `timer_top` is a peripheral and is not by itself a complete board-level design.

## Simulation

### ModelSim / Questa

From the repository root, open a ModelSim/Questa transcript and run:

```tcl
do sim/run_all.do
```

The script compiles only the canonical testbenches: `tb_apb_slave`, `tb_register`, `tb_timer_divider`, `tb_timer_core`, and `tb_timer_top`. Any failed test ends with `$fatal`, causing the run to fail instead of silently returning success.

The script compiles the RTL and runs `tb_apb_slave`, `tb_register`, `tb_timer_divider`, `tb_timer_core` and `tb_timer_top`.

### Icarus Verilog

From the repository root:

```bash
make sim
```

or:

```bash
./sim/run_iverilog.sh
```

The script writes compile outputs and logs under `results/`, and VCD waveforms under `results/waveforms/`. A simulator must be installed for these commands to run.

## Design parameters and reset defaults

| Item | Value |
|---|---:|
| Verification clock used by supplied testbench | 50 MHz |
| Verification clock period | 20 ns |
| APB data width | 32 bits |
| APB address width | 12 bits |
| PSTRB width | 4 bits |
| Timer counter / compare width | 64 bits |
| TCR reset | `0x0000_0000` |
| TCMP0 / TCMP1 reset | `0xFFFF_FFFF` each |
| TIER / TISR / THCSR reset | `0x0000_0000` |
| `timer_en`, `div_en`, `div_val` reset | `0`, `0`, `0` |
| Legal `div_val` values | 0 through 7 |

The 50 MHz clock is the report/testbench reference supplied in the project discussion. The RTL receives `sys_clk` from the integrating system; the actual board clock must be confirmed from the assigned Gowin board documentation.

## Specification decisions and known source conflicts

See [`docs/DESIGN_DECISIONS.md`](docs/DESIGN_DECISIONS.md) and [`docs/INTERFACE_AGREEMENT.md`](docs/INTERFACE_AGREEMENT.md). In brief:

1. The Logic Diagram explicitly describes a linear `(div_val + 1)` cycle interval. This implementation follows that behavior rather than the older `2^div_val` and `2^(div_val+1)` source variants.
2. The register RTL and its standalone register testbench use `TCR=0` after reset. An older system testbench expected `0x100`; this implementation follows the register RTL/unit-test reset and updates the integration expectation accordingly.
3. The Design SPEC states that software W1C clear has priority over a simultaneous hardware interrupt set. This implementation follows the written specification and updates the conflicting legacy register-test expectation.
4. `PSLVERR` is asserted only for a completed write that violates TCR rules. The Design SPEC table's note that `PSLVERR` is tied high conflicts with the register error logic and is recorded for instructor confirmation.
5. The counter is cleared on the timer-enable falling edge. Explicit TDR writes are retained as counter preloads while the timer is stopped; this reconciles the clear-on-disable requirement with the supplied TDR load interface.

These decisions are documented, but final instructor approval is still required where the supplied materials contradict each other.

## Verification status

The RTL and self-checking testbenches are prepared. The authoring environment used for this package did not have ModelSim/Questa or Icarus Verilog installed, so HDL compilation/simulation has **not** been executed here. Do not describe the testbench as passing until the logs and waveform evidence are generated on a machine with a simulator.

## Gowin FPGA handoff

The exact board model, Gowin FPGA part number, clock pin, reset pin and APB master/wrapper were not included in the supplied materials. Therefore no `.cst` pin assignments or bitstream are fabricated. See [`constraints/README.md`](constraints/README.md) and [`docs/GOWIN_HANDOFF.md`](docs/GOWIN_HANDOFF.md).

## Canonical verification files

- `tb/tb_apb_slave.v` – APB wait-state, read-data and error-response unit test (Member 2).
- `tb/tb_register.v` – register-bank reset, byte-strobe, protection and W1C unit test (Member 5).
- `tb/tb_timer_divider.v` – divider period, full-speed, disabled and debug-halt unit test (Member 1).
- `tb/tb_timer_core.v` – 64-bit counter, preload, clear, compare and halt unit test (Member 4).
- `tb/tb_timer_top.v` – integrated APB, register, counter, interrupt and debug test (Member 3).
- Earlier incompatible draft testbenches are archived under `reference/superseded_testbenches/` and are not compiled.

## Team reports

- Group report: `docs/FAP201_IP_Timer_Group_Report_EN.docx`
- Individual report for Member 1 (Phùng Văn Tân): `docs/reports/individual/FAP201_IP_Timer_Individual_Report_Member_1_SE203222.docx`
- Individual report for Member 2 (Hoàng Trung Hiếu): `docs/reports/individual/FAP201_IP_Timer_Individual_Report_Member_2_SE203208.docx`
- Individual report for Member 3 (Hoàng Quốc Trí): `docs/reports/individual/FAP201_IP_Timer_Individual_Report_Member_3_SE203836.docx`
- Individual report for Member 4 (Lê Dương Hoàng Khang): `docs/reports/individual/FAP201_IP_Timer_Individual_Report_Member_4_SE204508.docx`
- Individual report for Member 5 (Trần Định Quốc): `docs/reports/individual/FAP201_IP_Timer_Individual_Report_Member_5_CE202008.docx`

The individual reports are pre-filled drafts. They intentionally leave actual contribution evidence, personal reflection, final grade and instructor feedback for completion after assessment.
