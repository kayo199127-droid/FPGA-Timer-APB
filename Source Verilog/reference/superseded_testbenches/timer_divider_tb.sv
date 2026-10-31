`timescale 1ns/1ps
module timer_divider_tb;
    reg sys_clk=0, sys_rst_n=0, timer_en=0, div_en=0, halt_ack=0;
    reg [3:0] div_val=0;
    wire tick;
    integer cycles;
    timer_divider dut(.sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.timer_en(timer_en),
        .div_en(div_en),.div_val(div_val),.halt_ack(halt_ack),.tick(tick));
    always #10 sys_clk=~sys_clk;
    initial begin
        repeat(2) @(negedge sys_clk); sys_rst_n=1; timer_en=1;
        div_en=0; repeat(4) @(posedge sys_clk);
        if (tick !== 1'b1) $fatal(1,"full-speed mode tick expected high");
        div_en=1; div_val=2; cycles=0;
        @(negedge sys_clk);
        while (tick !== 1'b1) @(negedge sys_clk);
        while (tick !== 1'b0) @(negedge sys_clk);
        cycles=0;
        while (tick !== 1'b1) begin @(negedge sys_clk); cycles=cycles+1; end
        if (cycles != 3) $fatal(1,"expected pulse spacing=4 cycles, measured=%0d",cycles+1);
        halt_ack=1; repeat(4) @(posedge sys_clk);
        if (tick !== 1'b0) $fatal(1,"tick must be low during halt");
        $display("timer_divider_tb: PASS"); $finish;
    end
endmodule
