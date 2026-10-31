module timer_divider (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       div_en,
    input  wire [3:0] div_val,
    output reg        tick
);

reg [7:0] count;
reg [8:0] divisor;

always @(*) begin
    case (div_val)
        4'b0000: divisor = 9'd2;
        4'b0001: divisor = 9'd4;
        4'b0010: divisor = 9'd8;
        4'b0011: divisor = 9'd16;
        4'b0100: divisor = 9'd32;
        4'b0101: divisor = 9'd64;
        4'b0110: divisor = 9'd128;
        4'b0111: divisor = 9'd256;
        default: divisor = 9'd2;
    endcase
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        count <= 8'd0;
        tick  <= 1'b0;
    end
    else if (!div_en) begin
        count <= 8'd0;
        tick  <= 1'b1;
    end
    else begin
        if (count == divisor - 1'b1) begin
            count <= 8'd0;
            tick  <= 1'b1;
        end
        else begin
            count <= count + 1'b1;
            tick  <= 1'b0;
        end
    end
end

endmodule
