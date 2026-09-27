`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: mxu_ctrl
 * ============================================================================
 *
 *  Description:
 *      Control unit for the matrix multiplication unit.
 *
 *      The controller captures an MXU command, clears the systolic array
 *      accumulators, streams K-dimension operands from memory, and keeps the
 *      array enabled long enough for the final result to propagate through
 *      the systolic pipeline.
 *
 *      Operation:
 *
 *          1. Wait for mxu_start and register the incoming MXU command.
 *          2. Clear the systolic array accumulators.
 *          3. Stream A and B operands across the requested K dimension.
 *          4. Drain the systolic pipeline after the final operands are sent.
 *          5. Pulse mxu_done when the result is ready.
 *
 * Author: Paulo Dietrich
 * ============================================================================
 */

module mxu_ctrl (
    input logic clk, rst_n,

    // control
    input  logic     mxu_start,
    output logic     mxu_done,
    input  mxu_cmd_t mxu_cmd,

    // systolic array
    output logic array_en,
    output logic clr_acc_n,

    // memory
    output k_dim_t a_k_idx,
    output k_dim_t b_k_idx,
    output logic   a_k_valid,
    output logic   b_k_valid,
    output logic   mxu_using_mem[2]
);

    // Registered command for the active MXU operation.
    mxu_cmd_t reg_cmd;

    always_ff @(posedge clk)
        if (mxu_start)
            reg_cmd <= mxu_cmd;

    // Pipeline latency tracking.
    logic [RESULT_LAT_W-1:0] result_lat, counter;

    assign result_lat = 2*reg_cmd.m + reg_cmd.n + reg_cmd.k - 2;

    typedef enum logic [2:0] {
        m_IDLE,
        m_CLEAR,
        m_STREAM,
        m_DRAIN,
        m_DONE
    } mxu_state_t;

    mxu_state_t curr_state;

    // Count cycles while operands/results are propagating through the array.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            counter <= '0;
        else if (curr_state == m_IDLE || curr_state == m_CLEAR || curr_state == m_DONE)
            counter <= '0;
        else if (curr_state == m_STREAM || curr_state == m_DRAIN)
            counter <= counter + 1;
    end

    // Current K indices are valid while they remain inside the requested range.
    assign a_k_valid = (curr_state == m_STREAM) && (a_k_idx < reg_cmd.k + reg_cmd.a_k_offset);
    assign b_k_valid = (curr_state == m_STREAM) && (b_k_idx < reg_cmd.k + reg_cmd.b_k_offset);

    // Memory request enables correspond to the current address/valid pair.
    assign mxu_using_mem[0] = rst_n && a_k_valid;
    assign mxu_using_mem[1] = rst_n && b_k_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= m_IDLE;
            array_en    <= 0;
            clr_acc_n   <= 1;
            mxu_done    <= 0;
            a_k_idx     <= '0;
            b_k_idx     <= '0;
        end else begin
            array_en  <= 0;
            clr_acc_n <= 1;
            mxu_done  <= 0;
            a_k_idx   <= '0;
            b_k_idx   <= '0;

            case(curr_state)

                // Wait for a new MXU command.
                m_IDLE: begin
                    a_k_idx    <= '0;
                    b_k_idx    <= '0;
                    curr_state <= mxu_start ? m_CLEAR : m_IDLE;
                end

                // Clear previous accumulator contents before a new operation.
                m_CLEAR: begin
                    clr_acc_n   <= 0;
                    a_k_idx     <= reg_cmd.a_k_offset;
                    b_k_idx     <= reg_cmd.b_k_offset;
                    curr_state  <= m_STREAM;
                end

                // Stream operands through the K dimension.
                m_STREAM: begin
                    array_en  <= 1;
                    clr_acc_n <= 1;

                    if (!(a_k_valid & b_k_valid))
                        curr_state <= m_DRAIN;
                    else begin
                        a_k_idx <= a_k_idx + 1'b1;
                        b_k_idx <= b_k_idx + 1'b1;
                    end
                end

                // Keep the array enabled until the final result exits the pipeline.
                m_DRAIN: begin
                    array_en  <= 1;
                    clr_acc_n <= 1;
                    a_k_idx   <= '0;
                    b_k_idx   <= '0;
                    curr_state <= (counter == result_lat) ? m_DONE : m_DRAIN;
                end

                // Signal completion for one cycle.
                m_DONE: begin
                    mxu_done   <= 1;
                    array_en   <= 0;
                    clr_acc_n  <= 1;
                    a_k_idx    <= '0;
                    b_k_idx    <= '0;
                    curr_state <= m_IDLE;
                end

                default:
                    curr_state <= m_IDLE;

            endcase
        end
    end

endmodule