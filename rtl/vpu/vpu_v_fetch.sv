`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: vpu_v_fetch
 * ============================================================================
 *
 *  Description:
 *      Fetches the V tile required by the VPU from the packed SRAM interface.
 *
 *      The SRAM read path is synchronous with one cycle of latency. This module
 *      generates the sequential read indices, tracks the delayed return index,
 *      unpacks the returned memory lanes, and reconstructs the full V tile.
 *
 *      Operation:
 *
 *          1. Accept vf_start while idle.
 *          2. Issue one packed V-memory read every cycle.
 *          3. Delay the issued index by one cycle to match SRAM latency.
 *          4. Unpack each returned memory beat into the correct V tile row.
 *          5. Pulse vf_done after the final returned beat is captured.
 *
 *      The memory interface is assumed to always accept reads while vf_busy is
 *      asserted.
 *
 * Author: Paulo Dietrich, assisted by an AI Agent
 * ============================================================================
 */

module vpu_v_fetch (
    input logic clk, rst_n,

    // control
    input  logic vf_start,
    output logic vf_busy,
    output logic vf_done,

    // v memory
    output logic [V_IDX_W-1:0] vf_idx_out,
    output logic               vf_rd_valid,
    input  operand_t           v_mbd [NUM_PORTS*WPA],

    // output tile
    output operand_t v_tile [SA_COLS][D_MODEL]
);

    localparam int LANES         = NUM_PORTS * WPA;
    localparam int BEATS_PER_ROW = (D_MODEL + LANES - 1) / LANES;
    localparam int TOTAL_BEATS   = SA_COLS * BEATS_PER_ROW;
    localparam int COUNT_W       = $clog2(TOTAL_BEATS + 1);

    // read tracking
    logic [COUNT_W-1:0] issued;
    logic capture_valid;
    logic [V_IDX_W-1:0] capture_idx;

    // Issue one memory read per cycle while beats remain.
    assign vf_rd_valid = rst_n && vf_busy && (issued < COUNT_W'(TOTAL_BEATS));
    assign vf_idx_out  = vf_rd_valid ? V_IDX_W'(issued) : '0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vf_busy       <= 1'b0;
            vf_done       <= 1'b0;
            issued        <= '0;
            capture_valid <= 1'b0;
            capture_idx   <= '0;

            for (int r = 0; r < SA_COLS; r++)
                for (int d = 0; d < D_MODEL; d++)
                    v_tile[r][d] <= '0;
        end else begin
            vf_done <= 1'b0;

            // SRAM data returns one cycle after the read request.
            capture_valid <= vf_rd_valid;

            if (!vf_busy) begin
                issued <= '0;

                if (vf_start)
                    vf_busy <= 1'b1;
            end else begin

                // Track each issued SRAM read.
                if (vf_rd_valid) begin
                    capture_idx <= vf_idx_out;
                    issued      <= issued + 1'b1;
                end

                // Capture and unpack the returned SRAM beat.
                if (capture_valid) begin
                    for (int lane = 0; lane < LANES; lane++) begin
                        if (((int'(capture_idx) % BEATS_PER_ROW)*LANES + lane) < D_MODEL)
                            v_tile[int'(capture_idx)/BEATS_PER_ROW]
                                  [(int'(capture_idx)%BEATS_PER_ROW)*LANES+lane] <= v_mbd[lane];
                    end

                    // Final returned beat completes the V tile.
                    if (capture_idx == V_IDX_W'(TOTAL_BEATS-1)) begin
                        vf_busy <= 1'b0;
                        vf_done <= 1'b1;
                    end
                end
            end
        end
    end

endmodule