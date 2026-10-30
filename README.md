# FAP201 – 64-bit APB Timer IP

A modular 64-bit timer peripheral for an SoC, implemented in Verilog/SystemVerilog.
The project combines an APB slave, a memory-mapped register bank, a programmable
clock-enable divider, a 64-bit up-counter, interrupt generation, and debug halt.

## Project structure

```text
IP-Timer-FAP201/
├── rtl/
│   ├── apb_slave.v       # APB access/ready/error logic
│   ├── register.v        # TCR/TDR/TCMP/TIER/TISR/THCSR register bank
│   ├── counter.sv        # counter_divider, counter_core, counter
│   └── timer_top.v       # Integrated timer_top module
├── tb/
│   ├── register_tb.v     # Focused register-file testbench
│   ├── integration_smoke_tb.sv # Top-level integration smoke test
│   └── test_bench.sv     # Extended course system testbench (ID2–ID38)
├── docs/
│   ├── DESIGN_NOTES.md   # Register map and design decisions
│   ├── VERIFICATION.md   # Test plan and execution notes
│   └── INTEGRATION_REPORT.md # Member 5 integration handoff report
├── reference/
│   ├── GOLDEN_MODEL.py   # Integration-aligned cycle/bit-accurate model
│   ├── GOLDEN_MODEL_supplied.py # Unmodified model from the uploaded archive
│   ├── Design_SPEC.docx  # Original user-provided specification
│   └── Logic_Diagram.docx# Original user-provided logic notes
├── sim/
│   ├── run_iverilog.sh
│   └── run_modelsim.do
└── gowin/
    └── README.md         # Board-project handoff and constraints checklist
```

## Main features

- APB-style 32-bit data interface, 12-bit address, byte strobes and one wait cycle.
- 64-bit count-up timer, accessible through `TDR0` and `TDR1`.
- 64-bit compare threshold (`TCMP0`/`TCMP1`) and interrupt output.
- `TISR.int_st` is write-one-to-clear (W1C); at the integrated top, a simultaneous software clear wins over a hardware compare event, as required by the Design SPEC.
- Debug halt is effective only when `dbg_mode && halt_req`; the counter and divider freeze while `halt_ack` is asserted.
- A falling edge of `timer_en` clears the 64-bit counter; TDR can then be preloaded while stopped.
- TCR prescaler settings are protected while the timer is enabled; `div_val[3] = 1` is rejected.

## Register map

All addresses are byte offsets. `register.v` ignores `reg_addr[1:0]`.

| Offset | Register | Implemented fields |
|---:|---|---|
| `0x00` | TCR | bit 0 `timer_en`; bit 1 `div_en`; bits 11:8 `div_val` |
| `0x04` | TDR0 | counter bits 31:0, read/write |
| `0x08` | TDR1 | counter bits 63:32, read/write |
| `0x0C` | TCMP0 | compare bits 31:0, reset `0xFFFF_FFFF` |
| `0x10` | TCMP1 | compare bits 63:32, reset `0xFFFF_FFFF` |
| `0x14` | TIER | bit 0 `int_en` |
| `0x18` | TISR | bit 0 `int_st`, W1C |
| `0x1C` | THCSR | bit 0 `halt_req`; bit 1 `halt_ack` (read-only) |

Unimplemented offsets read as zero and ignore writes. TCR reserved bits read as zero.

## Divider behavior

This integrated project follows the supplied `counter.sv`, `GOLDEN_MODEL.py`,
and system testbench ID30: when `div_en=1`, the counter tick period is
`2^div_val` clock cycles (`div_val=0` means every clock, `div_val=1` means every
2 clocks, ... `div_val=7` means every 128 clocks). When `div_en=0`, the divider
is bypassed. Note that the written Logic Diagram instead states `div_val + 1`
cycles and an older divider source uses `2^(div_val+1)`; this discrepancy is
recorded in `docs/DESIGN_NOTES.md`.

`RESET_DIV_VAL` is a `timer_top` parameter. Its default is `1`, because the supplied
system-level testbench explicitly checks reset `TCR = 0x0000_0100`. The standalone
`register` module defaults this parameter to `0` so the supplied register-only
`register_tb.v` retains its original reset expectation. Set `timer_top.RESET_DIV_VAL`
to `0` if the course specification requires a zero reset value instead.

## Build and simulate

### Icarus Verilog

From the project root:

```bash
chmod +x sim/run_iverilog.sh
./sim/run_iverilog.sh
```

### ModelSim / Questa

```tcl
do sim/run_modelsim.do
```

The testbenches are `register_tb`, `integration_smoke_tb`, and the supplied
extended system bench `test_bench`. The smoke test checks integration-specific
behaviors independently; keep the simulator transcript for evidence.

## Top-level interface

The top module is `timer_top` in `rtl/timer_top.v`. It exposes `sys_clk`, active-low
asynchronous `sys_rst_n`, APB signals (`tim_psel`, `tim_penable`, `tim_pwrite`,
`tim_paddr`, `tim_pwdata`, `tim_pstrb`), response signals (`tim_prdata`,
`tim_pready`, `tim_pslverr`), `tim_int`, and `dbg_mode`.

## Notes before grading

The uploaded source set did not contain a complete `timer_top` integration module.
This repository supplies that integration and adapts the older APB slave interface
to the 12-bit address bus used by the course-level testbench. The source documents
contain a few conflicting statements; the choices above are made explicit in
`docs/DESIGN_NOTES.md` rather than silently mixing incompatible implementations.

## Gowin board integration

`timer_top` is the reusable APB peripheral top, not a complete board-level
application. It expects a system clock/reset and an APB master (normally the
CPU/SoC interconnect). To synthesize it in Gowin EDA, add the files under `rtl/`
to the board's parent project and instantiate `timer_top` on the internal APB
bus. The board-specific top module, device selection, clock constraints and
`.cst` pin assignments must come from the actual Gowin board model and its
provided pinout. They are intentionally not guessed here. See
`gowin/README.md` for the handoff checklist.
