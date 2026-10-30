file mkdir build
transcript file build/modelsim_transcript.log
transcript on
onerror {quit -code 1}
onbreak {quit -code 1}
if {![file isdirectory work]} { vlib work }
vmap work work

vlog -sv rtl/apb_slave.v rtl/register.v rtl/counter.sv rtl/timer_top.v \
     tb/register_tb.v tb/test_bench.sv tb/integration_smoke_tb.sv

puts "===== RUN: standalone register_tb ====="
vsim -c work.register_tb
run -all
quit -sim

puts "===== RUN: integrated smoke test ====="
vsim -c -voptargs=+acc work.integration_smoke_tb
run -all
quit -sim

puts "===== RUN: supplied system test_bench ====="
vsim -c -voptargs=+acc work.test_bench
run -all
quit -f
