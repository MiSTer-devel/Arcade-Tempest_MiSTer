// ============================================================================
// videodr0me_fb: Phosphor Timing
// written 2026 by Videodr0me
// Measures source-frame cadence and converts draw phases to physical age.
// ============================================================================

module vfb_phosphor_timing #(
	parameter [15:0] AGE_QUANTUM_CLKS = 16'd18519
) (
	input  logic        clk_source,
	input  logic        clk_sys,
	input  logic        reset_source,
	input  logic        reset_sys,
	input  logic        frame_done,

	input  logic        eof_token_popped,
	input  logic [15:0] eof_frame_tick_clks_popped,
	input  logic [1:0]  buf_draw,
	input  logic [1:0]  buf_display,
	input  logic        vbl_swap_req,

	output logic [3:0]  draw_idx,
	output logic [15:0] active_frame_tick_clks,
	output logic [3:0]  readout_draw_idx,
	output logic [63:0] readout_age_map
);

	localparam [15:0] DEFAULT_TICK_CLKS =
		(AGE_QUANTUM_CLKS == 16'd0) ? 16'd1 : AGE_QUANTUM_CLKS;
	localparam [16:0] AGE_QUANTUM_EXT = {1'b0, DEFAULT_TICK_CLKS};
	localparam [16:0] AGE_HALF_QUANTUM = {1'b0, (DEFAULT_TICK_CLKS >> 1)};
	localparam [63:0] IDENTITY_AGE_MAP = 64'hFEDCBA9876543210;

	function automatic [15:0] frame_tick_from_period(input logic [19:0] period);
		logic [16:0] rounded_tick;
		begin
			if (period[19:4] == 16'hFFFF) begin
				frame_tick_from_period = 16'hFFFF;
			end else begin
				rounded_tick = {1'b0, period[19:4]} + {16'd0, period[3]};
				frame_tick_from_period = (rounded_tick == 17'd0)
					? 16'd1 : rounded_tick[15:0];
			end
		end
	endfunction

	// Source domain: a free-running 16-phase counter follows the previously
	// measured frame period. Each EOF carries the phase duration used while its
	// frame was drawn.
	logic        frame_done_q;
	logic        have_eof_reference;
	logic [19:0] eof_period_count;
	logic [15:0] draw_tick_count;
	logic [3:0]  draw_idx_source;

	wire frame_done_rise = frame_done && !frame_done_q;
	wire [15:0] measured_frame_tick_clks = frame_tick_from_period(eof_period_count);

	always_ff @(posedge clk_source) begin
		if (reset_source) begin
			frame_done_q <= 1'b0;
			have_eof_reference <= 1'b0;
			eof_period_count <= 20'd0;
			draw_tick_count <= 16'd0;
			draw_idx_source <= 4'd0;
			active_frame_tick_clks <= DEFAULT_TICK_CLKS;
		end else begin
			frame_done_q <= frame_done;

			if (draw_tick_count >= active_frame_tick_clks - 16'd1) begin
				draw_tick_count <= 16'd0;
				draw_idx_source <= draw_idx_source + 4'd1;
			end else begin
				draw_tick_count <= draw_tick_count + 16'd1;
			end

			if (frame_done_rise) begin
				eof_period_count <= 20'd1;
				if (have_eof_reference)
					active_frame_tick_clks <= measured_frame_tick_clks;
				else
					have_eof_reference <= 1'b1;
			end else if (eof_period_count != 20'hFFFFF) begin
				eof_period_count <= eof_period_count + 20'd1;
			end
		end
	end

	// Synchronize the free-running phase counter into the renderer domain.
	logic [3:0] draw_idx_sync1;
	always_ff @(posedge clk_sys) begin
		if (reset_sys) begin
			draw_idx_sync1 <= 4'd0;
			draw_idx <= 4'd0;
		end else begin
			draw_idx_sync1 <= draw_idx_source;
			draw_idx <= draw_idx_sync1;
		end
	end

	// A serial divider builds all 16 rounded physical-age mappings from each
	// completed frame's measured draw-phase duration, then publishes the map
	// atomically to that frame's buffer.
	logic [63:0] buf_age_map [0:3];
	logic        map_pending;
	logic [1:0]  map_pending_buf;
	logic [15:0] map_pending_tick;
	logic        map_busy;
	logic [1:0]  map_build_buf;
	logic [3:0]  map_build_index;
	logic [3:0]  map_build_age;
	logic [15:0] map_build_tick;
	logic [16:0] map_build_remainder;
	logic [63:0] map_build_data;
	logic [1:0]  prev_buf_display;
	integer buf_i;

	wire [15:0] popped_frame_tick_clks =
		(eof_frame_tick_clks_popped == 16'd0)
			? DEFAULT_TICK_CLKS : eof_frame_tick_clks_popped;

	always_ff @(posedge clk_sys) begin
		if (reset_sys) begin
			map_pending <= 1'b0;
			map_pending_buf <= 2'd0;
			map_pending_tick <= DEFAULT_TICK_CLKS;
			map_busy <= 1'b0;
			map_build_buf <= 2'd0;
			map_build_index <= 4'd0;
			map_build_age <= 4'd0;
			map_build_tick <= DEFAULT_TICK_CLKS;
			map_build_remainder <= 17'd0;
			map_build_data <= 64'd0;
			prev_buf_display <= 2'd0;
			readout_draw_idx <= 4'd0;
			readout_age_map <= IDENTITY_AGE_MAP;
			for (buf_i = 0; buf_i < 4; buf_i = buf_i + 1)
				buf_age_map[buf_i] <= IDENTITY_AGE_MAP;
		end else begin
			prev_buf_display <= buf_display;
			if (vbl_swap_req || (buf_display != prev_buf_display)) begin
				readout_draw_idx <= draw_idx;
				readout_age_map <= buf_age_map[buf_display];
			end

			if (!map_busy && map_pending) begin
				map_pending <= 1'b0;
				map_busy <= 1'b1;
				map_build_buf <= map_pending_buf;
				map_build_index <= 4'd1;
				map_build_age <= 4'd0;
				map_build_tick <= map_pending_tick;
				map_build_remainder <= AGE_HALF_QUANTUM
					+ {1'b0, map_pending_tick};
				map_build_data <= 64'd0;
			end else if (map_busy) begin
				if ((map_build_age == 4'd15) ||
				    (map_build_remainder < AGE_QUANTUM_EXT)) begin
					if (map_build_index == 4'd15) begin
						buf_age_map[map_build_buf] <=
							{map_build_age, map_build_data[59:0]};
						map_busy <= 1'b0;
					end else begin
						map_build_data[{map_build_index, 2'b00} +: 4]
							<= map_build_age;
						map_build_index <= map_build_index + 4'd1;
						if (map_build_age != 4'd15)
							map_build_remainder <= map_build_remainder
								+ {1'b0, map_build_tick};
					end
				end else begin
					map_build_remainder <= map_build_remainder - AGE_QUANTUM_EXT;
					map_build_age <= map_build_age + 4'd1;
				end
			end

			if (eof_token_popped) begin
				map_pending_buf <= buf_draw;
				map_pending_tick <= popped_frame_tick_clks;
				map_pending <= 1'b1;
			end
		end
	end

endmodule
