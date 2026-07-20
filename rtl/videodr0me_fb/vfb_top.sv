// ============================================================================
// Tile-based sparse vector framebuffer and CRT effect pipeline.
// written 2026 by Videodr0me
// ============================================================================

module vfb_top (
	input         clk_sys,
	input         clk_12,
	input         reset,
	input         video_timing_reset, // Resyncs readout only; does not clear framebuffer state.

	// Vector inputs (from AVG)
	input  [10:0] X_VECTOR,
	input  [10:0] Y_VECTOR,
	input  [7:0]  Z_VECTOR,
	input  [3:0]  COLOR,
	input         IS_DOT,
	input         BEAM_ON,

	// DDRAM Framebuffer Interface
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	// SDRAM used by the compressed halo-alignment delay
	input  [15:0] SDRAM_DQ_IN,
	output [15:0] SDRAM_DQ_OUT,
	output        SDRAM_DQ_OE,
	output        SDRAM_CKE,
	output        SDRAM_nCS,
	output        SDRAM_nRAS,
	output        SDRAM_nCAS,
	output        SDRAM_nWE,
	output  [1:0] SDRAM_DQM,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,

	// Raster dimensions
	input [11:0]  RENDER_WIDTH,
	input [11:0]  RENDER_HEIGHT,

	// VGA Readout Interface
	output logic [7:0]  VGA_R,
	output logic [7:0]  VGA_G,
	output logic [7:0]  VGA_B,
	output logic        VGA_HS,
	output logic        VGA_VS,
	output logic        VGA_HBLANK,
	output logic        VGA_VBLANK,

	input  [10:0] h_cnt,
	input  [10:0] v_cnt,
	input         ce_pix,
	input         hsync,
	input         vsync,
	input         hblank,
	input         vblank,

	// Custom and frame sync signals
	input  [7:0]  FLASH_PARAM,
	input         OSD_120HZ,
	input         FRAME_DONE,
	input   [1:0] BUFFER_MODE,
	input   [2:0] DOT_MODE,
	output        FIFO_FULL_LED,

	input  [2:0]  osd_bloom_width,
	input  [2:0]  osd_bloom_curve,
	input  [2:0]  osd_halo_filter,
	input  [1:0]  osd_phosphor_mode,    // 0=Off, 1=LUT A, 2=LUT B, 3=LUT C
	input  [1:0]  osd_halo_spread,
	input         osd_color_space,
	input  [2:0]  osd_color_channels,
	input         osd_slot_mask,
	input         osd_slot_mask_rows,
	input         osd_full_bypass,

	output wire   arbiter_reset_busy
);

	localparam TILE_SIZE = 8;   // 8x8 tiles
	localparam CACHE_COUNT = 4; // Four cache slots in this integration.

	// Rasterizer to Cache Manager Handshake
	logic        pixel_valid;
	logic        pixel_ready;
	logic [15:0] pixel_tile_id;
	logic [5:0]  pixel_offset;
	logic [15:0] pixel_data;


	// Readout to DDRAM arbiter handshake
	wire        readout_ready;
	wire        readout_grant;
	wire [15:0] readout_tile_id;
	wire [63:0] readout_data;
	wire        readout_data_valid;
	wire        flush_done_arbiter;

	// EOF metadata path
	wire        eof_token;
	wire        eof_token_popped;
	wire [15:0] eof_frame_tick_clks_popped;

	// VBL promotion request to the buffer controller
	wire        vbl_swap_req;

	wire        fifo_empty;
	wire  [1:0] buf_display;
	wire  [1:0] buf_draw;
	wire        arbiter_idle;

	// Framebuffer / DDRAM client reset
	assign DDRAM_CLK = clk_sys;

	// Extended DDR-client reset: keep framebuffer DDR clients in reset until
	// the arbiter finishes draining any mid-flight DDR burst after a raw reset.
	wire fb_client_reset = reset | arbiter_reset_busy;

	logic filter_reset_q = 1'b1;
	always_ff @(posedge clk_sys)
		filter_reset_q <= reset | video_timing_reset;

	// Frame timing is measured directly in source clocks. Each EOF token carries
	// the draw-phase duration used by its frame, so no game-rate table is needed.
	wire [3:0]  draw_idx;
	wire [15:0] active_frame_tick_clks;
	wire [3:0]  readout_draw_idx;
	wire [63:0] readout_age_map;

	vfb_phosphor_timing phosphor_timing_inst (
		.clk_source(clk_12),
		.clk_sys(clk_sys),
		.reset_source(reset),
		.reset_sys(fb_client_reset),
		.frame_done(FRAME_DONE),

		.eof_token_popped(eof_token_popped),
		.eof_frame_tick_clks_popped(eof_frame_tick_clks_popped),
		.buf_draw(buf_draw),
		.buf_display(buf_display),
		.vbl_swap_req(vbl_swap_req),

		.draw_idx(draw_idx),
		.active_frame_tick_clks(active_frame_tick_clks),
		.readout_draw_idx(readout_draw_idx),
		.readout_age_map(readout_age_map)
	);

	vfb_rasterizer #(
		.TILE_SIZE(TILE_SIZE)
	) rasterizer_inst (
		.clk_sys(clk_sys),
		.clk_12(clk_12),
		.reset(fb_client_reset),

		// Vector Input Interface
		.X_VECTOR(X_VECTOR),
		.Y_VECTOR(Y_VECTOR),
		.Z_VECTOR(Z_VECTOR),
		.COLOR(COLOR),
		.IS_DOT(IS_DOT),
		.BEAM_ON(BEAM_ON),
		.FRAME_DONE(FRAME_DONE),
		.DOT_MODE(DOT_MODE),
		.FB_WIDTH(RENDER_WIDTH),
		.FB_HEIGHT(RENDER_HEIGHT),

		// Outputs to Cache Manager
		.pixel_valid(pixel_valid),
		.pixel_ready(pixel_ready),
		.pixel_tile_id(pixel_tile_id),
		.pixel_offset(pixel_offset),
		.pixel_data(pixel_data),
		.draw_idx(draw_idx),
		.frame_tick_clks(active_frame_tick_clks),


		.eof_token(eof_token),
		.fifo_full_led(FIFO_FULL_LED),
		.fifo_empty(fifo_empty)
	);

	// Inter-module signals
	wire        fill_ready, fill_grant;
	wire [28:0] fill_addr;
	wire [7:0]  fill_burstcnt;
	wire [63:0] fill_data;
	wire        fill_data_valid;

	wire        flush_ready, flush_grant, flush_done, flush_advance;
	wire [28:0] flush_addr;
	wire [7:0]  flush_burstcnt;
	wire [63:0] flush_din;
	wire [7:0]  flush_be;

	wire [15:0] display_tile_query;
	wire        display_tile_dirty;

	wire flush_req;
	wire clear_req;
	wire [1:0] clear_buf_idx;
	wire clear_done;
	wire has_draw_buf;
	wire display_valid;

	wire [28:0] buf_base [4];
	assign buf_base[0] = 29'h06000000;
	assign buf_base[1] = 29'h06110000;
	assign buf_base[2] = 29'h06220000;
	assign buf_base[3] = 29'h06330000;
	wire [28:0] display_buf_base = buf_base[buf_display];

	vfb_buffer_controller buffer_controller_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),

		.BUFFER_MODE(BUFFER_MODE),

		.eof_token_popped(eof_token_popped),
		.vbl_swap_req(vbl_swap_req),

		.flush_req(flush_req),
		.flush_done(flush_done),

		.clear_req(clear_req),
		.clear_buf_idx(clear_buf_idx),
		.clear_done(clear_done),

		.buf_draw(buf_draw),
		.buf_display_out(buf_display),
		.display_valid(display_valid),

		.has_draw_buf(has_draw_buf)
	);

	vfb_tile_cache_manager #(
		.TILE_SIZE(TILE_SIZE),
		.CACHE_COUNT(CACHE_COUNT)
	) cache_manager_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),

		.FB_WIDTH(RENDER_WIDTH),
		.FB_HEIGHT(RENDER_HEIGHT),

		// Rasterizer Interface
		.pixel_valid(pixel_valid),
		.pixel_ready(pixel_ready),
		.pixel_tile_id(pixel_tile_id),
		.pixel_offset(pixel_offset),
		.pixel_data(pixel_data),

		.eof_token(eof_token),
		.fifo_empty(fifo_empty),

		// Buffer Controller Interface
		.eof_token_popped(eof_token_popped),
		.eof_frame_tick_clks_popped(eof_frame_tick_clks_popped),
		.flush_req(flush_req),
		.flush_done(flush_done),
		.clear_req(clear_req),
		.clear_buf_idx(clear_buf_idx),
		.clear_done(clear_done),
		.buf_draw(buf_draw),
		.buf_display(buf_display),
		.display_valid(display_valid),
		.has_draw_buf(has_draw_buf),

		// Arbiter Interface
		.fill_ready(fill_ready),
		.fill_grant(fill_grant),
		.fill_addr(fill_addr),
		.fill_burstcnt(fill_burstcnt),
		.fill_data(fill_data),
		.fill_data_valid(fill_data_valid),

		.flush_ready(flush_ready),
		.flush_grant(flush_grant),
		.flush_done_in(flush_done_arbiter),
		.flush_addr(flush_addr),
		.flush_burstcnt(flush_burstcnt),
		.flush_din(flush_din),
		.flush_be(flush_be),
		.flush_advance(flush_advance),

		.display_tile_query(display_tile_query),
		.display_tile_dirty(display_tile_dirty),
		.arbiter_idle(arbiter_idle)
	);

	wire [28:0] readout_addr = display_buf_base + ({13'd0, readout_tile_id} << 4);
	wire [8:0] readout_burstcnt;
	wire [23:0] arbiter_debug_flashparam;

	vfb_ddr_arbiter ddr_arbiter_inst (
		.clk_sys(clk_sys),
		.rst_sys(reset),

		// DDRAM Avalon-MM Interface
		.DDRAM_BUSY(DDRAM_BUSY),
		.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
		.DDRAM_ADDR(DDRAM_ADDR),
		.DDRAM_RD(DDRAM_RD),
		.DDRAM_WE(DDRAM_WE),
		.DDRAM_DIN(DDRAM_DIN),
		.DDRAM_BE(DDRAM_BE),
		.DDRAM_DOUT(DDRAM_DOUT),
		.DDRAM_DOUT_READY(DDRAM_DOUT_READY),

		// Readout
		.readout_ready(readout_ready),
		.readout_grant(readout_grant),
		.readout_addr(readout_addr),
		.readout_burstcnt(readout_burstcnt),
		.readout_data(readout_data),
		.readout_data_valid(readout_data_valid),

		// Fill
		.fill_ready(fill_ready),
		.fill_grant(fill_grant),
		.fill_addr(fill_addr),
		.fill_burstcnt(fill_burstcnt),
		.fill_data(fill_data),
		.fill_data_valid(fill_data_valid),

		// Flush
		.flush_ready(flush_ready),
		.flush_grant(flush_grant),
		.flush_done(flush_done_arbiter),
		.flush_addr(flush_addr),
		.flush_burstcnt(flush_burstcnt),
		.flush_din(flush_din),
		.flush_be(flush_be),
		.flush_advance(flush_advance),

		.debug_flashparam(arbiter_debug_flashparam),
		.arbiter_idle(arbiter_idle),
		.reset_busy(arbiter_reset_busy)
	);

	wire [7:0] raw_vga_r;
	wire [7:0] raw_vga_g;
	wire [7:0] raw_vga_b;
	wire       raw_vga_hs;
	wire       raw_vga_vs;
	wire       raw_vga_hblank;
	wire       raw_vga_vblank;

	// Synchronize OSD controls before decoding filter values.
	wire [19:0] osd_control_in = {
		osd_full_bypass,
		osd_slot_mask_rows,
		osd_slot_mask,
		osd_color_channels,
		osd_color_space,
		osd_halo_spread,
		osd_phosphor_mode,
		osd_halo_filter,
		osd_bloom_curve,
		osd_bloom_width
	};

	logic [19:0] osd_control_meta;
	logic [19:0] osd_control_sync;
	logic [19:0] osd_control_sync_d;
	logic [19:0] osd_control_stable;
	logic [2:0]  osd_bloom_width_vid;
	logic [1:0]  osd_phosphor_mode_vid;
	logic [1:0]  osd_halo_spread_vid;
	logic        osd_color_space_vid;
	logic [2:0]  osd_color_channels_vid;
	logic        osd_slot_mask_vid;
	logic        osd_slot_mask_rows_vid;
	logic        osd_full_bypass_vid;
	logic [9:0]  bloom_curve_gain;
	logic [7:0]  halo_filter;

	function automatic [9:0] decode_bloom_curve_gain(
		input logic [2:0] sel
	);
		begin
			decode_bloom_curve_gain =
				(sel == 3'd0) ? 10'd64  : // Minimal
				(sel == 3'd1) ? 10'd96  : // Min+
				(sel == 3'd2) ? 10'd128 : // Mild
				(sel == 3'd3) ? 10'd192 : // Mild+
				(sel == 3'd4) ? 10'd256 : // Moderate
				(sel == 3'd5) ? 10'd320 : // Mod+
				(sel == 3'd6) ? 10'd384 : // Strong-
				                  10'd512 ; // Strong
		end
	endfunction

	function automatic [7:0] decode_halo_filter(
		input logic [2:0] sel
	);
		begin
			decode_halo_filter =
				(sel == 3'd0) ? 8'd0  : // Off
				(sel == 3'd1) ? 8'd8  : // 0.25x
				(sel == 3'd2) ? 8'd11 : // 0.33x
				(sel == 3'd3) ? 8'd16 : // 0.5x
				(sel == 3'd4) ? 8'd24 : // 0.75x
				(sel == 3'd5) ? 8'd32 : // 1.0x
				(sel == 3'd6) ? 8'd40 : // 1.25x
				                  8'd48 ; // 1.5x
		end
	endfunction

	always_ff @(posedge clk_sys) begin
		if (fb_client_reset | video_timing_reset) begin
			osd_control_meta <= osd_control_in;
			osd_control_sync <= osd_control_in;
			osd_control_sync_d <= osd_control_in;
			osd_control_stable <= osd_control_in;
			osd_bloom_width_vid <= osd_bloom_width;
			osd_phosphor_mode_vid <= osd_phosphor_mode;
			osd_halo_spread_vid <= osd_halo_spread;
			osd_color_space_vid <= osd_color_space;
			osd_color_channels_vid <= osd_color_channels;
			osd_slot_mask_vid <= osd_slot_mask;
			osd_slot_mask_rows_vid <= osd_slot_mask_rows;
			osd_full_bypass_vid <= osd_full_bypass;
			bloom_curve_gain <=
				decode_bloom_curve_gain(osd_bloom_curve);
			halo_filter <= decode_halo_filter(osd_halo_filter);
		end else begin
			osd_control_meta <= osd_control_in;
			osd_control_sync <= osd_control_meta;
			osd_control_sync_d <= osd_control_sync;
			if (osd_control_sync == osd_control_sync_d)
				osd_control_stable <= osd_control_sync;

			osd_bloom_width_vid <= osd_control_stable[2:0];
			bloom_curve_gain <=
				decode_bloom_curve_gain(osd_control_stable[5:3]);
			halo_filter <= decode_halo_filter(
				osd_control_stable[8:6]);
			osd_phosphor_mode_vid <= osd_control_stable[10:9];
			osd_halo_spread_vid <= osd_control_stable[12:11];
			osd_color_space_vid <= osd_control_stable[13];
			osd_color_channels_vid <= osd_control_stable[16:14];
			osd_slot_mask_vid <= osd_control_stable[17];
			osd_slot_mask_rows_vid <= osd_control_stable[18];
			osd_full_bypass_vid <= osd_control_stable[19];
		end
	end

	vfb_readout #(
		.TILE_SIZE(TILE_SIZE)
	) readout_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset | video_timing_reset),

		// DDRAM arbiter interface
		.readout_ready(readout_ready),
		.readout_grant(readout_grant),
		.readout_tile_id(readout_tile_id),
		.readout_burstcnt(readout_burstcnt),
		.readout_data(readout_data),
		.readout_data_valid(readout_data_valid),

		.vbl_swap_req(vbl_swap_req),

		// Raw readout packet
		.VGA_R(raw_vga_r),
		.VGA_G(raw_vga_g),
		.VGA_B(raw_vga_b),
		.VGA_HS(raw_vga_hs),
		.VGA_VS(raw_vga_vs),
		.VGA_HBLANK(raw_vga_hblank),
		.VGA_VBLANK(raw_vga_vblank),

		.display_tile_query(display_tile_query),
		.display_tile_dirty(display_tile_dirty),

		.h_cnt(h_cnt),
		.v_cnt(v_cnt),
		.ce_pix(ce_pix),
		.hsync(hsync),
		.vsync(vsync),
		.hblank(hblank),
		.vblank(vblank),

		.RENDER_WIDTH(RENDER_WIDTH),
		.RENDER_HEIGHT(RENDER_HEIGHT),
		.FLASH_PARAM({FLASH_PARAM, FLASH_PARAM, FLASH_PARAM}),
		.draw_idx(readout_draw_idx),
		.phosphor_age_map(readout_age_map),
		.osd_phosphor_mode(osd_phosphor_mode_vid)
	);

	wire sdram_delay_overflow;
	wire sdram_delay_underflow;
	wire sdram_delay_init_done;
	wire [7:0] filtered_vga_r;
	wire [7:0] filtered_vga_g;
	wire [7:0] filtered_vga_b;
	wire       filtered_vga_hs;
	wire       filtered_vga_vs;
	wire       filtered_vga_hblank;
	wire       filtered_vga_vblank;

	vfb_halo_pipeline filter_inst (
		.clk_sys(clk_sys),
		.ce_pix(ce_pix),
		.reset(filter_reset_q),

		.osd_bloom_width(osd_bloom_width_vid),
		.bloom_curve_gain(bloom_curve_gain),
		.halo_filter(halo_filter),
		.halo_spread_mode(osd_halo_spread_vid),
		.active_height(RENDER_HEIGHT),
		.color_space_amp709(osd_color_space_vid),
		.color_channels(osd_color_channels_vid),
		.slot_mask_enable(osd_slot_mask_vid),
		.slot_mask_rows(osd_slot_mask_rows_vid),

		.VGA_R_IN(raw_vga_r),
		.VGA_G_IN(raw_vga_g),
		.VGA_B_IN(raw_vga_b),
		.VGA_HS_IN(raw_vga_hs),
		.VGA_VS_IN(raw_vga_vs),
		.VGA_HBLANK_IN(raw_vga_hblank),
		.VGA_VBLANK_IN(raw_vga_vblank),

		.VGA_R_OUT(filtered_vga_r),
		.VGA_G_OUT(filtered_vga_g),
		.VGA_B_OUT(filtered_vga_b),
		.VGA_HS_OUT(filtered_vga_hs),
		.VGA_VS_OUT(filtered_vga_vs),
		.VGA_HBLANK_OUT(filtered_vga_hblank),
		.VGA_VBLANK_OUT(filtered_vga_vblank),

		.sdram_data_in(SDRAM_DQ_IN),
		.sdram_data_out(SDRAM_DQ_OUT),
		.sdram_data_oe(SDRAM_DQ_OE),
		.sdram_cke(SDRAM_CKE),
		.sdram_cs(SDRAM_nCS),
		.sdram_ras(SDRAM_nRAS),
		.sdram_cas(SDRAM_nCAS),
		.sdram_we(SDRAM_nWE),
		.sdram_dqm(SDRAM_DQM),
		.sdram_addr(SDRAM_A),
		.sdram_ba(SDRAM_BA),
		.sdram_overflow(sdram_delay_overflow),
		.sdram_underflow(sdram_delay_underflow),
		.sdram_init_done(sdram_delay_init_done)
	);

	// Full bypass passes the readout packet directly to the MiSTer
	// framework.
	always_ff @(posedge clk_sys) begin
		if (fb_client_reset | video_timing_reset) begin
			VGA_R <= 8'd0;
			VGA_G <= 8'd0;
			VGA_B <= 8'd0;
			VGA_HS <= 1'b1;
			VGA_VS <= 1'b1;
			VGA_HBLANK <= 1'b1;
			VGA_VBLANK <= 1'b1;
		end else if (ce_pix) begin
			if (osd_full_bypass_vid) begin
				VGA_R <= raw_vga_r;
				VGA_G <= raw_vga_g;
				VGA_B <= raw_vga_b;
				VGA_HS <= raw_vga_hs;
				VGA_VS <= raw_vga_vs;
				VGA_HBLANK <= raw_vga_hblank;
				VGA_VBLANK <= raw_vga_vblank;
			end else begin
				VGA_R <= filtered_vga_r;
				VGA_G <= filtered_vga_g;
				VGA_B <= filtered_vga_b;
				VGA_HS <= filtered_vga_hs;
				VGA_VS <= filtered_vga_vs;
				VGA_HBLANK <= filtered_vga_hblank;
				VGA_VBLANK <= filtered_vga_vblank;
			end
		end
	end

endmodule
