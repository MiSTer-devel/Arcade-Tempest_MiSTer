//============================================================================
//  Tempest spinner input
//
//  Written 2026 by Videodr0me
//
//  Converts MiSTer relative and directional controls into the two four-bit
//  encoder counters observed through POKEY 1.
//============================================================================

module tempest_spinner #(
	parameter logic [3:0] MAX_PENDING_COUNTS = 4'd14
)(
	input  logic              clk,
	input  logic              reset,
	input  logic              time_tick,
	input  logic        [1:0] sample,
	input  logic signed [7:0] analog_x_1,
	input  logic signed [7:0] analog_y_1,
	input  logic signed [7:0] analog_x_2,
	input  logic signed [7:0] analog_y_2,
	input  logic              analog_circular,
	input  logic              left_1,
	input  logic              right_1,
	input  logic              left_2,
	input  logic              right_2,
	input  logic        [8:0] spinner_1,
	input  logic        [8:0] spinner_2,
	input  logic       [24:0] mouse,
	input  logic        [2:0] sensitivity,
	input  logic              reverse,
	output logic        [3:0] position_1,
	output logic        [3:0] position_2
);

	localparam logic signed [8:0] MAX_PENDING_Q4 =
		$signed({1'b0, MAX_PENDING_COUNTS, 4'b0000});
	localparam logic signed [15:0] RATE_PHASE_LIMIT = 16'sd16_384;

	logic              time_tick_q;
	logic        [1:0] sample_q;
	logic signed [7:0] analog_x_q [0:1];
	logic signed [7:0] analog_y_q [0:1];
	logic        [1:0] left_q;
	logic        [1:0] right_q;
	logic        [8:0] spinner_q [0:1];
	logic       [24:0] mouse_q;
	logic        [2:0] sensitivity_q;
	logic              reverse_q;
	logic              analog_circular_q;
	logic              input_valid_q;

	logic        [1:0] spinner_toggle_seen;
	logic              mouse_toggle_seen;
	logic              input_ready;
	logic              reverse_previous;
	logic              circular_previous;

	logic signed [8:0] pending_q4 [0:1];
	logic signed [14:0] rate_phase [0:1];
	logic        [3:0] position_state [0:1];

	logic              spinner_event [0:1];
	logic              mouse_event;
	logic signed [9:0] raw_event [0:1];
	logic signed [9:0] raw_mouse_event;
	logic signed [9:0] directed_event [0:1];
	logic signed [9:0] directed_mouse_event;
	logic signed [13:0] event_q3 [0:1];
	logic signed [13:0] mouse_event_q3;
	logic signed [15:0] event_q4 [0:1];
	logic signed  [8:0] directional_rate [0:1];
	logic signed [13:0] rate_eighths [0:1];
	logic signed [15:0] rate_sum [0:1];
	logic signed [15:0] rate_phase_adjusted [0:1];
	logic signed [14:0] rate_phase_next [0:1];
	logic signed  [1:0] rate_step [0:1];
	logic signed [15:0] rate_step_q4 [0:1];
	logic signed  [4:0] sample_delta [0:1];
	logic signed [15:0] sample_delta_q4 [0:1];
	logic signed [15:0] pending_sum [0:1];
	logic signed  [8:0] pending_next [0:1];
	logic        [8:0] analog_magnitude [0:1];

	logic signed [7:0] circular_delta;
	logic              circular_player;
	logic              circular_valid;
	logic              circular_ready;
	logic              mode_changed;

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

	function automatic logic signed [13:0] scale_q3(
		input logic signed [9:0] value,
		input logic        [2:0] setting
	);
		logic signed [13:0] extended_value;
		begin
			extended_value = {{4{value[9]}}, value};
			case (setting)
				3'd0: scale_q3 = extended_value <<< 3; // 1.0x
				3'd1: scale_q3 = (extended_value <<< 2) +
				                   (extended_value <<< 1); // 0.75x
				3'd2: scale_q3 = extended_value <<< 2; // 0.5x
				3'd3: scale_q3 = extended_value <<< 1; // 0.25x
				3'd4: scale_q3 = extended_value;       // 0.125x
				3'd5: scale_q3 = (extended_value <<< 3) +
				                   (extended_value <<< 1); // 1.25x
				3'd6: scale_q3 = (extended_value <<< 3) +
				                   (extended_value <<< 2); // 1.5x
				default: scale_q3 = extended_value <<< 4; // 2.0x
			endcase
		end
	endfunction

	function automatic logic signed [4:0] counts_for_sample(
		input logic signed [8:0] pending
	);
		logic signed [9:0] extended_pending;
		logic        [9:0] magnitude;
		logic        [4:0] count_magnitude;
		begin
			extended_pending = {pending[8], pending};
			magnitude = extended_pending[9] ? -extended_pending : extended_pending;
			count_magnitude = magnitude[8:4];
			if (count_magnitude > 5'd7)
				count_magnitude = 5'd7;
			counts_for_sample = extended_pending[9] ?
			                    -$signed(count_magnitude) :
			                     $signed(count_magnitude);
		end
	endfunction

	function automatic logic signed [8:0] saturate_pending(
		input logic signed [15:0] value
	);
		begin
			if (value > MAX_PENDING_Q4)
				saturate_pending = MAX_PENDING_Q4;
			else if (value < -MAX_PENDING_Q4)
				saturate_pending = -MAX_PENDING_Q4;
			else
				saturate_pending = value[8:0];
		end
	endfunction

	always_ff @(posedge clk) begin
		if (reset) begin
			time_tick_q        <= 1'b0;
			sample_q           <= 2'b00;
			analog_x_q[0]      <= 8'sd0;
			analog_y_q[0]      <= 8'sd0;
			analog_x_q[1]      <= 8'sd0;
			analog_y_q[1]      <= 8'sd0;
			left_q             <= 2'b00;
			right_q            <= 2'b00;
			spinner_q[0]       <= 9'd0;
			spinner_q[1]       <= 9'd0;
			mouse_q            <= 25'd0;
			sensitivity_q      <= 3'd0;
			reverse_q          <= 1'b0;
			analog_circular_q  <= 1'b0;
			input_valid_q       <= 1'b0;
		end else begin
			time_tick_q        <= time_tick;
			sample_q           <= sample;
			analog_x_q[0]      <= analog_x_1;
			analog_y_q[0]      <= analog_y_1;
			analog_x_q[1]      <= analog_x_2;
			analog_y_q[1]      <= analog_y_2;
			left_q             <= {left_2, left_1};
			right_q            <= {right_2, right_1};
			spinner_q[0]       <= spinner_1;
			spinner_q[1]       <= spinner_2;
			mouse_q            <= mouse;
			sensitivity_q      <= sensitivity;
			reverse_q          <= reverse;
			analog_circular_q  <= analog_circular;
			input_valid_q       <= 1'b1;
		end
	end

	tempest_circular_stick circular_stick (
		.clk(clk),
		.reset(reset),
		.enable(analog_circular_q),
		.analog_x_1(analog_x_q[0]),
		.analog_y_1(analog_y_q[0]),
		.analog_x_2(analog_x_q[1]),
		.analog_y_2(analog_y_q[1]),
		.delta(circular_delta),
		.delta_player(circular_player),
		.delta_valid(circular_valid),
		.delta_ready(circular_ready)
	);

	always_comb begin
		mode_changed = (reverse_q != reverse_previous) ||
		               (analog_circular_q != circular_previous);
		circular_ready = input_ready && analog_circular_q && !mode_changed;
		mouse_event = input_ready && (mouse_q[24] != mouse_toggle_seen);
		raw_mouse_event = mouse_event ?
			$signed({mouse_q[4], mouse_q[4], mouse_q[15:8]}) : 10'sd0;
		directed_mouse_event = reverse_q ? -raw_mouse_event : raw_mouse_event;
		mouse_event_q3 = scale_q3(directed_mouse_event, sensitivity_q);

		for (combinational_channel = 0; combinational_channel < 2;
		     combinational_channel = combinational_channel + 1) begin
			spinner_event[combinational_channel] = input_ready &&
				(spinner_q[combinational_channel][8] !=
				 spinner_toggle_seen[combinational_channel]);
			raw_event[combinational_channel] = 10'sd0;
			if (spinner_event[combinational_channel])
				raw_event[combinational_channel] =
					raw_event[combinational_channel] +
					$signed({{2{spinner_q[combinational_channel][7]}},
					         spinner_q[combinational_channel][7:0]});
			if (circular_valid && circular_ready &&
			    (circular_player == (combinational_channel != 0)))
				raw_event[combinational_channel] =
					raw_event[combinational_channel] +
				                     $signed({{2{circular_delta[7]}},
				                              circular_delta});

			directed_event[combinational_channel] = reverse_q ?
				-raw_event[combinational_channel] : raw_event[combinational_channel];
			event_q3[combinational_channel] =
				scale_q3(directed_event[combinational_channel], sensitivity_q);
			event_q4[combinational_channel] =
				$signed({{2{event_q3[combinational_channel][13]}},
				          event_q3[combinational_channel]}) <<< 1;
			if (combinational_channel == 0)
				// Treating the mouse Q3 result as Q4 applies its 1/2 base gain.
				event_q4[combinational_channel] =
					event_q4[combinational_channel] +
					$signed({{2{mouse_event_q3[13]}}, mouse_event_q3});

			analog_magnitude[combinational_channel] =
				absolute_8(analog_x_q[combinational_channel]);
			directional_rate[combinational_channel] = 9'sd0;
			if (!analog_circular_q) begin
				if (analog_magnitude[combinational_channel] > 9'd12)
					directional_rate[combinational_channel] =
						$signed({analog_x_q[combinational_channel][7],
						         analog_x_q[combinational_channel]});
				else if (left_q[combinational_channel] ^
				         right_q[combinational_channel])
					directional_rate[combinational_channel] =
						right_q[combinational_channel] ?
					                            9'sd56 : -9'sd56;
			end
			if (reverse_q)
				directional_rate[combinational_channel] =
					-directional_rate[combinational_channel];
			rate_eighths[combinational_channel] = scale_q3(
				{{1{directional_rate[combinational_channel][8]}},
				 directional_rate[combinational_channel]},
				sensitivity_q
			);

			rate_sum[combinational_channel] =
				{{1{rate_phase[combinational_channel][14]}},
				 rate_phase[combinational_channel]} +
				{{2{rate_eighths[combinational_channel][13]}},
				 rate_eighths[combinational_channel]};
			rate_step[combinational_channel] = 2'sd0;
			rate_phase_adjusted[combinational_channel] =
				rate_sum[combinational_channel];
			if (rate_sum[combinational_channel] >= RATE_PHASE_LIMIT) begin
				rate_step[combinational_channel] = 2'sd1;
				rate_phase_adjusted[combinational_channel] =
					rate_sum[combinational_channel] - RATE_PHASE_LIMIT;
			end else if (rate_sum[combinational_channel] <= -RATE_PHASE_LIMIT) begin
				rate_step[combinational_channel] = -2'sd1;
				rate_phase_adjusted[combinational_channel] =
					rate_sum[combinational_channel] + RATE_PHASE_LIMIT;
			end
			rate_phase_next[combinational_channel] =
				rate_phase_adjusted[combinational_channel][14:0];

			sample_delta[combinational_channel] =
				sample_q[combinational_channel] ?
				counts_for_sample(pending_q4[combinational_channel]) : 5'sd0;
			sample_delta_q4[combinational_channel] =
				{{11{sample_delta[combinational_channel][4]}},
				 sample_delta[combinational_channel]} <<< 4;
			rate_step_q4[combinational_channel] =
				{{14{rate_step[combinational_channel][1]}},
				 rate_step[combinational_channel]} <<< 4;
			pending_sum[combinational_channel] =
				{{7{pending_q4[combinational_channel][8]}},
				 pending_q4[combinational_channel]} -
				sample_delta_q4[combinational_channel] +
				event_q4[combinational_channel];
			if (time_tick_q)
				pending_sum[combinational_channel] =
					pending_sum[combinational_channel] +
					rate_step_q4[combinational_channel];
			pending_next[combinational_channel] =
				saturate_pending(pending_sum[combinational_channel]);
		end
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			spinner_toggle_seen <= 2'b00;
			mouse_toggle_seen   <= 1'b0;
			input_ready         <= 1'b0;
			reverse_previous    <= 1'b0;
			circular_previous   <= 1'b0;
			for (sequential_channel = 0; sequential_channel < 2;
			     sequential_channel = sequential_channel + 1) begin
				pending_q4[sequential_channel]   <= 9'sd0;
				rate_phase[sequential_channel]   <= 15'sd0;
				position_state[sequential_channel] <= 4'd0;
			end
		end else if (!input_ready) begin
			if (input_valid_q) begin
				spinner_toggle_seen <= {spinner_q[1][8], spinner_q[0][8]};
				mouse_toggle_seen   <= mouse_q[24];
				reverse_previous    <= reverse_q;
				circular_previous   <= analog_circular_q;
				input_ready         <= 1'b1;
			end
		end else begin
			spinner_toggle_seen <= {spinner_q[1][8], spinner_q[0][8]};
			mouse_toggle_seen   <= mouse_q[24];
			reverse_previous    <= reverse_q;
			circular_previous   <= analog_circular_q;

			if (mode_changed) begin
				for (sequential_channel = 0; sequential_channel < 2;
				     sequential_channel = sequential_channel + 1) begin
					pending_q4[sequential_channel] <= 9'sd0;
					rate_phase[sequential_channel] <= 15'sd0;
				end
			end else begin
				for (sequential_channel = 0; sequential_channel < 2;
				     sequential_channel = sequential_channel + 1) begin
					pending_q4[sequential_channel] <=
						pending_next[sequential_channel];
					if (time_tick_q)
						rate_phase[sequential_channel] <=
							rate_phase_next[sequential_channel];
					if (sample_q[sequential_channel])
						position_state[sequential_channel] <=
							position_state[sequential_channel] +
							sample_delta[sequential_channel][3:0];
				end
			end
		end
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			position_1 <= 4'd0;
			position_2 <= 4'd0;
		end else begin
			position_1 <= position_state[0];
			position_2 <= position_state[1];
		end
	end

endmodule
