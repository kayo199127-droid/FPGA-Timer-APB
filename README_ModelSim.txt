IP TIMER (FAP201) - HUONG DAN CHAY WAVE TREN MODELSIM
=====================================================

1. Copy (ghi de) TAT CA file trong thu muc nay vao
   C:/Desktop/modelsim_ase/win32aloem

2. Trong cua so Transcript cua ModelSim go:

      cd C:/Desktop/modelsim_ase/win32aloem
      do run_timer_top_tb.do      (test he thong: APB + register + counter)

   Cac test rieng tung khoi:
      do run_counter_tb.do        (counter.v so voi GOLDEN_MODEL.v)
      do run_register_tb.do       (register.v)
      do run_app_slave_tb.do      (app_slave.v)
      do run_all_tb.do            (chay ca 4 testbench, giu wave timer_top_tb)

   KHONG dung Simulate > Start Simulation. Khi load loi, hop thoai nay chi
   bao "can't read Startup(-L) ... Load canceled" va giau loi that.
   Do-file tu compile 9 file .v, load testbench, add wave, run -all va
   in loi that ra Transcript neu co.

3. Ket qua mong doi trong Transcript:
      timer_top_tb : TIMER IP TEST SUMMARY: 45 checks, 0 failures
      counter_tb   : directed checks = 48, failures = 0
                     scoreboard cycles = 4102, mismatches = 0
      register_tb  : TAT CA 87 KIEM TRA DEU PASS
      apb_slave_tb : APB SLAVE TB SUMMARY: checks = 68, failures = 0

Module trong tung file
----------------------
   app_slave.v      module apb_slave             (RTL)
   register.v       module timer_register        (RTL)
   counter.v        module counter, counter_divider, counter_core (RTL)
   timer_top.v      module timer_top             (RTL top)
   GOLDEN_MODEL.v   module counter_golden_model  (model tham chieu cho counter)
   app_slave_tb.v   module apb_slave_tb          (testbench)
   register_tb.v    module register_tb           (testbench)
   counter_tb.v     module counter_tb            (testbench)
   timer_top_tb.v   module timer_top_tb          (testbench)
