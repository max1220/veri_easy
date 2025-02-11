module counter(clk, cnt);
	input clk;
	output reg [7:0] cnt;
	always @(posedge clk) begin
		cnt <= cnt + 1;
		$display("Verilog counter: %d", cnt);
	end
	initial begin
		$display("Verilog starting!");
	end
endmodule
