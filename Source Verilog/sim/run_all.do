onerror {quit -code 1}
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
do sim/compile.do
echo "========== RUN tb_apb_slave =========="
vsim work.tb_apb_slave
run -all
quit -sim
echo "========== RUN tb_register =========="
vsim work.tb_register
run -all
quit -sim
echo "========== RUN tb_timer_divider =========="
vsim work.tb_timer_divider
run -all
quit -sim
echo "========== RUN tb_timer_core =========="
vsim work.tb_timer_core
run -all
quit -sim
echo "========== RUN tb_timer_top =========="
vsim work.tb_timer_top
run -all
quit -sim
quit -f
