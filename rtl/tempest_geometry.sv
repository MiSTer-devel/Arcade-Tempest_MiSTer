//============================================================================
//  Tempest vector geometry
//
//  Written 2026 by Videodr0me
//
//  Scales signed AVG coordinates, then applies the selected orientation around
//  the exact center of the even-sized raster.
//============================================================================

module tempest_geometry
(
	input  logic signed [14:0] source_x,
	input  logic signed [14:0] source_y,
	input  logic               mode_1080p,
	input  logic               mode_480p,
	input  logic               mode_240p,
	input  logic        [11:0] center_x,
	input  logic        [11:0] center_y,
	input  logic        [11:0] render_width,
	input  logic        [11:0] render_height,
	input  logic         [2:0] orientation,
	input  logic               zoom_far,
	output logic signed [23:0] raster_x,
	output logic signed [23:0] raster_y,
	output logic               beam_in_bounds
);

	logic signed [23:0] source_x_w;
	logic signed [23:0] source_y_w;
	logic signed [23:0] centered_y;
	logic signed [23:0] scale_x_term;
	logic signed [23:0] scale_y_term;
	logic signed [23:0] scaled_x;
	logic signed [23:0] scaled_y;
	logic signed [23:0] selected_x;
	logic signed [23:0] selected_y;
	logic signed [23:0] presented_y_axis;
	logic signed [23:0] oriented_x;
	logic signed [23:0] oriented_y;
	logic               quarter_turn;
	logic               output_x_negative;
	logic               output_y_negative;

	always_comb begin
		source_x_w = {{9{source_x[14]}}, source_x};
		source_y_w = {{9{source_y[14]}}, source_y};
		quarter_turn = (orientation == 3'd1) ||
		               (orientation == 3'd3) ||
		               (orientation == 3'd6) ||
		               (orientation == 3'd7);
		centered_y = zoom_far ? source_y_w : source_y_w - 24'sd736;
		scale_x_term = 24'sd0;
		scale_y_term = 24'sd0;
		scaled_x = 24'sd0;
		scaled_y = 24'sd0;

		if (mode_1080p) begin
			if (!zoom_far && quarter_turn) begin
				scaled_x = ((source_x_w << 7) - (source_x_w << 1) - source_x_w) >>> 11;
				scaled_y = ((centered_y << 7) - (centered_y << 1) - centered_y) >>> 11;
			end else if (!zoom_far) begin
				scaled_x = ((source_x_w << 6) + (source_x_w << 3) + source_x_w) >>> 10;
				scaled_y = ((centered_y << 6) + (centered_y << 3) + centered_y) >>> 10;
			end else if (quarter_turn) begin
				scaled_x = ((source_x_w << 6) - (source_x_w << 2) - source_x_w) >>> 10;
				scaled_y = ((centered_y << 6) - (centered_y << 2) - centered_y) >>> 10;
			end else begin
				scaled_x = ((source_x_w << 6) - source_x_w) >>> 10;
				scaled_y = ((centered_y << 6) - centered_y) >>> 10;
			end
		end else if (mode_480p || mode_240p) begin
			if (!zoom_far && quarter_turn) begin
				scaled_x = ((source_x_w << 6) - (source_x_w << 3) - source_x_w) >>> 11;
				scaled_y = ((centered_y << 6) - (centered_y << 3) - centered_y) >>> 11;
			end else if (!zoom_far) begin
				scaled_x = ((source_x_w << 6) + source_x_w) >>> 11;
				scaled_y = ((centered_y << 6) + centered_y) >>> 11;
			end else if (quarter_turn) begin
				scaled_x = ((source_x_w << 6) + (source_x_w << 5) +
				            (source_x_w << 3) + source_x_w) >>> 12;
				scaled_y = ((centered_y << 6) + (centered_y << 5) +
				            (centered_y << 3) + centered_y) >>> 12;
			end else begin
				scaled_x = ((source_x_w << 3) - source_x_w) >>> 8;
				scaled_y = ((centered_y << 3) - centered_y) >>> 8;
			end
		end else begin
			if (!zoom_far && quarter_turn) begin
				scale_x_term = (source_x_w << 5) + (source_x_w << 2) + source_x_w;
				scale_y_term = (centered_y << 5) + (centered_y << 2) + centered_y;
				scaled_x = ((scale_x_term << 3) + scale_x_term) >>> 13;
				scaled_y = ((scale_y_term << 3) + scale_y_term) >>> 13;
			end else if (!zoom_far) begin
				scale_x_term = (source_x_w << 6) + source_x_w;
				scale_y_term = (centered_y << 6) + centered_y;
				scaled_x = ((scale_x_term << 1) + scale_x_term) >>> 12;
				scaled_y = ((scale_y_term << 1) + scale_y_term) >>> 12;
			end else if (quarter_turn) begin
				scaled_x = ((source_x_w << 6) + (source_x_w << 4) - source_x_w) >>> 11;
				scaled_y = ((centered_y << 6) + (centered_y << 4) - centered_y) >>> 11;
			end else begin
				scaled_x = ((source_x_w << 4) + (source_x_w << 2) + source_x_w) >>> 9;
				scaled_y = ((centered_y << 4) + (centered_y << 2) + centered_y) >>> 9;
			end
		end

		case (orientation)
			3'd0: begin
				selected_x = scaled_x; output_x_negative = 1'b0;
				selected_y = scaled_y; output_y_negative = 1'b0;
			end
			3'd1: begin
				selected_x = scaled_y; output_x_negative = 1'b1;
				selected_y = scaled_x; output_y_negative = 1'b0;
			end
			3'd2: begin
				selected_x = scaled_x; output_x_negative = 1'b1;
				selected_y = scaled_y; output_y_negative = 1'b1;
			end
			3'd3: begin
				selected_x = scaled_y; output_x_negative = 1'b0;
				selected_y = scaled_x; output_y_negative = 1'b1;
			end
			3'd4: begin
				selected_x = scaled_x; output_x_negative = 1'b1;
				selected_y = scaled_y; output_y_negative = 1'b0;
			end
			3'd5: begin
				selected_x = scaled_x; output_x_negative = 1'b0;
				selected_y = scaled_y; output_y_negative = 1'b1;
			end
			3'd6: begin
				selected_x = scaled_y; output_x_negative = 1'b0;
				selected_y = scaled_x; output_y_negative = 1'b0;
			end
			default: begin
				selected_x = scaled_y; output_x_negative = 1'b1;
				selected_y = scaled_x; output_y_negative = 1'b1;
			end
		endcase

		oriented_x = output_x_negative ? -selected_x : selected_x;
		presented_y_axis = mode_240p ? (selected_y >>> 1) : selected_y;
		oriented_y = output_y_negative ? -presented_y_axis : presented_y_axis;
		raster_x = $signed({12'd0, center_x}) -
		           (output_x_negative ? 24'sd1 : 24'sd0) + oriented_x;
		raster_y = $signed({12'd0, center_y}) -
		           (output_y_negative ? 24'sd1 : 24'sd0) + oriented_y;
		beam_in_bounds = (raster_x >= 24'sd0) &&
		                 (raster_x < $signed({12'd0, render_width})) &&
		                 (raster_y >= 24'sd0) &&
		                 (raster_y < $signed({12'd0, render_height}));
	end

endmodule
