`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: mxu_systolic_array
 * ============================================================================
 *
 *  Description:
 *      Implements the 2D systolic processing array used by the MXU.
 *
 *      The array is built from a grid of processing elements. A operands move
 *      horizontally across each row while B operands move vertically down each
 *      column. Each processing element multiplies its current A and B operands
 *      and accumulates the result locally.
 *
 *      Operation:
 *
 *          1. Skewed A operands enter from the left side of the array.
 *          2. Skewed B operands enter from the top of the array.
 *          3. Each PE forwards A to the next column and B to the next row.
 *          4. Each PE accumulates its local multiply result into c.
 *
 *      array_en enables computation and data propagation through the array.
 *      clr_acc_n clears the PE accumulators before a new matrix operation.
 *
 * Author: Paulo Dietrich
 * ============================================================================
 */

module mxu_systolic_array (
    input logic clk, rst_n,

    // control
    input logic array_en,
    input logic clr_acc_n,

    // operands
    input operand_t a_j_skewed[SA_ROWS],
    input operand_t b_i_skewed[SA_COLS],

    // outputs
    output accumulator_t c[SA_ROWS][SA_COLS]
);

    // Interconnect used to move A horizontally and B vertically through the array.
    operand_t inter_cols[SA_ROWS][SA_COLS+1];
    operand_t inter_rows[SA_ROWS+1][SA_COLS];

    // Connect the skewed operands to the left and top edges of the array.
    always_comb begin
        for(int j=0; j<SA_ROWS; j++)
            inter_cols[j][0] = a_j_skewed[j];

        for(int i=0; i<SA_COLS; i++)
            inter_rows[0][i] = b_i_skewed[i];
    end

    // Generate the 2D processing-element array.
    for(genvar j=0; j<SA_ROWS; j++) begin : GEN_ROW
        for(genvar i=0; i<SA_COLS; i++) begin : GEN_COL
            pe U_PE (
                .clk      (clk),
                .rst_n    (rst_n),
                .clr_acc_n(clr_acc_n),
                .array_en (array_en),
                .in_a     (inter_cols[j][i]),
                .in_b     (inter_rows[j][i]),
                .out_a    (inter_cols[j][i+1]),
                .out_b    (inter_rows[j+1][i]),
                .c        (c[j][i])
            );
        end
    end

endmodule