`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: attention_ctrl
 * ============================================================================
 *
 *  Description:
 *      Controls the tiled execution of the Flash Attention accelerator.
 *
 *      The input sequence is divided into BATCH_SIZE tiles. For every query
 *      tile, the controller iterates across every key/value tile and issues
 *      one MXU command for each Q/K tile pair.
 *
 *      Operation:
 *
 *          1. Wait for a valid start request.
 *          2. Calculate the number of sequence batches.
 *          3. Generate an MXU command for the current Q and K/V tiles.
 *          4. Wait for the VPU/output path to retire the current operation.
 *          5. Advance through all K/V tiles for the current Q tile.
 *          6. Advance to the next Q tile and repeat.
 *          7. Assert done after all Q/K/V tile combinations complete.
 *
 *      Invalid sequence lengths are ignored. The sequence length must be
 *      non-zero, no larger than MAX_TOKENS, and divisible by BATCH_SIZE.
 * 
 * Author: Paulo Dietrich
 * ============================================================================
 */

module attention_ctrl (
    input logic clk, rst_n,

    // control
    input  logic                         start,
    input  logic [MAX_TILE_SQ_LEN_W-1:0] tile_sq_len,
    output logic                         busy,
    output logic                         done,

    // mxu
    output logic     mxu_start,
    output mxu_cmd_t mxu_cmd,

    // vpu
    input logic vpu_done
);

    // Batch indices for the current Q and K/V tiles.
    logic [MAX_TILE_W-1:0] q_batch_idx;
    logic [MAX_TILE_W-1:0] kv_batch_idx;

    // Number of BATCH_SIZE tiles in the current sequence.
    logic [BATCH_COUNT_W-1:0] num_batches;

    // BATCH_SIZE is a power of two, allowing division through a right shift.
    localparam SHIFT = $clog2(BATCH_SIZE);

    typedef enum logic [1:0] {
        fa_IDLE,
        fa_SEND_CMD,
        fa_COMPUTE,
        fa_DONE
    } fa_state_t;

    fa_state_t curr_state;

    // Controller status.
    assign busy = (curr_state != fa_IDLE) && (curr_state != fa_DONE);
    assign done = (curr_state == fa_DONE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            num_batches  <= '0;
            mxu_cmd      <= '0;
            mxu_start    <= '0;
            q_batch_idx  <= '0;
            kv_batch_idx <= '0;
            curr_state   <= fa_IDLE;
        end else begin
            // MXU start is a one-cycle pulse.
            mxu_start <= 1'b0;

            case (curr_state)

                // Wait for a valid sequence to begin.
                fa_IDLE: begin
                    mxu_cmd   <= '0;
                    mxu_start <= '0;

                    if (start && tile_sq_len != 0 && tile_sq_len <= MAX_TILE_SQ_LEN_W'(MAX_TOKENS) &&
                        (tile_sq_len % BATCH_SIZE) == 0) begin
                        num_batches  <= BATCH_COUNT_W'(tile_sq_len >> SHIFT);
                        q_batch_idx  <= '0;
                        kv_batch_idx <= '0;
                        curr_state   <= fa_SEND_CMD;
                    end
                end

                // Configure the MXU for the current Q and K/V tile pair.
                fa_SEND_CMD: begin
                    mxu_cmd.m          <= m_dim_t'(SA_ROWS);
                    mxu_cmd.n          <= n_dim_t'(SA_COLS);
                    mxu_cmd.k          <= k_dim_t'(D_MODEL);
                    mxu_cmd.a_m_offset <= m_dim_t'(BATCH_SIZE * q_batch_idx);
                    mxu_cmd.a_k_offset <= '0;
                    mxu_cmd.b_k_offset <= '0;
                    mxu_cmd.b_n_offset <= n_dim_t'(BATCH_SIZE * kv_batch_idx);

                    mxu_start  <= 1'b1;
                    curr_state <= fa_COMPUTE;
                end

                // Wait for the current attention tile operation to retire.
                fa_COMPUTE: begin
                    if (vpu_done) begin

                        // Current K/V tile is the last one for this Q tile.
                        if (BATCH_COUNT_W'(kv_batch_idx) == num_batches - 1'b1) begin
                            q_batch_idx  <= q_batch_idx + 1;
                            kv_batch_idx <= '0;

                            // Current Q tile is also the final Q tile.
                            if (BATCH_COUNT_W'(q_batch_idx) == num_batches - 1'b1) begin
                                q_batch_idx <= '0;
                                curr_state  <= fa_DONE;
                            end else begin
                                curr_state <= fa_SEND_CMD;
                            end

                        // Advance to the next K/V tile.
                        end else begin
                            kv_batch_idx <= kv_batch_idx + 1;
                            curr_state   <= fa_SEND_CMD;
                        end
                    end else
                        curr_state <= fa_COMPUTE;
                end

                // Pulse done for one cycle before returning to idle.
                fa_DONE:
                    curr_state <= fa_IDLE;

                default:
                    curr_state <= fa_IDLE;

            endcase
        end
    end

endmodule