transcript on
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
file mkdir results
file mkdir results/waveforms
if {[file exists sim/work]} {vdel -lib sim/work -all}
vlib sim/work
vmap work sim/work
vlog -sv rtl/apb_slave.v
vlog -sv rtl/register.v
vlog -sv rtl/timer_divider.v
vlog -sv rtl/timer_core.v
vlog -sv rtl/counter.sv
vlog -sv rtl/timer_top.v
vlog -sv tb/tb_apb_slave.v
vlog -sv tb/tb_register.v
vlog -sv tb/tb_timer_core.v
vlog -sv tb/tb_timer_divider.v
vlog -sv tb/tb_timer_top.v
