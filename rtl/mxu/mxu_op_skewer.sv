`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: mxu_op_skewer
 * ============================================================================
 *
 *  Description:
 *      Skews the A and B operands before they enter the systolic array.
 *
 *      In a systolic array, operands entering later rows and columns must be
 *      delayed so that matching A and B values meet at the correct processing
 *      element during the same clock cycle.
 *
 *      Operation:
 *
 *          1. Row 0 of A and column 0 of B pass directly to the array.
 *
 *          2. Each additional A row is delayed by its row index.
 *
 *          3. Each additional B column is delayed by its column index.
 *
 *      The generated shift registers create the diagonal wavefront required
 *      by the systolic array.
 *
 * Author: Paulo Dietrich
 * ============================================================================
 */

module mxu_op_skewer (
    input logic clk, rst_n,

    // operands
    input operand_t a_j[SA_ROWS],
    input operand_t b_i[SA_COLS],

    // systolic array
    output operand_t a_j_skewed[SA_ROWS],
    output operand_t b_i_skewed[SA_COLS]
);

    // Row 0 and column 0 require no delay.
    always_comb begin
        if(!rst_n) begin
            a_j_skewed[0] = '0;
            b_i_skewed[0] = '0;
        end else begin
            a_j_skewed[0] = a_j[0];
            b_i_skewed[0] = b_i[0];
        end
    end

    // Delay each A row by its row index.
    for (genvar r = 1; r < SA_ROWS; r++) begin : GEN_SKEW_ROWS
        operand_t a_shift_regs[0:r-1];

        always_ff @(posedge clk) begin
            if(!rst_n) begin
                for(int d = 0; d < r; d++)
                    a_shift_regs[d] <= '0;
            end else begin
                a_shift_regs[0] <= a_j[r];
                for(int d = 1; d < r; d++)
                    a_shift_regs[d] <= a_shift_regs[d-1];
            end
        end

        assign a_j_skewed[r] = a_shift_regs[r-1];
    end

    // Delay each B column by its column index.
    for (genvar c = 1; c < SA_COLS; c++) begin : GEN_SKEW_COLS
        operand_t b_shift_regs[0:c-1];

        always_ff @(posedge clk) begin
            if(!rst_n) begin
                for(int d = 0; d < c; d++)
                    b_shift_regs[d] <= '0;
            end else begin
                b_shift_regs[0] <= b_i[c];
                for(int d = 1; d < c; d++)
                    b_shift_regs[d] <= b_shift_regs[d-1];
            end
        end

        assign b_i_skewed[c] = b_shift_regs[c-1];
    end

endmodule