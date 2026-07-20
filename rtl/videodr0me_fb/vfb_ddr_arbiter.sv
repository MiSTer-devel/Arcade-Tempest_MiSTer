// ============================================================================
// Fixed-priority DDRAM burst arbiter.
// written 2026 by Videodr0me
// Priority is readout, flush, then fill. The arbiter routes requests and
// responses, counts accepted beats, and drains in-flight bursts across reset.
// ============================================================================

module vfb_ddr_arbiter (
	input  logic        clk_sys,
	input  logic        rst_sys,

	// DDRAM Avalon-MM interface
	input  logic        DDRAM_BUSY,
	output logic [7:0]  DDRAM_BURSTCNT,
	output logic [28:0] DDRAM_ADDR,
	output              DDRAM_RD,
	output              DDRAM_WE,
	output wire [63:0] DDRAM_DIN,
	output wire [7:0]  DDRAM_BE,
	input  logic [63:0] DDRAM_DOUT,
	input  logic        DDRAM_DOUT_READY,

	// Requester interfaces

	// 1. VGA Readout (Read, Highest Priority)
	input  logic        readout_ready,
	output logic        readout_grant,
	input  logic [28:0] readout_addr,
	input  logic [8:0]  readout_burstcnt,
	output logic [63:0] readout_data,
	output logic        readout_data_valid,

	// 3. Cache Fill (Read)
	input  logic        fill_ready,
	output logic        fill_grant,
	input  logic [28:0] fill_addr,
	input  logic [7:0]  fill_burstcnt,
	output logic [63:0] fill_data,
	output logic        fill_data_valid,

	// 2. Cache Flush (Write)
	input  logic        flush_ready,
	output logic        flush_grant,
	output logic        flush_done,         // Pulse: last beat accepted
	input  logic [28:0] flush_addr,
	input  logic [7:0]  flush_burstcnt,
	input  logic [63:0] flush_din,          // Current beat data from requester
	input  logic [7:0]  flush_be,           // Current beat byte enables
	output wire         flush_advance,      // Beat accepted; present next beat
	output logic [23:0] debug_flashparam,   // Color-coded activity status
	output wire         arbiter_idle,       // True if arbiter is in IDLE state
	output wire         reset_busy          // Active during reset or burst drain
);

	typedef enum logic [2:0] {
		ARB_IDLE,
		ARB_READOUT,
		ARB_FILL,
		ARB_FLUSH
	} arb_state_t;

	arb_state_t arb_state = ARB_IDLE;
	logic [8:0] burst_counter = 0;
	logic [8:0] burst_target  = 0;    // Latched burstcnt for drain tracking

	// Synchronize reset and retain it while an in-flight burst drains.
	logic [1:0] rst_sync = 2'b11;
	always_ff @(posedge clk_sys) rst_sync <= {rst_sync[0], rst_sys};
	wire rst_ext = rst_sync[1];

	logic reset_pending = 0;
	wire rst_active = rst_ext || reset_pending;
	logic reset_busy_q = 1'b1;
	always_ff @(posedge clk_sys) reset_busy_q <= rst_active;

	// Internal WE/RD signals (gated by safety clamp on output)
	logic internal_rd = 0;
	logic internal_we = 0;

	// Safety Clamp: Limit access to our framebuffer region
	// (0x30000000 - 0x327FFFFF byte address = 0x06000000 - 0x064FFFFF word address)
	wire safe_address = (DDRAM_ADDR >= 29'h06000000) && (DDRAM_ADDR <= 29'h064FFFFF);
	assign DDRAM_WE = internal_we && safe_address && !rst_active;
	assign DDRAM_RD = internal_rd && safe_address;

	assign DDRAM_DIN = (arb_state == ARB_FLUSH && !rst_active) ? flush_din : 64'd0;
	assign DDRAM_BE  = (arb_state == ARB_FLUSH && !rst_active) ? flush_be : 8'h00;

	assign flush_advance = (arb_state == ARB_FLUSH) && !DDRAM_BUSY && !rst_active;
	assign arbiter_idle = (arb_state == ARB_IDLE);
	assign reset_busy = reset_busy_q;

	localparam int RESET_DRAIN_WDOG_BITS = 16;

	logic [RESET_DRAIN_WDOG_BITS-1:0] reset_drain_wdog = '0;

	wire arb_read_state =
		(arb_state == ARB_READOUT) || (arb_state == ARB_FILL);

	wire arb_drain_progress =
		arb_read_state ? DDRAM_DOUT_READY :
		(arb_state == ARB_FLUSH) ? !DDRAM_BUSY :
		1'b0;

	wire reset_read_drain_timeout =
		(arb_state != ARB_IDLE) &&
		!arb_drain_progress &&
		(&reset_drain_wdog);

	always_ff @(posedge clk_sys) begin
		// Retain reset until the active burst reaches a safe boundary.
		if (rst_ext) begin
			if (arb_state != ARB_IDLE) reset_pending <= 1;
		end else if (arb_state == ARB_IDLE) begin
			reset_pending <= 0;
		end

		if (arb_state != ARB_IDLE) begin
			if (arb_drain_progress)
				reset_drain_wdog <= '0;
			else
				reset_drain_wdog <= reset_drain_wdog + 1'b1;
		end else begin
			reset_drain_wdog <= '0;
		end

		// Default-clear one-shot pulses
		readout_grant <= 0;
		fill_grant <= 0;
		flush_grant <= 0;
		flush_done <= 0;
		readout_data_valid <= 0;
		fill_data_valid <= 0;

		if (reset_read_drain_timeout) begin
			arb_state          <= ARB_IDLE;
			reset_pending      <= 1'b0;
			internal_rd        <= 1'b0;
			internal_we        <= 1'b0;
			burst_counter      <= '0;
			burst_target       <= '0;
			readout_grant      <= 1'b0;
			fill_grant         <= 1'b0;
			flush_grant        <= 1'b0;
			readout_data_valid <= 1'b0;
			fill_data_valid    <= 1'b0;
		end else begin
			case (arb_state)
			ARB_IDLE: begin
				burst_counter <= 0;

				if (!rst_active) begin
					// Fixed-Priority Dispatcher
					if (readout_ready) begin
						arb_state <= ARB_READOUT;
						internal_rd <= 1;
						DDRAM_ADDR <= readout_addr;
						DDRAM_BURSTCNT <= readout_burstcnt[7:0]; // 8'h00 encodes 256 beats.
						burst_target <= readout_burstcnt;
						readout_grant <= 1;
					end else if (flush_ready) begin
						arb_state <= ARB_FLUSH;
						internal_we <= 1;
						DDRAM_ADDR <= flush_addr;
						DDRAM_BURSTCNT <= flush_burstcnt;
						burst_target <= flush_burstcnt;
						flush_grant <= 1;
					end else if (fill_ready) begin
						arb_state <= ARB_FILL;
						internal_rd <= 1;
						DDRAM_ADDR <= fill_addr;
						DDRAM_BURSTCNT <= fill_burstcnt;
						burst_target <= fill_burstcnt;
						fill_grant <= 1;
					end
				end
			end

			ARB_READOUT: begin
				if (!DDRAM_BUSY) internal_rd <= 0;

				if (DDRAM_DOUT_READY) begin
					if (!rst_active) begin
						readout_data <= DDRAM_DOUT;
						readout_data_valid <= 1;
					end
					burst_counter <= burst_counter + 1'b1;
					if (burst_counter == burst_target - 1)
						arb_state <= ARB_IDLE;
				end
			end

			ARB_FILL: begin
				if (!DDRAM_BUSY) internal_rd <= 0;

				if (DDRAM_DOUT_READY) begin
					if (!rst_active) begin
						fill_data <= DDRAM_DOUT;
						fill_data_valid <= 1;
					end
					burst_counter <= burst_counter + 1'b1;
					if (burst_counter == burst_target - 1)
						arb_state <= ARB_IDLE;
				end
			end

			ARB_FLUSH: begin
				if (!DDRAM_BUSY) begin
					burst_counter <= burst_counter + 1'b1;

					if (burst_counter == burst_target - 1) begin
						// Last beat accepted
						internal_we <= 0;
						if (!rst_active) flush_done <= 1;
						arb_state <= ARB_IDLE;
					end
				end
			end

			default: begin
				arb_state          <= ARB_IDLE;
				reset_pending      <= 1'b0;
				internal_rd        <= 1'b0;
				internal_we        <= 1'b0;
				burst_counter      <= '0;
				burst_target       <= '0;
				readout_data_valid <= 1'b0;
				fill_data_valid    <= 1'b0;
				flush_done         <= 1'b0;
			end
		endcase
		end
	end

	always_comb begin
		case (arb_state)
			ARB_IDLE: begin
				debug_flashparam = 24'h000000;
			end
			ARB_READOUT: begin
				debug_flashparam = DDRAM_DOUT_READY ? 24'h0000FF : 24'h00007F;
			end
			ARB_FILL: begin
				debug_flashparam = DDRAM_DOUT_READY ? 24'h00FF00 : 24'h007F00;
			end
			ARB_FLUSH: begin
				debug_flashparam = !DDRAM_BUSY ? 24'hFF0000 : 24'h7F0000;
			end
			default: begin
				debug_flashparam = 24'h000000;
			end
		endcase
	end

endmodule
