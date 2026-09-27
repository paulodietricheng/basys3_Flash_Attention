`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: mxu
 * ============================================================================
 *
 *  Description:
 *      Top-level integration module for the matrix multiplication unit.
 *
 *      The module connects the MXU controller, operand handler, operand skewer,
 *      and systolic array.
 *
 *      Operation:
 *
 *          1. mxu_ctrl sequences the matrix multiplication and generates the
 *             K-dimension indices used to read operands from memory.
 *
 *          2. mxu_op_handler receives the memory data and selects the current
 *             A and B operands for the systolic array.
 *
 *          3. mxu_op_skewer delays the operands so they arrive at the correct
 *             processing elements at the correct cycle.
 *
 *          4. mxu_systolic_array performs the multiply-accumulate operations
 *             and produces the output matrix.
 *
 * ============================================================================
 */

module mxu (
    input logic clk, rst_n,

    // control
    input  logic     mxu_start,
    output logic     mxu_done,
    input  mxu_cmd_t mxu_cmd,

    // memory
    output logic mxu_using_mem[2],
    input  operand_t in_a[SA_ROWS],
    input  operand_t in_b[SA_COLS],

    // memory address generation
    output k_dim_t a_k_rd_idx,
    output k_dim_t b_k_rd_idx,
    output m_dim_t a_m_rd_offset,
    output n_dim_t b_n_rd_offset,

    // output
    output accumulator_t c[SA_ROWS][SA_COLS]
);

    // control
    logic a_k_valid, b_k_valid;
    logic array_en, clr_acc_n;
    k_dim_t a_k_idx, b_k_idx;

    // operands
    operand_t a_j [SA_ROWS], b_i[SA_COLS];
    operand_t a_j_skewed [SA_ROWS], b_i_skewed[SA_COLS];

    // Controls the MXU execution and memory access timing.
    mxu_ctrl U_MXU_CTRL (
        .clk          (clk),
        .rst_n        (rst_n),
        .mxu_start    (mxu_start),
        .mxu_done     (mxu_done),
        .mxu_cmd      (mxu_cmd),
        .array_en     (array_en),
        .clr_acc_n    (clr_acc_n),
        .a_k_idx      (a_k_idx),
        .b_k_idx      (b_k_idx),
        .a_k_valid    (a_k_valid),
        .b_k_valid    (b_k_valid),
        .mxu_using_mem(mxu_using_mem)
    );

    // Selects and forwards the current A and B operands from memory.
    mxu_op_handler U_MXU_OPH (
        .clk          (clk),
        .rst_n        (rst_n),
        .a_k_idx      (a_k_idx),
        .b_k_idx      (b_k_idx),
        .a_k_valid    (a_k_valid),
        .b_k_valid    (b_k_valid),
        .in_a         (in_a),
        .in_b         (in_b),
        .a_m_offset   (mxu_cmd.a_m_offset),
        .b_n_offset   (mxu_cmd.b_n_offset),
        .a_k_rd_idx   (a_k_rd_idx),
        .b_k_rd_idx   (b_k_rd_idx),
        .a_m_rd_offset(a_m_rd_offset),
        .b_n_rd_offset(b_n_rd_offset),
        .a_j          (a_j),
        .b_i          (b_i)
    );

    // Skews operands
    mxu_op_skewer U_MXU_OPS (
        .clk       (clk),
        .rst_n     (rst_n),
        .a_j       (a_j),
        .b_i       (b_i),
        .a_j_skewed(a_j_skewed),
        .b_i_skewed(b_i_skewed)
    );

    // Performs the systolic matrix multiplication.
    mxu_systolic_array U_MXU_SA (
        .clk       (clk),
        .rst_n     (rst_n),
        .array_en  (array_en),
        .clr_acc_n (clr_acc_n),
        .a_j_skewed(a_j_skewed),
        .b_i_skewed(b_i_skewed),
        .c         (c)
    );

endmodule