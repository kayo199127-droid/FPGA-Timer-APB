
`timescale 1ns/1ps

module timer_divider_tb;

reg sys_clk;
reg sys_rst_n;
reg div_en;
reg [3:0] div_val;

wire tick;

timer_divider uut (
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .div_en(div_en),
    .div_val(div_val),
    .tick(tick)
);

// Tao xung clock chu ky 10 ns
initial begin
    sys_clk = 1'b0;
    forever #5 sys_clk = ~sys_clk;
end

// Tao tin hieu reset va cac gia tri kiem tra
initial begin
    sys_rst_n = 0;
    div_en = 1;
    div_val = 4'b0001;  // Gia su chia 4

    #20;
    sys_rst_n = 1;

    #100;
    div_val = 4'b0010;  // Gia su chia 8

    #160;
    div_en = 1'b0;

    #40;
    $finish;
end

endmodule
