#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p results/waveforms
RTL=(rtl/apb_slave.v rtl/register.v rtl/timer_divider.v rtl/timer_core.v rtl/counter.sv rtl/timer_top.v)
TESTS=(tb_apb_slave tb_register tb_timer_divider tb_timer_core tb_timer_top)
for TB in "${TESTS[@]}"; do
  echo "========== COMPILE ${TB} =========="
  iverilog -g2012 -Wall -s "$TB" -o "results/${TB}.out" "${RTL[@]}" "tb/${TB}.v"
  echo "========== RUN ${TB} =========="
  vvp "results/${TB}.out" | tee "results/${TB}.log"
done
echo "All canonical IP Timer testbenches completed successfully."
