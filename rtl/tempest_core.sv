//============================================================================
//  Atari Tempest machine
//
//  Written 2026 by Videodr0me
//
//  Implements the digital hardware on Tempest drawing package sheets 2A, 2B,
//  3A, and 3B. The 12.096 MHz master clock drives all board-rate enables.
//============================================================================

module tempest_core
(
	input  logic        clk_12,
	input  logic        reset,
	input  logic        pause,
	input  logic        audio_filter_enable,

	input  logic        coin_right,
	input  logic        coin_center,
	input  logic        coin_left,
	input  logic        slam,
	input  logic        service,
	input  logic        diagnostic_step,
	input  logic        start_1,
	input  logic        start_2,
	input  logic        fire_1,
	input  logic        superzapper_1,
	input  logic        fire_2,
	input  logic        superzapper_2,
	input  logic        cocktail,
	input  logic  [3:0] spinner_1,
	input  logic  [3:0] spinner_2,
	input  logic  [2:0] auxiliary_dip,
	input  logic  [7:0] dsw_1,
	input  logic  [7:0] dsw_2,

	input  logic        rom_write,
	input  logic [15:0] rom_address,
	input  logic  [7:0] rom_data,

	input  logic  [5:0] nvram_address,
	input  logic  [7:0] nvram_data_in,
	input  logic        nvram_write,
	output logic  [7:0] nvram_data_out,
	output logic        nvram_modified,

	output logic  [7:0] audio,
	output logic [14:0] x_out,
	output logic [14:0] y_out,
	output logic  [7:0] z_out,
	output logic  [3:0] color_out,
	output logic        is_dot,
	output logic        frame_done,
	output logic        avg_halted,
	output logic  [1:0] start_led,
	output logic        spinner_time_tick,
	output logic  [1:0] spinner_sample
);

	localparam logic [15:0] ROM_PROGRAM_END  = 16'h5000;
	localparam logic [15:0] ROM_VECTOR_BASE  = 16'h5000;
	localparam logic [15:0] ROM_STATE_BASE   = 16'h6000;
	localparam logic [15:0] ROM_COMMAND_BASE = 16'h6700;

	logic [2:0] clock_divider = 3'd0;
	logic [8:0] timer_3khz = 9'd0;
	logic [3:0] irq_counter = 4'd0;
	logic [7:0] watchdog_counter = 8'd0;
	logic [7:0] reset_hold = 8'hff;

	logic        ce_cpu;
	logic        ce_mathbox;
	logic        timer_tick;
	logic        irq_n;
	logic        machine_reset;
	logic        watchdog_expired;
	logic        pokey_1_potgo_write;

	logic [15:0] cpu_address;
	logic  [7:0] cpu_data_in;
	logic  [7:0] cpu_data_out;
	logic        cpu_rw_n;
	logic        cpu_sync;
	logic        cpu_write;

	logic        program_ram_select;
	logic        vector_memory_select;
	logic        pokey_1_select;
	logic        pokey_2_select;
	logic        program_rom_select;
	logic        color_write;
	logic        avg_go;
	logic        avg_reset;
	logic        watchdog_clear;
	logic        mathbox_start;
	logic        earom_latch_write;
	logic        earom_control_write;

	(* ramstyle = "M10K" *) logic [7:0] program_ram [0:2047];
	(* ramstyle = "M10K" *) logic [7:0] program_rom [0:20479];
	logic [7:0] program_ram_q;
	logic [7:0] program_rom_q;
	logic [14:0] program_rom_address;

	logic  [7:0] vector_data_out;
	logic [14:0] avg_x_raw;
	logic [14:0] avg_y_raw;
	logic  [7:0] avg_z_raw;
	logic  [3:0] avg_color_raw;
	logic        avg_is_dot;
	logic        avg_list_wrap;

	logic  [7:0] pokey_1_data;
	logic  [7:0] pokey_2_data;
	logic  [7:0] pokey_1_audio;
	logic  [7:0] pokey_2_audio;
	logic  [7:0] audio_unfiltered;
	logic  [7:0] pokey_1_pins;
	logic  [7:0] pokey_2_pins;
	logic  [1:0] selected_buttons;
	logic  [3:0] selected_spinner;

	logic        mathbox_busy;
	logic [15:0] mathbox_result;
	logic        mathbox_rom_write;
	logic  [2:0] mathbox_rom_index;
	logic  [7:0] mathbox_rom_address;

	logic  [7:0] earom_data;
	logic  [7:0] output_0;
	logic  [7:0] output_1;

	integer index;

	initial begin
		for (index = 0; index < 2048; index = index + 1)
			program_ram[index] = 8'h00;
	end

	assign ce_cpu = (clock_divider == 3'd0);
	assign ce_mathbox = (clock_divider[1:0] == 2'd0);
	assign timer_tick = ce_cpu && (timer_3khz == 9'h1ff);
	assign irq_n = ~(irq_counter[3] && irq_counter[2]);
	assign machine_reset = |reset_hold;
	assign watchdog_expired = timer_tick && (&watchdog_counter);

	assign cpu_write = ce_cpu && !cpu_rw_n;
	assign program_ram_select = (cpu_address[15:11] == 5'b00000);
	assign vector_memory_select = (cpu_address[15:13] == 3'b001);
	assign pokey_1_select = (cpu_address[15:4] == 12'h60c);
	assign pokey_2_select = (cpu_address[15:4] == 12'h60d);

	assign color_write = cpu_write && (cpu_address[15:4] == 12'h080);
	assign avg_go = cpu_write && (cpu_address == 16'h4800);
	assign avg_reset = machine_reset || (cpu_write && (cpu_address == 16'h5800));
	assign watchdog_clear = cpu_write && (cpu_address == 16'h5000);
	assign pokey_1_potgo_write = cpu_write && pokey_1_select &&
	                             (cpu_address[3:0] == 4'hb);
	assign mathbox_start = cpu_write && (cpu_address[15:5] == 11'b01100000100);
	assign earom_latch_write = cpu_write && (cpu_address[15:6] == 10'b0110000000);
	assign earom_control_write = cpu_write && (cpu_address == 16'h6040);

	always_comb begin
		program_rom_select = 1'b1;
		case (cpu_address[15:12])
			4'h9,
			4'ha,
			4'hb,
			4'hc,
			4'hd: program_rom_address = {
				cpu_address[14:12] - 3'd1,
				cpu_address[11:0]
			};
			4'hf: program_rom_address = {3'b100, cpu_address[11:0]};
			default: begin
				program_rom_select = 1'b0;
				program_rom_address = 15'd0;
			end
		endcase
	end

	always_comb begin
		cpu_data_in = 8'hff;
		if (program_ram_select)
			cpu_data_in = program_ram_q;
		else if (cpu_address == 16'h0c00)
			cpu_data_in = {
				timer_3khz[8], avg_halted,
				~diagnostic_step, ~service, ~slam,
				~coin_left, ~coin_center, ~coin_right
			};
		else if (cpu_address == 16'h0d00)
			cpu_data_in = dsw_1;
		else if (cpu_address == 16'h0e00)
			cpu_data_in = dsw_2;
		else if (vector_memory_select)
			cpu_data_in = vector_data_out;
		else if (cpu_address == 16'h6040)
			cpu_data_in = {mathbox_busy, 7'd0};
		else if (cpu_address == 16'h6050)
			cpu_data_in = earom_data;
		else if (cpu_address == 16'h6060)
			cpu_data_in = mathbox_result[7:0];
		else if (cpu_address == 16'h6070)
			cpu_data_in = mathbox_result[15:8];
		else if (pokey_1_select)
			cpu_data_in = pokey_1_data;
		else if (pokey_2_select)
			cpu_data_in = pokey_2_data;
		else if (program_rom_select)
			cpu_data_in = program_rom_q;
	end

	always @(posedge clk_12) begin
		if (reset)
			clock_divider <= 3'd0;
		else
			clock_divider <= clock_divider + 1'd1;

		if (reset || watchdog_expired)
			reset_hold <= 8'hff;
		else if (reset_hold != 8'd0)
			reset_hold <= reset_hold - 1'd1;

		if (machine_reset)
			timer_3khz <= 9'd0;
		else if (ce_cpu)
			timer_3khz <= timer_3khz + 1'd1;

		if (machine_reset || watchdog_clear)
			irq_counter <= 4'd0;
		else if (timer_tick && irq_n)
			irq_counter <= irq_counter + 1'd1;

		if (machine_reset || pause || watchdog_clear)
			watchdog_counter <= 8'd0;
		else if (timer_tick)
			watchdog_counter <= watchdog_counter + 1'd1;

		program_ram_q <= program_ram[cpu_address[10:0]];
		if (cpu_write && program_ram_select)
			program_ram[cpu_address[10:0]] <= cpu_data_out;

		program_rom_q <= program_rom[program_rom_address];
		if (rom_write && (rom_address < ROM_PROGRAM_END))
			program_rom[rom_address[14:0]] <= rom_data;

		if (machine_reset) begin
			output_0 <= 8'd0;
			output_1 <= 8'd0;
		end else if (cpu_write) begin
			if (cpu_address == 16'h4000)
				output_0 <= cpu_data_out;
			if (cpu_address == 16'h60e0)
				output_1 <= cpu_data_out;
		end
	end

	always_ff @(posedge clk_12) begin
		if (machine_reset) begin
			spinner_time_tick <= 1'b0;
			spinner_sample    <= 2'b00;
		end else begin
			spinner_time_tick <= timer_tick;
			spinner_sample    <= 2'b00;
			if (pokey_1_potgo_write)
				spinner_sample <= output_1[2] ? 2'b10 : 2'b01;
		end
	end

	tempest_cpu cpu
	(
		.clk(clk_12),
		.reset_n(!machine_reset),
		.enable(ce_cpu),
		.ready(!pause),
		.irq_n(irq_n),
		.data_in(cpu_data_in),
		.address(cpu_address),
		.data_out(cpu_data_out),
		.rw_n(cpu_rw_n),
		.sync(cpu_sync)
	);

	assign selected_buttons = output_1[2]
		? {fire_2, superzapper_2}
		: {fire_1, superzapper_1};
	assign selected_spinner = output_1[2] ? spinner_2 : spinner_1;
	assign pokey_1_pins = {3'b111, cocktail, selected_spinner};
	assign pokey_2_pins = {
		1'b1, ~start_2, ~start_1,
		~selected_buttons[1], ~selected_buttons[0], auxiliary_dip
	};

	pokey pokey_1
	(
		.ADDR(cpu_address[3:0]),
		.DIN(cpu_data_out),
		.DOUT(pokey_1_data),
		.DOUT_OE_L(),
		.RW_L(cpu_rw_n),
		.CS(1'b1),
		.CS_L(!pokey_1_select),
		.AUDIO_OUT(pokey_1_audio),
		.PIN(pokey_1_pins),
		.ENA(ce_cpu),
		.CLK(clk_12)
	);

	pokey pokey_2
	(
		.ADDR(cpu_address[3:0]),
		.DIN(cpu_data_out),
		.DOUT(pokey_2_data),
		.DOUT_OE_L(),
		.RW_L(cpu_rw_n),
		.CS(1'b1),
		.CS_L(!pokey_2_select),
		.AUDIO_OUT(pokey_2_audio),
		.PIN(pokey_2_pins),
		.ENA(ce_cpu),
		.CLK(clk_12)
	);

	assign mathbox_rom_write = rom_write &&
		(((rom_address[15:8] >= 8'h61) && (rom_address[15:8] <= 8'h66)) ||
		 ((rom_address >= ROM_COMMAND_BASE) &&
		  (rom_address < ROM_COMMAND_BASE + 16'h0020)));
	assign mathbox_rom_index = (rom_address[15:8] == 8'h67)
		? 3'd0
		: rom_address[10:8];
	assign mathbox_rom_address = rom_address[7:0];

	tempest_mathbox mathbox
	(
		.clk(clk_12),
		.reset(machine_reset),
		.ce_3m(ce_mathbox),
		.start(mathbox_start),
		.command(cpu_address[4:0]),
		.data_in(cpu_data_out),
		.busy(mathbox_busy),
		.result(mathbox_result),
		.rom_we(mathbox_rom_write),
		.rom_index(mathbox_rom_index),
		.rom_addr(mathbox_rom_address),
		.rom_data(rom_data)
	);

	tempest_earom earom
	(
		.clk(clk_12),
		.reset(machine_reset),
		.latch_write(earom_latch_write),
		.latch_address(cpu_address[5:0]),
		.latch_data(cpu_data_out),
		.control_write(earom_control_write),
		.control_data(cpu_data_out[3:0]),
		.data_out(earom_data),
		.modified(nvram_modified),
		.host_address(nvram_address),
		.host_data_in(nvram_data_in),
		.host_write(nvram_write),
		.host_data_out(nvram_data_out)
	);

	tempest_avg avg
	(
		.clk(clk_12),
		.clken(ce_cpu),
		.avg_reset(avg_reset),
		.avg_go(avg_go),
		.cpu_cs(vector_memory_select),
		.cpu_rw(cpu_rw_n),
		.cpu_addr(cpu_address[12:0]),
		.cpu_data_in(cpu_data_out),
		.cpu_data_out(vector_data_out),
		.color_wr(color_write),
		.color_addr(cpu_address[3:0]),
		.color_data(cpu_data_out[3:0]),
		.vector_rom_wr(rom_write &&
			(rom_address[15:12] == ROM_VECTOR_BASE[15:12])),
		.vector_rom_addr(rom_address[11:0]),
		.vector_rom_data(rom_data),
		.state_prom_wr(rom_write &&
			(rom_address[15:8] == ROM_STATE_BASE[15:8])),
		.state_prom_addr(rom_address[7:0]),
		.state_prom_data(rom_data[3:0]),
		.halted(avg_halted),
		.list_wrap(avg_list_wrap),
		.x_out(avg_x_raw),
		.y_out(avg_y_raw),
		.z_out(avg_z_raw),
		.color_out(avg_color_raw),
		.is_dot_out(avg_is_dot)
	);

	assign x_out = output_0[3] ? (~avg_x_raw + 1'd1) : avg_x_raw;
	assign y_out = output_0[4] ? (~avg_y_raw + 1'd1) : avg_y_raw;
	assign z_out = avg_z_raw;
	assign color_out = avg_color_raw;
	assign is_dot = avg_is_dot;
	assign frame_done = avg_list_wrap || avg_halted;
	assign start_led = ~output_1[1:0];
	assign audio_unfiltered = {1'b0, pokey_1_audio[7:1]} +
	                          {1'b0, pokey_2_audio[7:1]};

	tempest_audio_filter audio_filter
	(
		.clk(clk_12),
		.reset(machine_reset),
		.ce(ce_cpu),
		.enable(audio_filter_enable),
		.audio_in(audio_unfiltered),
		.audio_out(audio)
	);

endmodule
