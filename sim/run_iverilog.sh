#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v iverilog >/dev/null 2>&1 || { echo "ERROR: iverilog is not installed." >&2; exit 127; }
command -v vvp >/dev/null 2>&1 || { echo "ERROR: vvp is not installed." >&2; exit 127; }
mkdir -p build

RTL=(rtl/apb_slave.v rtl/register.v rtl/counter.sv rtl/timer_top.v)

echo "[1/3] Compile and run standalone register_tb"
iverilog -g2012 -Wall -s register_tb -o build/register_tb rtl/register.v tb/register_tb.v
vvp build/register_tb

echo "[2/3] Compile and run timer_top integration smoke test"
iverilog -g2012 -Wall -s integration_smoke_tb -o build/integration_smoke_tb \
  "${RTL[@]}" tb/integration_smoke_tb.sv
vvp build/integration_smoke_tb

echo "[3/3] Compile and run supplied system test_bench"
iverilog -g2012 -Wall -s test_bench -o build/timer_top_tb \
  "${RTL[@]}" tb/test_bench.sv
vvp build/timer_top_tb
