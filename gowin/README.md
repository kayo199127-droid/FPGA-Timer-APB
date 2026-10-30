# Gowin handoff checklist

## What is ready

- Synthesizable peripheral hierarchy: `timer_top` in `rtl/timer_top.v`.
- RTL dependencies: `rtl/apb_slave.v`, `rtl/register.v`, `rtl/counter.sv`.
- APB signals are 32-bit data, 12-bit byte address and 4-bit write strobe.
- Reset is active-low asynchronous (`sys_rst_n`).
- Interrupt output is `tim_int`; debug input is `dbg_mode`.

## Integrate into the board project

1. Open the existing Gowin board project and keep its selected FPGA part and
   board-level clock/reset constraints.
2. Add the four RTL source files above to the project. Set the board/SoC top
   module as the synthesis top; instantiate `timer_top` inside that top.
3. Connect `sys_clk` and `sys_rst_n` to the board's qualified clock/reset.
4. Connect `tim_*` to the SoC APB master/interconnect. Do not connect the APB
   control/data bus directly to LEDs or switches; those pins are not an APB host.
5. Connect `tim_int` to the interrupt controller or a spare debug output, and
   connect `dbg_mode` to the SoC debug-mode signal (or tie it low when debug
   halt is not used).
6. Run synthesis, place-and-route, timing analysis, generate the bitstream, and
   program the target board. Save the Gowin log and a board test record.

## Board-specific inputs still required

The supplied files do not identify the Gowin board model, FPGA part number,
clock frequency/pin, reset pin, or an APB master/SoC wrapper. Therefore this
handoff does not invent a `.gprj`, `.cst`, or pin numbers. Those files must be
created/updated in the actual board project using its official pinout. The IP
itself is ready to be instantiated, but board synthesis/programming has not
been verified in this environment.
