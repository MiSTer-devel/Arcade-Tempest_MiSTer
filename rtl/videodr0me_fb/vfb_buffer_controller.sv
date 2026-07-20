`timescale 1ns / 1ps

// ============================================================================
// Quad-buffer controller.
// written 2026 by Videodr0me
// Manages drawing, presentation, retirement, and background tilemap clearing:
// CLEAN -> DRAWING -> {DRAWN|DISPLAY} -> DIRTY -> CLEARING -> CLEAN.
// ============================================================================

module vfb_buffer_controller (
    input  logic clk_sys,
    input  logic reset,

    // Settings: Buffer Mode
    // 0 = VBL + EOF (flush on EOF, swap at VBLANK)
    // 1 = VBL only (flush at VBLANK, swap when flush completes)
    // 2 = EOF only (flush on EOF, swap when flush completes)
    input  logic [1:0] BUFFER_MODE,

    // Synchronous Events
    input  logic eof_token_popped, // Asserted by Cache Manager
    input  logic vbl_swap_req,     // Asserted by Readout module at VBLANK start

    // Flush Handshake (Buffer Controller -> Cache Manager)
    output logic flush_req,
    input  logic flush_done,

    // Background Clearer Interface (Controller -> Cache Manager)
    output logic        clear_req,
    output logic [1:0]  clear_buf_idx,
    input  logic        clear_done,

    // Active Buffers Routing
    output logic [1:0]  buf_draw,
    output logic [1:0]  buf_display_out,
    output logic        display_valid,

    // Pipeline control
    output logic has_draw_buf        // True when a drawing buffer is assigned
);

    typedef enum logic [2:0] {
        ST_DISPLAY,
        ST_DRAWING,
        ST_DRAWN,
        ST_DIRTY,
        ST_CLEARING,
        ST_CLEAN
    } buf_state_t;

    buf_state_t buf_state[4];

    // State-presence flags and preferred slot indices.
    wire has_display = (buf_state[0]==ST_DISPLAY) | (buf_state[1]==ST_DISPLAY) | (buf_state[2]==ST_DISPLAY) | (buf_state[3]==ST_DISPLAY);
    wire has_drawing = (buf_state[0]==ST_DRAWING) | (buf_state[1]==ST_DRAWING) | (buf_state[2]==ST_DRAWING) | (buf_state[3]==ST_DRAWING);
    wire has_drawn   = (buf_state[0]==ST_DRAWN)   | (buf_state[1]==ST_DRAWN)   | (buf_state[2]==ST_DRAWN)   | (buf_state[3]==ST_DRAWN);
    wire has_dirty   = (buf_state[0]==ST_DIRTY)   | (buf_state[1]==ST_DIRTY)   | (buf_state[2]==ST_DIRTY)   | (buf_state[3]==ST_DIRTY);
    wire has_clean   = (buf_state[0]==ST_CLEAN)   | (buf_state[1]==ST_CLEAN)   | (buf_state[2]==ST_CLEAN)   | (buf_state[3]==ST_CLEAN);

    wire [1:0] buf_display_comb  = (buf_state[0]==ST_DISPLAY)  ? 2'd0 : (buf_state[1]==ST_DISPLAY)  ? 2'd1 : (buf_state[2]==ST_DISPLAY)  ? 2'd2 : 2'd3;

    wire [1:0] drawn_idx =
        (buf_state[buf_display_comb + 2'd1] == ST_DRAWN) ? (buf_display_comb + 2'd1) :
        (buf_state[buf_display_comb + 2'd2] == ST_DRAWN) ? (buf_display_comb + 2'd2) :
        (buf_state[buf_display_comb + 2'd3] == ST_DRAWN) ? (buf_display_comb + 2'd3) :
        buf_display_comb;

    wire [1:0] dirty_idx =
        (buf_state[buf_display_comb + 2'd1] == ST_DIRTY) ? (buf_display_comb + 2'd1) :
        (buf_state[buf_display_comb + 2'd2] == ST_DIRTY) ? (buf_display_comb + 2'd2) :
        (buf_state[buf_display_comb + 2'd3] == ST_DIRTY) ? (buf_display_comb + 2'd3) :
        buf_display_comb;

    wire [1:0] clean_idx =
        (buf_state[buf_display_comb + 2'd1] == ST_CLEAN) ? (buf_display_comb + 2'd1) :
        (buf_state[buf_display_comb + 2'd2] == ST_CLEAN) ? (buf_display_comb + 2'd2) :
        (buf_state[buf_display_comb + 2'd3] == ST_CLEAN) ? (buf_display_comb + 2'd3) :
        buf_display_comb;

    logic [1:0] internal_buf_draw;
    assign buf_draw = internal_buf_draw;

    // Registered buffer-selection outputs. They change only on buffer state
    // transitions, and the cache manager independently gates pixel intake.
    logic [1:0] buf_display_reg = 2'd0;
    logic       has_draw_buf_reg = 0;
    logic       display_valid_reg = 0;
    always_ff @(posedge clk_sys) begin
        if (reset) begin
            buf_display_reg   <= 2'd0;
            has_draw_buf_reg  <= 0;
            display_valid_reg <= 0;
        end else begin
            buf_display_reg   <= buf_display_comb;
            has_draw_buf_reg  <= has_drawing;
            display_valid_reg <= has_display;
        end
    end
    assign buf_display_out = buf_display_reg;
    assign has_draw_buf    = has_draw_buf_reg;
    assign display_valid   = display_valid_reg;

    // Event qualifiers
    logic flush_in_progress;
    logic flush_pending;

    // Flush complete: cache manager acknowledged our flush request
    wire evt_flush_complete = flush_in_progress && flush_done;

    // VBLANK promotion: swap DRAWN -> DISPLAY (VBL+EOF mode only)
    wire evt_vbl_promote = vbl_swap_req && (BUFFER_MODE == 2'd0) && has_drawn;

    // Assign new drawing buffer: promote a CLEAN slot
    wire evt_assign_draw = !has_drawing && has_clean && !flush_in_progress;

    // Clear complete: cache manager finished zeroing the tilemap
    wire evt_clear_complete = clear_req && clear_done;

    // Clear start: begin clearing a dirty buffer
    wire evt_clear_start = !clear_req && has_dirty;

    // Registered logic
    always_ff @(posedge clk_sys) begin
        if (reset) begin
            buf_state[0]      <= ST_DISPLAY;
            buf_state[1]      <= ST_DRAWING;
            buf_state[2]      <= ST_DIRTY;
            buf_state[3]      <= ST_DIRTY;
            internal_buf_draw <= 2'd1;
            flush_req         <= 0;
            flush_in_progress <= 0;
            flush_pending     <= 0;
            clear_req         <= 0;
            clear_buf_idx     <= 2'd0;
        end else begin

            // Retain mode-specific flush events until the handshake can start.
            if (BUFFER_MODE == 2'd1) begin
                if (vbl_swap_req && has_drawing)       flush_pending <= 1;
            end else begin
                if (eof_token_popped && has_drawing)   flush_pending <= 1;
            end

            // Hold flush_req until the cache manager acknowledges completion.
            if (evt_flush_complete) begin
                flush_req         <= 0;
                flush_in_progress <= 0;
            end else if (!flush_in_progress && flush_pending) begin
                flush_req         <= 1;
                flush_in_progress <= 1;
                flush_pending     <= 0;
            end

            // The if/else order defines priority when transition events overlap.
            for (int i = 0; i < 4; i++) begin

                if (evt_flush_complete && i[1:0] == internal_buf_draw) begin
                    // Promote the completed drawing buffer.
                    buf_state[i] <= (BUFFER_MODE != 2'd0) ? ST_DISPLAY : ST_DRAWN;

                end else if (evt_flush_complete && (BUFFER_MODE != 2'd0)
                             && has_display && i[1:0] == buf_display_comb) begin
                    // Retire the old display in immediate-swap modes.
                    buf_state[i] <= ST_DIRTY;

                end else if (evt_vbl_promote && i[1:0] == drawn_idx) begin
                    // Present the newest completed frame at VBLANK.
                    buf_state[i] <= ST_DISPLAY;

                end else if ((buf_state[i] == ST_DRAWN) &&
                             ((BUFFER_MODE != 2'd0) ||
                              (evt_flush_complete && (BUFFER_MODE == 2'd0)) ||
                              (evt_vbl_promote && (BUFFER_MODE == 2'd0)))) begin
                    // Reclaim stale queued frames. EOF+VBL keeps only
                    // the newest completed frame waiting for the next VBLANK;
                    // VBL and EOF modes do not use ST_DRAWN.
                    buf_state[i] <= ST_DIRTY;

                end else if (evt_vbl_promote && has_display
                             && i[1:0] == buf_display_comb) begin
                    // Retire the old display after VBLANK promotion.
                    buf_state[i] <= ST_DIRTY;

                end else if (evt_assign_draw && i[1:0] == clean_idx) begin
                    // Assign a clean draw target.
                    buf_state[i] <= ST_DRAWING;

                end else if (evt_clear_complete && i[1:0] == clear_buf_idx) begin
                    // Finish background clearing.
                    buf_state[i] <= ST_CLEAN;

                end else if (evt_clear_start && i[1:0] == dirty_idx) begin
                    // Begin background clearing.
                    buf_state[i] <= ST_CLEARING;
                end
                // else: retain current state

            end

            // Track a newly assigned draw slot.
            if (evt_assign_draw)
                internal_buf_draw <= clean_idx;

            // Background-clear handshake.
            if (evt_clear_complete) begin
                clear_req <= 0;
            end else if (evt_clear_start) begin
                clear_req     <= 1;
                clear_buf_idx <= dirty_idx;
            end

        end
    end

endmodule
