# Design notes and resolved specification differences

## 1. Hierarchy

```text
timer_top
├── apb_slave
├── register
└── counter
    ├── counter_divider
    └── counter_core
```

The APB slave asserts register access only in the ACCESS phase after one wait
cycle. `register` decodes the memory map and produces timer configuration,
compare value, interrupt state, halt request, and merged TDR write data. `counter`
contains the prescaler and 64-bit counter. The comparator event feeds the
register bank's hardware interrupt-set input.

## 2. Register behavior

- TCR fields: bit 0 `timer_en`, bit 1 `div_en`, bits 11:8 `div_val`.
- While `timer_en=1`, changing `div_en` or `div_val` is rejected. Rewriting the
  same values is accepted. `timer_en` itself may still be changed.
- `div_val` values 8–15 are rejected when byte lane 1 is strobed.
- Byte writes are merged using `PSTRB`.
- TDR reads reflect the live 64-bit counter. When stopped, writes are routed as
  merged `tdr_val`; while running, the counter core applies the APB byte lanes.
- `TISR.int_st` is W1C. The integrated `timer_top` sets
  `SW_CLEAR_PRIORITY=1`, so a simultaneous software clear wins over a compare
  event as required by the Design SPEC. The standalone `register` module keeps
  a default of zero for this parameter to preserve the supplied legacy
  `register_tb.v`, which explicitly expects hardware-set priority.
- THCSR bit 1 is a live read-only `halt_ack` input; writes affect only bit 0.
- The integrated top detects the falling edge of `timer_en` and sends a
  one-cycle clear request to the counter. A later TDR write while stopped can
  preload the counter again.

## 3. Explicitly resolved differences in the uploaded references

1. **TCR reset value:** the provided standalone `register_tb.v` expects zero,
   while the large system testbench expects `0x0000_0100`. To keep both supplied
   benches meaningful, `register` has a `RESET_DIV_VAL` parameter defaulting to
   zero, and `timer_top` defaults it to one. This is visible and configurable.
2. **Divider period:** the integrated `counter.sv`, golden model and supplied
   system testbench ID30 use a power-of-two period (`2^div_val`), where zero
   gives full speed. The written Logic Diagram says `div_val + 1` cycles, and
   the older `prj_FAP/timer_divider.v` uses `2^(div_val+1)`. The integrated RTL
   follows the executable timer source/model and the ID30 expectation; this
   mismatch should be confirmed with the instructor before hardware grading.
3. **TISR simultaneous set/clear:** the Design SPEC says software clear wins,
   while the supplied standalone register testbench expects hardware set to
   win. The parameter `SW_CLEAR_PRIORITY` resolves this without breaking the
   standalone test: `timer_top` defaults to specification priority (`1`), and
   `register` defaults to legacy-test priority (`0`).
4. **Counter clear on timer disable:** the Logic Diagram and system behavior
   require a clear when `timer_en` falls. The original counter block's `tdr_val`
   input also supports preloading while stopped, so `timer_top` generates a
   one-cycle falling-edge clear request; subsequent TDR writes while stopped
   remain supported.

These are real differences in the input material, not claims that all versions
of the spec agree.

## 4. APB assumptions

The APB master keeps address, write data, direction and strobes stable through
ACCESS completion. The slave inserts one wait cycle and returns `PREADY` only
when `PSEL && PENABLE && access_seen` is true. `PSLVERR` is asserted only with
`PREADY` and the register-bank error response. The Design SPEC interface table
says `tim_pslverr` is tied high; the integrated implementation instead asserts
it only for a rejected TCR write, consistent with APB error signaling and the
supplied APB slave RTL.
