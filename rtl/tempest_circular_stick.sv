//============================================================================
//  Tempest circular analog-stick input
//
//  Written 2026 by Videodr0me
//
//  Converts angular movement from either player's analog stick into signed
//  Tempest spinner counts using one shared iterative CORDIC.
//============================================================================

module tempest_circular_stick #(
	parameter integer ENTER_RADIUS = 28,
	parameter integer EXIT_RADIUS  = 20
)(
	input  logic              clk,
	input  logic              reset,
	input  logic              enable,
	input  logic signed [7:0] analog_x_1,
	input  logic signed [7:0] analog_y_1,
	input  logic signed [7:0] analog_x_2,
	input  logic signed [7:0] analog_y_2,
	output logic signed [7:0] delta,
	output logic              delta_player,
	output logic              delta_valid,
	input  logic              delta_ready
);

	localparam integer CORDIC_STAGES = 7;
	localparam logic [1:0] STATE_IDLE    = 2'd0;
	localparam logic [1:0] STATE_CORDIC  = 2'd1;
	localparam logic [1:0] STATE_RESOLVE = 2'd2;
	localparam logic [1:0] STATE_OUTPUT  = 2'd3;

	logic              enable_q;
	logic              delta_ready_q;
	logic signed [7:0] analog_x_q [0:1];
	logic signed [7:0] analog_y_q [0:1];

	logic              stick_engaged [0:1];
	logic              angle_valid [0:1];
	logic signed [7:0] sampled_x [0:1];
	logic signed [7:0] sampled_y [0:1];
	logic        [7:0] last_angle [0:1];
	logic signed [8:0] angle_remainder [0:1];

	logic [8:0] x_magnitude [0:1];
	logic [8:0] y_magnitude [0:1];
	logic [8:0] radius [0:1];
	logic       release_request [0:1];
	logic       conversion_request [0:1];

	logic signed [9:0] cordic_x;
	logic signed [9:0] cordic_y;
	logic signed [8:0] cordic_angle;
	logic        [2:0] cordic_stage;
	logic              cordic_owner;
	logic              round_robin;
	logic              sample_x_negative;
	logic              sample_y_negative;
	logic        [7:0] resolved_angle_q;
	logic        [1:0] state;

	logic signed [9:0] cordic_x_shifted;
	logic signed [9:0] cordic_y_shifted;
	logic signed [9:0] cordic_x_next;
	logic signed [9:0] cordic_y_next;
	logic signed [8:0] cordic_angle_next;
	logic        [8:0] sampled_x_magnitude;
	logic        [8:0] sampled_y_magnitude;
	logic        [6:0] first_quadrant_angle;
	logic        [7:0] resolved_angle;
	logic        [7:0] angle_difference;
	logic signed [8:0] angle_delta;
	logic signed [15:0] extended_angle_delta;
	logic signed [15:0] motion_numerator;
	logic        [15:0] motion_magnitude;
	logic signed  [7:0] generated_steps;
	logic signed  [8:0] generated_remainder;
	logic               selected_request;
	logic               selected_player;

	integer combinational_channel;
	integer sequential_channel;

	function automatic logic [8:0] absolute_8(
		input logic signed [7:0] value
	);
		logic signed [8:0] extended_value;
		begin
			extended_value = {value[7], value};
			absolute_8 = extended_value[8] ? -extended_value : extended_value;
		end
	endfunction

	function automatic logic signed [8:0] cordic_increment(
		input logic [2:0] stage_index
	);
		begin
			case (stage_index)
				3'd0: cordic_increment = 9'sd32;
				3'd1: cordic_increment = 9'sd19;
				3'd2: cordic_increment = 9'sd10;
				3'd3: cordic_increment = 9'sd5;
				3'd4: cordic_increment = 9'sd3;
				3'd5: cordic_increment = 9'sd1;
				default: cordic_increment = 9'sd1;
			endcase
		end
	endfunction

	always_ff @(posedge clk) begin
		if (reset) begin
			enable_q       <= 1'b0;
			delta_ready_q  <= 1'b0;
			analog_x_q[0]  <= 8'sd0;
			analog_y_q[0]  <= 8'sd0;
			analog_x_q[1]  <= 8'sd0;
			analog_y_q[1]  <= 8'sd0;
		end else begin
			enable_q       <= enable;
			delta_ready_q  <= delta_ready;
			analog_x_q[0]  <= analog_x_1;
			analog_y_q[0]  <= analog_y_1;
			analog_x_q[1]  <= analog_x_2;
			analog_y_q[1]  <= analog_y_2;
		end
	end

	always_comb begin
		for (combinational_channel = 0; combinational_channel < 2;
		     combinational_channel = combinational_channel + 1) begin
			x_magnitude[combinational_channel] =
				absolute_8(analog_x_q[combinational_channel]);
			y_magnitude[combinational_channel] =
				absolute_8(analog_y_q[combinational_channel]);
			if (x_magnitude[combinational_channel] >=
			    y_magnitude[combinational_channel])
				radius[combinational_channel] =
					x_magnitude[combinational_channel] +
					(y_magnitude[combinational_channel] >> 1);
			else
				radius[combinational_channel] =
					y_magnitude[combinational_channel] +
					(x_magnitude[combinational_channel] >> 1);

			release_request[combinational_channel] =
				stick_engaged[combinational_channel] &&
				(radius[combinational_channel] <= EXIT_RADIUS);
			conversion_request[combinational_channel] =
				(!stick_engaged[combinational_channel] &&
				 (radius[combinational_channel] >= ENTER_RADIUS)) ||
				(stick_engaged[combinational_channel] &&
				 (radius[combinational_channel] >= ENTER_RADIUS) &&
				 ((analog_x_q[combinational_channel] !=
				   sampled_x[combinational_channel]) ||
				  (analog_y_q[combinational_channel] !=
				   sampled_y[combinational_channel])));
		end

		selected_request = conversion_request[0] || conversion_request[1];
		if (conversion_request[0] && conversion_request[1])
			selected_player = round_robin;
		else
			selected_player = conversion_request[1];

		cordic_x_shifted = cordic_x >>> cordic_stage;
		cordic_y_shifted = cordic_y >>> cordic_stage;
		cordic_x_next = cordic_x;
		cordic_y_next = cordic_y;
		cordic_angle_next = cordic_angle;
		if (cordic_y > 0) begin
			cordic_x_next = cordic_x + cordic_y_shifted;
			cordic_y_next = cordic_y - cordic_x_shifted;
			cordic_angle_next = cordic_angle + cordic_increment(cordic_stage);
		end else if (cordic_y < 0) begin
			cordic_x_next = cordic_x - cordic_y_shifted;
			cordic_y_next = cordic_y + cordic_x_shifted;
			cordic_angle_next = cordic_angle - cordic_increment(cordic_stage);
		end

		sampled_x_magnitude = absolute_8(sampled_x[cordic_owner]);
		sampled_y_magnitude = absolute_8(sampled_y[cordic_owner]);
		if (sampled_y_magnitude == 9'd0)
			first_quadrant_angle = 7'd0;
		else if (sampled_x_magnitude == 9'd0)
			first_quadrant_angle = 7'd64;
		else if (sampled_x_magnitude == sampled_y_magnitude)
			first_quadrant_angle = 7'd32;
		else if (cordic_angle_next < 0)
			first_quadrant_angle = 7'd0;
		else if (cordic_angle_next > 9'sd64)
			first_quadrant_angle = 7'd64;
		else
			first_quadrant_angle = cordic_angle_next[6:0];

		case ({sample_y_negative, sample_x_negative})
			2'b00: resolved_angle = {1'b0, first_quadrant_angle};
			2'b01: resolved_angle = 8'd128 - first_quadrant_angle;
			2'b11: resolved_angle = 8'd128 + first_quadrant_angle;
			default: resolved_angle = 8'd0 - first_quadrant_angle;
		endcase

		angle_difference = resolved_angle_q - last_angle[cordic_owner];
		angle_delta = {angle_difference[7], angle_difference};
		extended_angle_delta = {{7{angle_delta[8]}}, angle_delta};
		motion_numerator =
			((extended_angle_delta <<< 7) -
			 (extended_angle_delta <<< 4) -
			 (extended_angle_delta <<< 2)) +
			{{7{angle_remainder[cordic_owner][8]}},
			 angle_remainder[cordic_owner]};
		motion_magnitude = motion_numerator[15] ?
		                   -motion_numerator : motion_numerator;
		if (motion_numerator[15]) begin
			generated_steps = -$signed({1'b0, motion_magnitude[14:8]});
			generated_remainder = -$signed({1'b0, motion_magnitude[7:0]});
		end else begin
			generated_steps = $signed({1'b0, motion_magnitude[14:8]});
			generated_remainder = $signed({1'b0, motion_magnitude[7:0]});
		end
	end

	always_ff @(posedge clk) begin
		if (reset || !enable_q) begin
			for (sequential_channel = 0; sequential_channel < 2;
			     sequential_channel = sequential_channel + 1) begin
				stick_engaged[sequential_channel]  <= 1'b0;
				angle_valid[sequential_channel]     <= 1'b0;
				sampled_x[sequential_channel]       <= 8'sd0;
				sampled_y[sequential_channel]       <= 8'sd0;
				last_angle[sequential_channel]      <= 8'd0;
				angle_remainder[sequential_channel] <= 9'sd0;
			end
			cordic_x          <= 10'sd0;
			cordic_y          <= 10'sd0;
			cordic_angle      <= 9'sd0;
			cordic_stage      <= 3'd0;
			cordic_owner      <= 1'b0;
			round_robin       <= 1'b0;
			sample_x_negative <= 1'b0;
			sample_y_negative <= 1'b0;
			resolved_angle_q  <= 8'd0;
			state             <= STATE_IDLE;
			delta             <= 8'sd0;
			delta_player      <= 1'b0;
			delta_valid       <= 1'b0;
		end else begin
			case (state)
				STATE_IDLE: begin
					for (sequential_channel = 0; sequential_channel < 2;
					     sequential_channel = sequential_channel + 1) begin
						if (release_request[sequential_channel]) begin
							stick_engaged[sequential_channel]  <= 1'b0;
							angle_valid[sequential_channel]     <= 1'b0;
							angle_remainder[sequential_channel] <= 9'sd0;
						end
					end

					if (selected_request) begin
						stick_engaged[selected_player] <= 1'b1;
						sampled_x[selected_player] <= analog_x_q[selected_player];
						sampled_y[selected_player] <= analog_y_q[selected_player];
						cordic_x <= $signed({1'b0, x_magnitude[selected_player]});
						cordic_y <= $signed({1'b0, y_magnitude[selected_player]});
						cordic_angle <= 9'sd0;
						cordic_stage <= 3'd0;
						cordic_owner <= selected_player;
						round_robin <= ~selected_player;
						sample_x_negative <= analog_x_q[selected_player][7];
						sample_y_negative <= analog_y_q[selected_player][7];
						state <= STATE_CORDIC;
					end
				end

				STATE_CORDIC: begin
					cordic_x     <= cordic_x_next;
					cordic_y     <= cordic_y_next;
					cordic_angle <= cordic_angle_next;
					if (cordic_stage == CORDIC_STAGES - 1) begin
						resolved_angle_q <= resolved_angle;
						state <= STATE_RESOLVE;
					end else begin
						cordic_stage <= cordic_stage + 1'd1;
					end
				end

				STATE_RESOLVE: begin
					last_angle[cordic_owner] <= resolved_angle_q;
					if (!angle_valid[cordic_owner]) begin
						angle_valid[cordic_owner] <= 1'b1;
						angle_remainder[cordic_owner] <= 9'sd0;
						state <= STATE_IDLE;
					end else begin
						angle_remainder[cordic_owner] <= generated_remainder;
						if (generated_steps != 8'sd0) begin
							delta        <= generated_steps;
							delta_player <= cordic_owner;
							delta_valid  <= 1'b1;
							state <= STATE_OUTPUT;
						end else begin
							state <= STATE_IDLE;
						end
					end
				end

				default: begin
					if (delta_ready_q) begin
						delta_valid <= 1'b0;
						state <= STATE_IDLE;
					end
				end
			endcase
		end
	end

endmodule
