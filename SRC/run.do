#==============================================================================
# run.do - Mo phong IP TIMER (FAP201 Final Project) tren ModelSim / QuestaSim
#------------------------------------------------------------------------------
# Cach chay:
#   1. Mo ModelSim -> File > Change Directory... -> chon thu muc SRC
#   2. Go trong cua so Transcript:   do run.do
#   3. Ket qua: dong "TIMER IP TEST SUMMARY: 45 checks, 0 failures" trong
#      Transcript; cua so Wave hien thi cac tin hieu cua timer_top_tb.
# Luu y: chi nap DUY NHAT testbench timer_top_tb lam top-level. Neu nap them
#        timer_top / timer_register / counter / apb_slave nhu cac top-level rieng,
#        tin hieu cua chung se hien HiZ / StX vi khong duoc noi voi testbench.
#==============================================================================
onerror {resume}
catch {quit -sim}

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -work work -2001 apb_slave.v
vlog -work work -2001 register.v
vlog -work work -2001 counter.v
vlog -work work -2001 timer_top.v
vlog -work work -2001 timer_top_tb.v

vsim -voptargs=+acc -onfinish stop work.timer_top_tb

# ---- Tin hieu cua testbench (giong Hinh 4.2 trong report) ----
add wave -noupdate sim:/timer_top_tb/*

# ---- Tin hieu noi bo de quan sat chi tiet ----
add wave -noupdate -divider {TIMER_REGISTER}
add wave -noupdate                    sim:/timer_top_tb/dut/u_register/r_timer_en
add wave -noupdate                    sim:/timer_top_tb/dut/u_register/r_div_en
add wave -noupdate -radix unsigned    sim:/timer_top_tb/dut/u_register/r_div_val
add wave -noupdate -radix hexadecimal sim:/timer_top_tb/dut/u_register/r_tcmp0
add wave -noupdate -radix hexadecimal sim:/timer_top_tb/dut/u_register/r_tcmp1
add wave -noupdate                    sim:/timer_top_tb/dut/u_register/r_int_en
add wave -noupdate                    sim:/timer_top_tb/dut/u_register/r_int_st
add wave -noupdate                    sim:/timer_top_tb/dut/u_register/r_halt_req
add wave -noupdate -divider {COUNTER}
add wave -noupdate -radix unsigned    sim:/timer_top_tb/dut/u_counter/u_counter_divider/div_cnt
add wave -noupdate                    sim:/timer_top_tb/dut/u_counter/u_counter_divider/div_match
add wave -noupdate                    sim:/timer_top_tb/dut/int_set_w
add wave -noupdate -radix hexadecimal sim:/timer_top_tb/dut/tdr_shadow
add wave -noupdate -radix hexadecimal sim:/timer_top_tb/dut/tcmp_w

configure wave -namecolwidth 230
configure wave -valuecolwidth 110
configure wave -timelineunits ns
run -all
wave zoom full
