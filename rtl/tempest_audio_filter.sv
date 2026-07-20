// Tempest cabinet audio low-pass filter.
// Models the equivalent 10 kOhm / 15 nF low-pass response of the summed POKEY output.
//
// Written 2026 by Videodr0me.

module tempest_audio_filter
(
	input  logic       clk,
	input  logic       reset,
	input  logic       ce,
	input  logic       enable,
	input  logic [7:0] audio_in,
	output logic [7:0] audio_out
);

	localparam int FRACTION_BITS = 12;

	logic signed [21:0] target_q;
	logic signed [21:0] filtered_q = '0;
	logic signed [22:0] delta_q;
	logic signed [26:0] delta_extended;
	logic signed [26:0] correction_wide;
	logic signed [21:0] correction_q;

	always_comb begin
		target_q = $signed({1'b0, audio_in, {FRACTION_BITS{1'b0}}});
		delta_q = $signed({target_q[21], target_q}) -
		          $signed({filtered_q[21], filtered_q});
		delta_extended = {{4{delta_q[22]}}, delta_q};
		// 9/2048 at 1.512 MHz gives a 150 us nominal time constant.
		correction_wide = ((delta_extended <<< 3) + delta_extended) >>> 11;
		correction_q = $signed(correction_wide[21:0]);
	end

	always_ff @(posedge clk) begin
		if (reset)
			filtered_q <= '0;
		else if (ce)
			filtered_q <= filtered_q + correction_q;
	end

	always_comb begin
		if (enable)
			audio_out = filtered_q[FRACTION_BITS +: 8];
		else
			audio_out = audio_in;
	end

endmodule
