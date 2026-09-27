`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: mxu_op_handler
 * ============================================================================
 *
 *  Description:
 *      Operand interface between the MXU controller, SRAM read path, and
 *      systolic array input pipeline.
 *
 *      The module forwards the current MXU memory indices and offsets to the
 *      SRAM address-generation logic while aligning the corresponding valid
 *      signals with the SRAM read data.
 *
 *      Operation:
 *
 *          1. Forward the current A and B K-dimension indices and matrix
 *             offsets to the memory address-generation logic.
 *
 *          2. Delay a_k_valid and b_k_valid by one cycle to match the SRAM
 *             read latency.
 *
 *          3. Forward the returned A and B operands when their delayed valid
 *             signal is asserted.
 *
 *          4. Drive zero operands when the corresponding memory data is not
 *             valid.
 *
 * Author: Paulo Dietrich
 * ============================================================================
 */

module mxu_op_handler (
    input logic clk, rst_n,

    // mxu control
    input k_dim_t a_k_idx,
    input k_dim_t b_k_idx,
    input logic   a_k_valid,
    input logic   b_k_valid,
    input m_dim_t a_m_offset,
    input n_dim_t b_n_offset,

    // memory
    input operand_t in_a[SA_ROWS],
    input operand_t in_b[SA_COLS],

    // memory address generation
    output k_dim_t a_k_rd_idx,
    output k_dim_t b_k_rd_idx,
    output m_dim_t a_m_rd_offset,
    output n_dim_t b_n_rd_offset,

    // systolic array
    output operand_t a_j[SA_ROWS],
    output operand_t b_i[SA_COLS]
);

    // Delayed valid signals align with the synchronous SRAM read data.
    logic a_k_valid_d, b_k_valid_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_k_valid_d <= 0;
            b_k_valid_d <= 0;
        end else begin
            a_k_valid_d <= a_k_valid;
            b_k_valid_d <= b_k_valid;
        end
    end

    // Forward the current memory indices and tile offsets.
    assign a_k_rd_idx    = a_k_idx;
    assign b_k_rd_idx    = b_k_idx;
    assign a_m_rd_offset = a_m_offset;
    assign b_n_rd_offset = b_n_offset;

    // Forward valid A operands to the systolic array.
    for (genvar r = 0; r < SA_ROWS; r++) begin : GEN_A
        always_comb begin
            if(a_k_valid_d)
                a_j[r] = in_a[r];
            else
                a_j[r] = '0;
        end
    end

    // Forward valid B operands to the systolic array.
    for (genvar c = 0; c < SA_COLS; c++) begin : GEN_B
        always_comb begin
            if(b_k_valid_d)
                b_i[c] = in_b[c];
            else
                b_i[c] = '0;
        end
    end

endmodule