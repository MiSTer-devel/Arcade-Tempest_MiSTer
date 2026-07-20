//============================================================================
//  Tempest for MiSTer
//
//  Written 2026 by Videodr0me
//
//  Original arcade hardware by Atari, 1981.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

	`include "build_id.v"

	logic [127:0] status;
	logic [31:0] joystick_0;
	logic [31:0] joystick_1;
	logic [31:0] joystick;
	logic [15:0] analog_0;
	logic [15:0] analog_1;
	logic  [8:0] spinner_0;
	logic  [8:0] spinner_1;
	logic [24:0] ps2_mouse;
	logic  [1:0] buttons;
	logic        direct_video;
	wire  [21:0] gamma_bus;

	logic        ioctl_download;
	logic        ioctl_upload;
	logic        ioctl_upload_req;
	logic        ioctl_wr;
	logic [26:0] ioctl_addr;
	logic  [7:0] ioctl_dout;
	logic  [7:0] ioctl_din;
	logic [15:0] ioctl_index;

	logic clk_50;
	logic clk_12;
	logic clk_125;
	logic pll_locked;

	logic [2:0] profile;
	logic       profile_off;
	logic       profile_touch;
	logic       profile_typical;
	logic       profile_overdriven;
	logic       profile_neon;
	logic       profile_stranger;
	logic       profile_custom_1;
	logic       profile_custom_2;
	logic       profile_flashing;
	logic [2:0] custom_bloom_width;
	logic [2:0] custom_halo;
	logic       custom_active;
	logic       custom_bloom_off;
	logic       custom_halo_off;
	logic [1:0] off_tone_mapping;
	logic [1:0] custom_1_tone_mapping;
	logic [1:0] custom_2_tone_mapping;
	logic [22:0] custom_1_settings;
	logic [22:0] custom_2_settings;
	logic        video_is_720p;

	assign profile = status[68:66] + 3'd2;
	assign profile_off        = (profile == 3'd0);
	assign profile_touch      = (profile == 3'd1);
	assign profile_typical    = (profile == 3'd2);
	assign profile_overdriven = (profile == 3'd3);
	assign profile_neon       = (profile == 3'd4);
	assign profile_stranger   = (profile == 3'd5);
	assign profile_custom_1   = (profile == 3'd6);
	assign profile_custom_2   = (profile == 3'd7);
	assign profile_flashing   = profile_neon || profile_stranger;

	assign custom_bloom_width = profile_custom_2 ? status[99:97] : status[76:74];
	assign custom_halo = profile_custom_2 ? status[105:103] : status[82:80];
	assign custom_active = profile_custom_1 || profile_custom_2;
	assign custom_bloom_off = custom_active && (custom_bloom_width == 3'd0);
	assign custom_halo_off = custom_active && (custom_halo == 3'd0);

	assign off_tone_mapping = status[38:37] + 2'd1;
	assign custom_1_tone_mapping = status[73:72] + 2'd1;
	assign custom_2_tone_mapping = status[96:95] + 2'd1;

	assign custom_1_settings = {
		status[71:69], custom_1_tone_mapping,
		status[76:74], status[79:77], status[82:80], status[84:83],
		status[86:85], status[87], status[90:88], status[91]
	};

	assign custom_2_settings = {
		status[94:92], custom_2_tone_mapping,
		status[99:97], status[102:100], status[105:103], status[107:106],
		status[109:108], status[110], status[113:111], status[114]
	};

	localparam CONF_STR = {
		"Tempest;;",
		"-;",
		"P3,Video Options;",
		"P3-;",
		"P3O[15:14],Aspect ratio,Optimized,Stretched,Pixel Perfect;",
		"D3P3O[25],120Hz (720p only),Off,On;",
		"h0P3O[115],Direct Video Scan Rate,15 kHz,31 kHz;",
		"P3O[40:39],Buffer Mode,EOF + VBL,VBL,EOF;",
		"P3-;",
		"P3O[68:66],Profile,80s Cruise Control,80s Overdrive,Neon Fever Dream,Stranger Tempest,Custom 1,Custom 2,Off,A Touch of CRT;",
		"h7P3O[30:28],Dot Scale,Auto,Pixel,2x,2.5x;",
		"h7P3O[38:37],Tone Mapping,Linear 2,Bright,Off,Linear 1;",
		"h7P3O[56:55],Phosphor Decay,Off,LUT A,LUT B,LUT C;",
		"h7P3-;",
		"h7P3-, For advanced settings;",
		"h7P3-, select Custom Profiles 1/2;",
		"h8P3-;",
		"h8P3-,This profile adds a subtle;",
		"h8P3-,CRT halo and bloom effect,;",
		"h8P3-,to modern AA vector drawing;",
		"h9P3-;",
		"h9P3-,Step away from the modern.;",
		"h9P3-,A faint vertical slot mask,;",
		"h9P3-,richer halos and more bloom;",
		"hAP3-;",
		"hAP3-,A remote arcade in the 80s:;",
		"hAP3-,CRTs overdriven and abused;",
		"hAP3-,pulsate with vector glow;",
		"hBP3-;",
		"hBP3-,     Epilepsy warning:;",
		"hBP3-,    excessive flashing;",
		"hBP3-,       bright lights;",
		"hBP3-;",
		"hBP3-,   Use Custom Profiles 1/2;",
		"hBP3-, to create your own effects;",
		"hDP3O[71:69],> Dot Scale,Auto,Pixel,2x,2.5x;",
		"hDP3O[73:72],> Tone Mapping,Linear 2,Bright,Off,Linear 1;",
		"hDP3O[76:74],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
		"hDD5P3O[79:77],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hDP3O[82:80],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
		"hDD6P3O[84:83],> Halo Spread,Original,Wide 1,Wide 2,Wide 3;",
		"hDP3O[86:85],> Phosphor Decay,Off,LUT A,LUT B,LUT C;",
		"hDP3O[87],> Color Space,Off,Amp709;",
		"hDP3O[90:88],> Color Channels,RGB,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
		"hDP3O[91],> Slot Mask,Off,On;",
		"hEP3O[94:92],> Dot Scale,Auto,Pixel,2x,2.5x;",
		"hEP3O[96:95],> Tone Mapping,Linear 2,Bright,Off,Linear 1;",
		"hEP3O[99:97],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
		"hED5P3O[102:100],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hEP3O[105:103],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
		"hED6P3O[107:106],> Halo Spread,Original,Wide 1,Wide 2,Wide 3;",
		"hEP3O[109:108],> Phosphor Decay,Off,LUT A,LUT B,LUT C;",
		"hEP3O[110],> Color Space,Off,Amp709;",
		"hEP3O[113:111],> Color Channels,RGB,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
		"hEP3O[114],> Slot Mask,Off,On;",
		"P6,Video Geometry;",
		"P6-;",
		"P6O[7:5],Orientation,Normal,Rotate 90 CW,Rotate 180,Rotate 90 CCW,Mirror Horizontal,Mirror Vertical,Mirror H + 90 CW,Mirror H + 90 CCW;",
		"P6O[3],Zoom,Near,Far;",
		"-;",
		"P2,Cabinet Audio Hardware;",
		"P2-;",
		"P2O[1],POKEY RC Filter,On,Off;",
		"-;",
		"P4,Input Controls;",
		"P4-,All Inputs:;",
		"P4O[2],Direction,Normal,Reversed;",
		"P4O[10:8],Sensitivity,1.0x,0.75x,0.5x,0.25x,0.125x,1.25x,1.5x,2.0x;",
		"P4-;",
		"P4O[11],Analog Stick,Normal,Circular;",
		"P4-;",
		"P4-,Circular Mode [Experimental]:;",
		"P4-,Instead of using left/right;",
		"P4-,circle analog stick along;",
		"P4-,outer edge to move ship.;",
		"-;",
		"DIP;",
		"-;",
		"P5,Core Info;",
		"P5-;",
		"P5-,Atari Tempest arcade core;",
		"P5-,     by Videodr0me 2026;",
		"P5-;",
		"P5-,If you enjoy reliving the;",
		"P5-,golden age of arcade games,;",
		"P5-,please support my work and;",
		"P5-,future updates:;",
		"P5-;",
		"P5-,buymeacoffee.com/videodr0me;",
		"-;",
		"OR,Autosave NVRAM,Off,On;",
		"T4,Save NVRAM;",
		"-;",
		"P1,Pause Options;",
		"P1O[116],Pause when OSD is open,Off,On;",
		"P1O[117],Dim video after 10s,On,Off;",
		"-;",
		"R[0],Reset;",
		"J1,Fire,Superzapper,Start 1,Start 2,Coin,Pause,Coin Right;",
		"jn,A,B,Start,Select,R,L,X,Y;",
		"V,v0.1.", `BUILD_DATE
	};

	hps_io #(.CONF_STR(CONF_STR)) hps_io_inst (
		.clk_sys(clk_12),
		.HPS_BUS(HPS_BUS),
		.joystick_0(joystick_0),
		.joystick_1(joystick_1),
		.joystick_l_analog_0(analog_0),
		.joystick_l_analog_1(analog_1),
		.spinner_0(spinner_0),
		.spinner_1(spinner_1),
		.ps2_mouse(ps2_mouse),
		.buttons(buttons),
		.forced_scandoubler(),
		.direct_video(direct_video),
		.gamma_bus(gamma_bus),
		.status(status),
		.status_menumask({
			1'b0, profile_custom_2, profile_custom_1, 1'b0,
			profile_flashing, profile_overdriven, profile_typical, profile_touch,
			profile_off, custom_halo_off, custom_bloom_off, 1'b0,
			!video_is_720p, 1'b0, 1'b0, direct_video
		}),
		.ioctl_download(ioctl_download),
		.ioctl_upload(ioctl_upload),
		.ioctl_upload_req(ioctl_upload_req),
		.ioctl_upload_index(8'd4),
		.ioctl_wr(ioctl_wr),
		.ioctl_rd(),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout),
		.ioctl_din(ioctl_din),
		.ioctl_index(ioctl_index)
	);

	pll pll (
		.refclk(CLK_50M),
		.rst(1'b0),
		.outclk_0(clk_50),
		.outclk_1(clk_12),
		.outclk_2(),
		.outclk_3(clk_125),
		.locked(pll_locked)
	);

	logic [7:0] dip_switch [0:7];
	initial begin
		dip_switch[0] = 8'h00;
		dip_switch[1] = 8'h00;
		dip_switch[2] = 8'h17;
		dip_switch[3] = 8'hff;
		dip_switch[4] = 8'hff;
		dip_switch[5] = 8'hff;
		dip_switch[6] = 8'hff;
		dip_switch[7] = 8'hff;
	end

	always @(posedge clk_12) begin
		if (ioctl_wr && (ioctl_index == 16'd254) && !ioctl_addr[26:3])
			dip_switch[ioctl_addr[2:0]] <= ioctl_dout;
	end

	assign joystick = joystick_0 | joystick_1;

	logic [3:0] spinner_position_1;
	logic [3:0] spinner_position_2;
	logic       spinner_time_tick;
	logic [1:0] spinner_sample;
	logic machine_reset;
	logic pause_cpu;

	tempest_spinner spinner_inputs (
		.clk(clk_12),
		.reset(machine_reset),
		.time_tick(spinner_time_tick),
		.sample(spinner_sample),
		.analog_x_1($signed(analog_0[7:0])),
		.analog_y_1($signed(analog_0[15:8])),
		.analog_x_2($signed(analog_1[7:0])),
		.analog_y_2($signed(analog_1[15:8])),
		.analog_circular(status[11]),
		.left_1(joystick_0[1]),
		.right_1(joystick_0[0]),
		.left_2(joystick_1[1]),
		.right_2(joystick_1[0]),
		.spinner_1(spinner_0),
		.spinner_2(spinner_1),
		.mouse(ps2_mouse),
		.sensitivity(status[10:8]),
		.reverse(status[2]),
		.position_1(spinner_position_1),
		.position_2(spinner_position_2)
	);

	logic [23:0] paused_rgb;
	logic [7:0] raw_video_r;
	logic [7:0] raw_video_g;
	logic [7:0] raw_video_b;

	pause #(8, 8, 8, 12) pause_inst (
		.clk_sys(clk_12),
		.reset(machine_reset),
		.user_button(joystick[9]),
		.pause_request(1'b0),
		.options({~status[117], status[116]}),
		.OSD_STATUS(OSD_STATUS),
		.r(raw_video_r),
		.g(raw_video_g),
		.b(raw_video_b),
		.pause_cpu(pause_cpu),
		.rgb_out(paused_rgb)
	);

	logic rom_download;
	logic nvram_download;
	logic nvram_host_write;
	logic [7:0] nvram_data_out;
	logic nvram_modified;
	logic nvram_dirty = 1'b0;

	assign rom_download = ioctl_download && (ioctl_index == 16'd0);
	assign nvram_download = ioctl_download && (ioctl_index == 16'd4);
	assign nvram_host_write = nvram_download && ioctl_wr;
	assign machine_reset = RESET || status[0] || buttons[1] ||
	                       rom_download || nvram_download || !pll_locked;

	always_ff @(posedge clk_12) begin
		if (nvram_download || (ioctl_upload && (ioctl_index == 16'd4)))
			nvram_dirty <= 1'b0;
		if (nvram_modified)
			nvram_dirty <= 1'b1;
	end

	assign ioctl_upload_req = (status[27] && nvram_dirty) || status[4];
	assign ioctl_din = (ioctl_index == 16'd4) ? nvram_data_out : 8'h00;

	logic [7:0] machine_audio;
	logic [14:0] avg_x;
	logic [14:0] avg_y;
	logic [7:0] avg_z;
	logic [3:0] avg_color;
	logic avg_is_dot;
	logic avg_frame_done;
	logic avg_halted;

	tempest_core machine (
		.clk_12(clk_12),
		.reset(machine_reset),
		.pause(pause_cpu),
		.audio_filter_enable(~status[1]),
		.coin_right(joystick[10]),
		.coin_center(1'b0),
		.coin_left(joystick[8]),
		.slam(1'b0),
		.service(dip_switch[2][5]),
		.diagnostic_step(dip_switch[2][6]),
		.start_1(joystick[6]),
		.start_2(joystick[7]),
		.fire_1(joystick_0[4] || ps2_mouse[0]),
		.superzapper_1(joystick_0[5] || ps2_mouse[1]),
		.fire_2(joystick_1[4]),
		.superzapper_2(joystick_1[5]),
		.cocktail(dip_switch[2][4]),
		.spinner_1(spinner_position_1),
		.spinner_2(spinner_position_2),
		.auxiliary_dip(dip_switch[2][2:0]),
		.dsw_1(dip_switch[0]),
		.dsw_2(dip_switch[1]),
		.rom_write(ioctl_wr && rom_download),
		.rom_address(ioctl_addr[15:0]),
		.rom_data(ioctl_dout),
		.nvram_address(ioctl_addr[5:0]),
		.nvram_data_in(ioctl_dout),
		.nvram_write(nvram_host_write),
		.nvram_data_out(nvram_data_out),
		.nvram_modified(nvram_modified),
		.audio(machine_audio),
		.x_out(avg_x),
		.y_out(avg_y),
		.z_out(avg_z),
		.color_out(avg_color),
		.is_dot(avg_is_dot),
		.frame_done(avg_frame_done),
		.avg_halted(avg_halted),
		.start_led(),
		.spinner_time_tick(spinner_time_tick),
		.spinner_sample(spinner_sample)
	);

	logic sdram_data_oe;
	logic [15:0] sdram_data_out;
	logic [1:0] sdram_dqm;
	logic video_hblank;
	logic video_vblank;
	logic fifo_full;

	assign SDRAM_CLK = ~clk_125;
	assign SDRAM_DQ = sdram_data_oe ? sdram_data_out : 16'hzzzz;
	assign SDRAM_DQML = sdram_dqm[0];
	assign SDRAM_DQMH = sdram_dqm[1];

	tempest_video video (
		.clk_12(clk_12),
		.clk_50(clk_50),
		.clk_125(clk_125),
		.reset(machine_reset),
		.direct_video(direct_video),
		.direct_video_31khz(status[115]),
		.hdmi_height(HDMI_HEIGHT),
		.mode_120hz(status[25]),
		.aspect_ratio(status[15:14]),
		.buffer_mode(status[40:39]),
		.geometry_orientation(status[7:5]),
		.geometry_zoom_far(status[3]),
		.profile(profile),
		.off_dot_mode(status[30:28]),
		.off_tone_mapping(off_tone_mapping),
		.off_phosphor_mode(status[56:55]),
		.custom_1_settings(custom_1_settings),
		.custom_2_settings(custom_2_settings),
		.avg_x(avg_x),
		.avg_y(avg_y),
		.avg_z(avg_z),
		.avg_color(avg_color),
		.avg_is_dot(avg_is_dot),
		.avg_halted(avg_halted),
		.frame_done(avg_frame_done),
		.video_arx(VIDEO_ARX),
		.video_ary(VIDEO_ARY),
		.ce_pixel(CE_PIXEL),
		.hblank(video_hblank),
		.vblank(video_vblank),
		.video_r(raw_video_r),
		.video_g(raw_video_g),
		.video_b(raw_video_b),
		.hsync(VGA_HS),
		.vsync(VGA_VS),
		.mode_is_720p(video_is_720p),
		.fifo_full(fifo_full),
		.ddram_clk(DDRAM_CLK),
		.ddram_busy(DDRAM_BUSY),
		.ddram_burst_count(DDRAM_BURSTCNT),
		.ddram_address(DDRAM_ADDR),
		.ddram_data_out(DDRAM_DOUT),
		.ddram_data_ready(DDRAM_DOUT_READY),
		.ddram_read(DDRAM_RD),
		.ddram_data_in(DDRAM_DIN),
		.ddram_byte_enable(DDRAM_BE),
		.ddram_write(DDRAM_WE),
		.sdram_data_in(SDRAM_DQ),
		.sdram_data_out(sdram_data_out),
		.sdram_data_oe(sdram_data_oe),
		.sdram_cke(SDRAM_CKE),
		.sdram_ncs(SDRAM_nCS),
		.sdram_nras(SDRAM_nRAS),
		.sdram_ncas(SDRAM_nCAS),
		.sdram_nwe(SDRAM_nWE),
		.sdram_dqm(sdram_dqm),
		.sdram_address(SDRAM_A),
		.sdram_bank(SDRAM_BA)
	);

	assign CLK_VIDEO = clk_125;
	assign VGA_R = paused_rgb[23:16];
	assign VGA_G = paused_rgb[15:8];
	assign VGA_B = paused_rgb[7:0];
	assign VGA_DE = !(video_hblank || video_vblank);
	assign VGA_F1 = 1'b0;
	assign VGA_SL = 2'b00;
	assign VGA_SCALER = 1'b0;
	assign VGA_DISABLE = 1'b0;
	assign HDMI_FREEZE = 1'b0;
	assign HDMI_BLACKOUT = 1'b0;
	assign HDMI_BOB_DEINT = 1'b0;

	assign AUDIO_L = {machine_audio, machine_audio};
	assign AUDIO_R = AUDIO_L;
	assign AUDIO_S = 1'b0;
	assign AUDIO_MIX = 2'b00;

	assign LED_USER = fifo_full || ioctl_download;
	assign LED_POWER = 2'b00;
	assign LED_DISK = 2'b00;
	assign BUTTONS = 2'b00;

	assign ADC_BUS = 4'bzzzz;
	assign USER_OUT = 7'h7f;
	assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
	assign {SD_SCK, SD_MOSI, SD_CS} = 3'bzzz;

`ifdef MISTER_FB
	assign FB_EN = 1'b0;
	assign FB_FORMAT = 5'd0;
	assign FB_WIDTH = 12'd0;
	assign FB_HEIGHT = 12'd0;
	assign FB_BASE = 32'd0;
	assign FB_STRIDE = 14'd0;
	assign FB_FORCE_BLANK = 1'b0;
`ifdef MISTER_FB_PALETTE
	assign FB_PAL_CLK = 1'b0;
	assign FB_PAL_ADDR = 8'd0;
	assign FB_PAL_DOUT = 24'd0;
	assign FB_PAL_WR = 1'b0;
`endif
`endif

`ifdef MISTER_DUAL_SDRAM
	assign SDRAM2_CLK = 1'bz;
	assign SDRAM2_A = 13'hzzz;
	assign SDRAM2_BA = 2'bzz;
	assign SDRAM2_DQ = 16'hzzzz;
	assign {SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE} = 4'hf;
`endif

endmodule
