// ============================================================================
// CRT profile resolver.
// written 2026 by Videodr0me
//
// Turns the profile selector into the filter/readout option bits used by
// vfb_top. Fixed profiles come from per-resolution tables; Custom 1 and
// Custom 2 use their editable OSD setting banks.
// ============================================================================

module vfb_profile_resolver (
	input  logic [2:0]  profile,
	input  logic [11:0] fb_height,

	input  logic [2:0]  off_dot_mode,
	input  logic [1:0]  off_tonemapping,
	input  logic [1:0]  off_phosphor_mode,
	input  logic [22:0] custom1_settings,
	input  logic [22:0] custom2_settings,

	output logic [2:0]  dot_mode,
	output logic [1:0]  tonemapping,
	output logic [2:0]  bloom_width,
	output logic [2:0]  bloom_curve,
	output logic [2:0]  halo_filter,
	output logic [1:0]  halo_spread,
	output logic [1:0]  phosphor_mode,
	output logic        color_space,
	output logic [2:0]  color_channels,
	output logic        slot_mask,
	output logic        full_bypass
);

	localparam logic [2:0] PROFILE_OFF        = 3'd0;
	localparam logic [2:0] PROFILE_TOUCH      = 3'd1;
	localparam logic [2:0] PROFILE_TYPICAL    = 3'd2;
	localparam logic [2:0] PROFILE_OVERDRIVEN = 3'd3;
	localparam logic [2:0] PROFILE_NEON       = 3'd4;
	localparam logic [2:0] PROFILE_STRANGER   = 3'd5;
	localparam logic [2:0] PROFILE_CUSTOM1    = 3'd6;
	localparam logic [2:0] PROFILE_CUSTOM2    = 3'd7;

	localparam logic [2:0] DOT_AUTO    = 3'd0;
	localparam logic [2:0] DOT_PIXEL   = 3'd1;
	localparam logic [2:0] DOT_2X      = 3'd2;
	localparam logic [2:0] DOT_25X     = 3'd3;

	localparam logic [1:0] TONE_LINEAR1 = 2'd0;
	localparam logic [1:0] TONE_LINEAR2 = 2'd1;
	localparam logic [1:0] TONE_BRIGHT  = 2'd2;
	localparam logic [1:0] TONE_OFF     = 2'd3;

	localparam logic [2:0] BLOOM_OFF    = 3'd0;
	localparam logic [2:0] BLOOM_THIN   = 3'd1;
	localparam logic [2:0] BLOOM_TIGHT  = 3'd2;
	localparam logic [2:0] BLOOM_SOFT   = 3'd3;
	localparam logic [2:0] BLOOM_NORMAL = 3'd4;
	localparam logic [2:0] BLOOM_BROAD  = 3'd5;
	localparam logic [2:0] BLOOM_WIDE_M = 3'd6;
	localparam logic [2:0] BLOOM_WIDE   = 3'd7;

	localparam logic [2:0] CURVE_MINIMAL  = 3'd0;
	localparam logic [2:0] CURVE_MIN_PLUS = 3'd1;
	localparam logic [2:0] CURVE_MILD     = 3'd2;
	localparam logic [2:0] CURVE_MILD_P   = 3'd3;
	localparam logic [2:0] CURVE_MODERATE = 3'd4;
	localparam logic [2:0] CURVE_MOD_PLUS = 3'd5;
	localparam logic [2:0] CURVE_STRONG_M = 3'd6;
	localparam logic [2:0] CURVE_STRONG   = 3'd7;

	localparam logic [2:0] HALO_OFF  = 3'd0;
	localparam logic [2:0] HALO_025X = 3'd1;
	localparam logic [2:0] HALO_033X = 3'd2;
	localparam logic [2:0] HALO_050X = 3'd3;
	localparam logic [2:0] HALO_075X = 3'd4;
	localparam logic [2:0] HALO_100X = 3'd5;
	localparam logic [2:0] HALO_125X = 3'd6;
	localparam logic [2:0] HALO_150X = 3'd7;

	localparam logic [1:0] SPREAD_ORIGINAL = 2'd0;
	localparam logic [1:0] SPREAD_WIDE1    = 2'd1;
	localparam logic [1:0] SPREAD_WIDE2    = 2'd2;
	localparam logic [1:0] SPREAD_WIDE3    = 2'd3;

	localparam logic [1:0] PHOSPHOR_OFF    = 2'd0;
	localparam logic [1:0] PHOSPHOR_LUT_A  = 2'd1;
	localparam logic [1:0] PHOSPHOR_LUT_B  = 2'd2;
	localparam logic [1:0] PHOSPHOR_LUT_C  = 2'd3;

	localparam logic       COLORSPACE_OFF    = 1'b0;
	localparam logic       COLORSPACE_AMP709 = 1'b1;

	localparam logic [2:0] CHANNEL_RGB      = 3'd0;
	localparam logic [2:0] CHANNEL_RBG      = 3'd1;
	localparam logic [2:0] CHANNEL_GRB      = 3'd2;
	localparam logic [2:0] CHANNEL_GBR      = 3'd3;
	localparam logic [2:0] CHANNEL_BRG      = 3'd4;
	localparam logic [2:0] CHANNEL_BGR      = 3'd5;
	localparam logic [2:0] CHANNEL_BW       = 3'd6;
	localparam logic [2:0] CHANNEL_NEGATIVE = 3'd7;

	localparam logic       SLOT_MASK_OFF = 1'b0;
	localparam logic       SLOT_MASK_ON  = 1'b1;

	function automatic logic [22:0] pack_settings;
		input logic [2:0] dot_i;
		input logic [1:0] tone_i;
		input logic [2:0] bloom_width_i;
		input logic [2:0] bloom_curve_i;
		input logic [2:0] halo_i;
		input logic [1:0] halo_spread_i;
		input logic [1:0] phosphor_i;
		input logic       color_space_i;
		input logic [2:0] color_channels_i;
		input logic       slot_mask_i;
		begin
			pack_settings = {
				dot_i,
				tone_i,
				bloom_width_i,
				bloom_curve_i,
				halo_i,
				halo_spread_i,
				phosphor_i,
				color_space_i,
				color_channels_i,
				slot_mask_i
			};
		end
	endfunction

	function automatic logic [22:0] fixed_480p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH: fixed_480p = pack_settings(
					DOT_AUTO, TONE_LINEAR1, BLOOM_TIGHT, CURVE_MIN_PLUS,
					HALO_033X, SPREAD_WIDE3, PHOSPHOR_OFF,
					COLORSPACE_OFF, CHANNEL_RGB, SLOT_MASK_OFF);
				PROFILE_TYPICAL: fixed_480p = pack_settings(
					DOT_2X, TONE_LINEAR2, BLOOM_TIGHT, CURVE_MILD,
					HALO_033X, SPREAD_WIDE3, PHOSPHOR_OFF,
					COLORSPACE_AMP709, CHANNEL_RGB, SLOT_MASK_OFF);
				PROFILE_OVERDRIVEN: fixed_480p = pack_settings(
					DOT_2X, TONE_BRIGHT, BLOOM_SOFT, CURVE_MILD,
					HALO_050X, SPREAD_WIDE2, PHOSPHOR_LUT_C,
					COLORSPACE_AMP709, CHANNEL_RGB, SLOT_MASK_OFF);
				PROFILE_NEON: fixed_480p = pack_settings(
					DOT_2X, TONE_LINEAR2, BLOOM_SOFT, CURVE_MIN_PLUS,
					HALO_075X, SPREAD_WIDE1, PHOSPHOR_LUT_B,
					COLORSPACE_OFF, CHANNEL_RGB, SLOT_MASK_OFF);
				PROFILE_STRANGER: fixed_480p = pack_settings(
					DOT_2X, TONE_LINEAR2, BLOOM_SOFT, CURVE_MIN_PLUS,
					HALO_075X, SPREAD_WIDE1, PHOSPHOR_LUT_B,
					COLORSPACE_OFF, CHANNEL_RBG, SLOT_MASK_OFF);
				default: fixed_480p = pack_settings(
					DOT_AUTO, TONE_LINEAR1, BLOOM_OFF, CURVE_MINIMAL,
					HALO_OFF, SPREAD_ORIGINAL, PHOSPHOR_OFF,
					COLORSPACE_OFF, CHANNEL_RBG, SLOT_MASK_OFF);
			endcase
		end
	endfunction

	function automatic logic [22:0] fixed_720p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH: fixed_720p = pack_settings(
					DOT_AUTO, TONE_LINEAR2, BLOOM_TIGHT, CURVE_MILD,
					HALO_075X, SPREAD_WIDE3, PHOSPHOR_OFF,
					COLORSPACE_OFF, CHANNEL_RGB, SLOT_MASK_OFF);
				PROFILE_TYPICAL: fixed_720p = pack_settings(
					DOT_AUTO, TONE_LINEAR1, BLOOM_THIN, CURVE_MOD_PLUS,
					HALO_075X, SPREAD_WIDE3, PHOSPHOR_OFF,
					COLORSPACE_AMP709, CHANNEL_RGB, SLOT_MASK_ON);
				PROFILE_OVERDRIVEN: fixed_720p = pack_settings(
					DOT_AUTO, TONE_BRIGHT, BLOOM_TIGHT, CURVE_MILD_P,
					HALO_100X, SPREAD_WIDE3, PHOSPHOR_LUT_C,
					COLORSPACE_AMP709, CHANNEL_RGB, SLOT_MASK_ON);
				PROFILE_NEON: fixed_720p = pack_settings(
					DOT_25X, TONE_OFF, BLOOM_SOFT, CURVE_MOD_PLUS,
					HALO_150X, SPREAD_WIDE2, PHOSPHOR_LUT_A,
					COLORSPACE_OFF, CHANNEL_RGB, SLOT_MASK_ON);
				PROFILE_STRANGER: fixed_720p = pack_settings(
					DOT_25X, TONE_OFF, BLOOM_SOFT, CURVE_MOD_PLUS,
					HALO_150X, SPREAD_WIDE2, PHOSPHOR_LUT_A,
					COLORSPACE_OFF, CHANNEL_RBG, SLOT_MASK_ON);
				default: fixed_720p = fixed_480p(profile_i);
			endcase
		end
	endfunction

	function automatic logic [22:0] fixed_1080p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH: fixed_1080p = pack_settings(
					DOT_AUTO, TONE_LINEAR2, BLOOM_TIGHT, CURVE_STRONG,
					HALO_050X, SPREAD_WIDE3, PHOSPHOR_OFF,
					COLORSPACE_OFF, CHANNEL_RGB, SLOT_MASK_OFF);
				PROFILE_TYPICAL: fixed_1080p = pack_settings(
					DOT_AUTO, TONE_LINEAR2, BLOOM_SOFT, CURVE_MILD,
					HALO_075X, SPREAD_WIDE2, PHOSPHOR_OFF,
					COLORSPACE_AMP709, CHANNEL_RGB, SLOT_MASK_ON);
				PROFILE_OVERDRIVEN: fixed_1080p = pack_settings(
					DOT_AUTO, TONE_BRIGHT, BLOOM_BROAD, CURVE_MILD,
					HALO_100X, SPREAD_WIDE2, PHOSPHOR_LUT_C,
					COLORSPACE_AMP709, CHANNEL_RGB, SLOT_MASK_ON);
				PROFILE_NEON: fixed_1080p = pack_settings(
					DOT_AUTO, TONE_LINEAR1, BLOOM_BROAD, CURVE_MILD,
					HALO_125X, SPREAD_WIDE2, PHOSPHOR_LUT_A,
					COLORSPACE_OFF, CHANNEL_RGB, SLOT_MASK_ON);
				PROFILE_STRANGER: fixed_1080p = pack_settings(
					DOT_AUTO, TONE_LINEAR1, BLOOM_BROAD, CURVE_MILD,
					HALO_125X, SPREAD_WIDE2, PHOSPHOR_LUT_A,
					COLORSPACE_OFF, CHANNEL_RBG, SLOT_MASK_ON);
				default: fixed_1080p = fixed_480p(profile_i);
			endcase
		end
	endfunction

	logic [22:0] selected_settings;

	always_comb begin
		unique case (profile)
			PROFILE_OFF: selected_settings = pack_settings(
				off_dot_mode, off_tonemapping, BLOOM_OFF, CURVE_MINIMAL,
				HALO_OFF, SPREAD_ORIGINAL, off_phosphor_mode,
				COLORSPACE_OFF, CHANNEL_RGB, SLOT_MASK_OFF);
			PROFILE_CUSTOM1: selected_settings = custom1_settings;
			PROFILE_CUSTOM2: selected_settings = custom2_settings;
			default: begin
				if (fb_height >= 12'd1000)
					selected_settings = fixed_1080p(profile);
				else if (fb_height >= 12'd700)
					selected_settings = fixed_720p(profile);
				else
					selected_settings = fixed_480p(profile);
			end
		endcase

		dot_mode       = selected_settings[22:20];
		tonemapping    = selected_settings[19:18];
		bloom_width    = selected_settings[17:15];
		bloom_curve    = selected_settings[14:12];
		halo_filter    = selected_settings[11:9];
		halo_spread    = selected_settings[8:7];
		phosphor_mode  = selected_settings[6:5];
		color_space    = selected_settings[4];
		color_channels = selected_settings[3:1];
		slot_mask      = selected_settings[0];
		full_bypass    = (profile == PROFILE_OFF);
	end

endmodule
