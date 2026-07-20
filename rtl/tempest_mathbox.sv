//============================================================================
//  Atari Tempest math box
//
//  Written 2026 by Videodr0me
//
//  Implements the microcoded processor shown on Tempest schematic Sheet 3B.
//  The command and microcode PROMs are loaded from the original ROM set.
//============================================================================

module tempest_mathbox
(
	input  logic        clk,
	input  logic        reset,
	input  logic        ce_3m,

	input  logic        start,
	input  logic  [4:0] command,
	input  logic  [7:0] data_in,
	output logic        busy,
	output logic [15:0] result,

	input  logic        rom_we,
	input  logic  [2:0] rom_index,
	input  logic  [7:0] rom_addr,
	input  logic  [7:0] rom_data
);

	(* ramstyle = "MLAB" *) logic [7:0] command_rom [0:31];
	(* ramstyle = "MLAB" *) logic [3:0] prom_e1 [0:255];
	(* ramstyle = "MLAB" *) logic [3:0] prom_f1 [0:255];
	(* ramstyle = "MLAB" *) logic [3:0] prom_h1 [0:255];
	(* ramstyle = "MLAB" *) logic [3:0] prom_j1 [0:255];
	(* ramstyle = "MLAB" *) logic [3:0] prom_k1 [0:255];
	(* ramstyle = "MLAB" *) logic [3:0] prom_l1 [0:255];

	logic [15:0] ram [0:15];
	logic [15:0] q;
	logic  [7:0] micro_pc;
	logic  [7:0] jump_target;
	logic  [7:0] host_data;
	logic        previous_q0;

	logic [23:0] micro;
	logic  [3:0] reg_a;
	logic  [3:0] reg_b;
	logic        i2_high;
	logic        i2_low;
	logic        i1;
	logic        i0;
	logic        stall;
	logic  [2:0] alu_function;
	logic        load_target;
	logic  [2:0] destination;
	logic        signed_shift;
	logic        jump;
	logic        multiply;
	logic        carry_in;

	logic        effective_i1;
	logic  [2:0] source_control_low;
	logic  [2:0] source_control_high;
	logic [15:0] source_low;
	logic [15:0] source_high;
	logic [15:0] operand_r;
	logic [15:0] operand_s;
	logic [15:0] alu_left;
	logic [15:0] alu_right;
	logic [16:0] alu_sum;
	logic [15:0] lower_sum;
	logic [15:0] alu_result;
	logic        alu_overflow;
	logic        msb_star;
	logic [15:0] y;
	logic  [7:0] branch_target;

	integer index;

	function automatic logic [15:0] select_sources
	(
		input logic [2:0] control,
		input logic [7:0] a_value,
		input logic [7:0] b_value,
		input logic [7:0] q_value,
		input logic [7:0] d_value
	);
		logic [7:0] r_value;
		logic [7:0] s_value;
		begin
			case (control)
				3'b000: begin r_value = a_value; s_value = q_value; end
				3'b001: begin r_value = a_value; s_value = b_value; end
				3'b010: begin r_value = 8'h00;   s_value = q_value; end
				3'b011: begin r_value = 8'h00;   s_value = b_value; end
				3'b100: begin r_value = 8'h00;   s_value = a_value; end
				3'b101: begin r_value = d_value; s_value = a_value; end
				3'b110: begin r_value = d_value; s_value = q_value; end
				default: begin r_value = d_value; s_value = 8'h00; end
			endcase
			select_sources = {r_value, s_value};
		end
	endfunction

	always_comb begin
		micro = {
			prom_l1[micro_pc],
			prom_k1[micro_pc],
			prom_j1[micro_pc],
			prom_h1[micro_pc],
			prom_f1[micro_pc],
			prom_e1[micro_pc]
		};

		reg_a         = micro[23:20];
		reg_b         = micro[19:16];
		i2_high       = micro[15];
		i2_low        = micro[14];
		i1            = micro[13];
		i0            = micro[12];
		stall         = micro[11];
		alu_function  = micro[10:8];
		load_target   = micro[7];
		destination   = micro[6:4];
		signed_shift  = micro[3];
		jump          = micro[2];
		multiply      = micro[1];
		carry_in      = micro[0];

		effective_i1       = i1 ^ (multiply & ~previous_q0);
		source_control_low  = {i2_low,  effective_i1, i0};
		source_control_high = {i2_high, effective_i1, i0};
		source_low = select_sources(
			source_control_low,
			ram[reg_a][7:0],
			ram[reg_b][7:0],
			q[7:0],
			host_data
		);
		source_high = select_sources(
			source_control_high,
			ram[reg_a][15:8],
			ram[reg_b][15:8],
			q[15:8],
			host_data
		);
		operand_r = {source_high[15:8], source_low[15:8]};
		operand_s = {source_high[7:0],  source_low[7:0]};

		alu_left     = 16'h0000;
		alu_right    = 16'h0000;
		alu_sum      = 17'h00000;
		lower_sum    = 16'h0000;
		alu_result   = 16'h0000;
		alu_overflow = 1'b0;

		case (alu_function)
			3'b000: begin
				alu_left  = operand_r;
				alu_right = operand_s;
				alu_sum   = {1'b0, alu_left} + {1'b0, alu_right} + carry_in;
				lower_sum = {1'b0, alu_left[14:0]} + {1'b0, alu_right[14:0]} + carry_in;
				alu_result = alu_sum[15:0];
				alu_overflow = lower_sum[15] ^ alu_sum[16];
			end
			3'b001: begin
				alu_left  = ~operand_r;
				alu_right = operand_s;
				alu_sum   = {1'b0, alu_left} + {1'b0, alu_right} + carry_in;
				lower_sum = {1'b0, alu_left[14:0]} + {1'b0, alu_right[14:0]} + carry_in;
				alu_result = alu_sum[15:0];
				alu_overflow = lower_sum[15] ^ alu_sum[16];
			end
			3'b010: begin
				alu_left  = operand_r;
				alu_right = ~operand_s;
				alu_sum   = {1'b0, alu_left} + {1'b0, alu_right} + carry_in;
				lower_sum = {1'b0, alu_left[14:0]} + {1'b0, alu_right[14:0]} + carry_in;
				alu_result = alu_sum[15:0];
				alu_overflow = lower_sum[15] ^ alu_sum[16];
			end
			3'b011: alu_result = operand_r | operand_s;
			3'b100: alu_result = operand_r & operand_s;
			3'b101: alu_result = ~operand_r & operand_s;
			3'b110: alu_result = operand_r ^ operand_s;
			default: alu_result = ~(operand_r ^ operand_s);
		endcase

		msb_star = signed_shift & (alu_overflow ^ alu_result[15]);
		y = (destination == 3'b010) ? ram[reg_a] : alu_result;
		branch_target = load_target ? {reg_a, reg_b} : jump_target;
	end

	always_ff @(posedge clk) begin
		if (rom_we) begin
			case (rom_index)
				3'd0: if (!rom_addr[7:5]) command_rom[rom_addr[4:0]] <= rom_data;
				3'd1: prom_e1[rom_addr] <= rom_data[3:0];
				3'd2: prom_f1[rom_addr] <= rom_data[3:0];
				3'd3: prom_h1[rom_addr] <= rom_data[3:0];
				3'd4: prom_j1[rom_addr] <= rom_data[3:0];
				3'd5: prom_k1[rom_addr] <= rom_data[3:0];
				3'd6: prom_l1[rom_addr] <= rom_data[3:0];
				default: ;
			endcase
		end

		if (reset) begin
			busy          <= 1'b0;
			result        <= 16'h0000;
			q             <= 16'h0000;
			micro_pc      <= 8'h00;
			jump_target   <= 8'h00;
			host_data     <= 8'h00;
			previous_q0   <= 1'b0;
			for (index = 0; index < 16; index = index + 1)
				ram[index] <= 16'h0000;
		end else if (start) begin
			busy        <= 1'b1;
			micro_pc    <= command_rom[command];
			host_data   <= data_in;
		end else if (ce_3m && busy) begin
			result <= y;

			if (load_target)
				jump_target <= {reg_a, reg_b};

			case (destination)
				3'b000: q <= alu_result;
				3'b010,
				3'b011: ram[reg_b] <= alu_result;
				3'b100: begin
					ram[reg_b] <= {msb_star, alu_result[15:1]};
					q <= {alu_result[0], q[15:1]};
					previous_q0 <= q[0];
				end
				3'b101: begin
					ram[reg_b] <= {msb_star, alu_result[15:1]};
					previous_q0 <= q[0];
				end
				3'b110: begin
					ram[reg_b] <= {alu_result[14:0], q[15]};
					q <= {q[14:0], 1'b0};
				end
				3'b111: ram[reg_b] <= {alu_result[14:0], 1'b0};
				default: ;
			endcase

			if (jump && !msb_star)
				micro_pc <= branch_target;
			else
				micro_pc <= micro_pc + 1'd1;

			if (stall)
				busy <= 1'b0;
		end
	end

endmodule
