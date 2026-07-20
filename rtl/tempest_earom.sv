//============================================================================
//  Atari ER2055 EAROM
//
//  Written 2026 by Videodr0me
//
//  Tempest latches address and data at $6000-$603f, then drives the ER2055
//  control pins from $6040. The host port provides persistent save data.
//============================================================================

module tempest_earom
(
	input  logic       clk,
	input  logic       reset,

	input  logic       latch_write,
	input  logic [5:0] latch_address,
	input  logic [7:0] latch_data,
	input  logic       control_write,
	input  logic [3:0] control_data,
	output logic [7:0] data_out,
	output logic       modified,

	input  logic [5:0] host_address,
	input  logic [7:0] host_data_in,
	input  logic       host_write,
	output logic [7:0] host_data_out
);

	(* ramstyle = "MLAB, no_rw_check" *) logic [7:0] cpu_memory [0:63];
	(* ramstyle = "MLAB, no_rw_check" *) logic [7:0] host_memory [0:63];
	logic [5:0] address_latch;
	logic [7:0] data_latch;
	logic [3:0] control;
	logic       cpu_memory_write;
	logic [7:0] cpu_memory_data;
	logic       memory_write;
	logic [5:0] memory_write_address;
	logic [7:0] memory_write_data;
	integer index;

	initial begin
		for (index = 0; index < 64; index = index + 1) begin
			cpu_memory[index] = 8'hff;
			host_memory[index] = 8'hff;
		end
	end

	assign host_data_out = host_memory[host_address];

	always_comb begin
		cpu_memory_write = 1'b0;
		cpu_memory_data = data_latch;

		if (control_write) begin
			case (control_data[3:1])
				3'b111: begin
					cpu_memory_write = 1'b1;
					cpu_memory_data = 8'hff;
				end
				3'b110: cpu_memory_write = 1'b1;
				default: ;
			endcase
		end

		memory_write = host_write || (!reset && cpu_memory_write);
		if (host_write) begin
			memory_write_address = host_address;
			memory_write_data = host_data_in;
		end else begin
			memory_write_address = address_latch;
			memory_write_data = cpu_memory_data;
		end
	end

	always @(posedge clk) begin
		modified <= 1'b0;

		if (reset) begin
			address_latch <= 6'd0;
			data_latch    <= 8'hff;
			control       <= 4'd0;
			data_out      <= 8'hff;
		end else begin
			if (latch_write) begin
				address_latch <= latch_address;
				data_latch    <= latch_data;
			end

			if (control_write) begin
				control <= control_data;

				if (cpu_memory_write)
					modified <= 1'b1;

				if ((control_data[3:1] == 3'b100) &&
				    !control[0] && control_data[0])
					data_out <= cpu_memory[address_latch];
			end
		end

		if (memory_write) begin
			cpu_memory[memory_write_address] <= memory_write_data;
			host_memory[memory_write_address] <= memory_write_data;
		end
	end

endmodule
