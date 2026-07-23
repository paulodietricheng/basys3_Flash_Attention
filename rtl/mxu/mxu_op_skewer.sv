`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/22/2026 02:24:39 PM
// Design Name: 
// Module Name: mxu_op_skewer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

import fa_pkg::*;

module mxu_op_skewer(
    input logic clk, rst_n,
    
    // From Operand Handler
    input operand_t a_j [0:SA_ROWS-1],
    input operand_t b_i [0:SA_COLS-1],
    input logic d_valid,    
    
    // To systolic array
    output operand_t a_j_skewed [0:SA_ROWS-1],
    output operand_t b_i_skewed [0:SA_COLS-1],
    
    // To systolic Control
    output logic pe00_valid
);
    
    // Row/col 0 has zero delay.
    always_comb begin
        if (!rst_n) begin
            a_j_skewed[0] = '0;
            b_i_skewed[0] = '0;
        end else begin
            a_j_skewed[0] = a_j[0];
            b_i_skewed[0] = b_i[0];
        end
    end
    
    assign pe00_valid = rst_n && d_valid;

    generate
        genvar row;
        for (row = 1; row < SA_ROWS; row++) begin : GEN_SKEW_ROWS

            // row `row` has exactly `row` registers.
            operand_t a_shift_regs [0:row-1];

            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    for (int d = 0; d < row; d++) begin
                        a_shift_regs[d] <= '0;
                    end
                end else begin
                    a_shift_regs[0] <= a_j[row];
                    for (int d = 1; d < row; d++) begin
                        a_shift_regs[d] <= a_shift_regs[d-1];
                    end
                end
            end
            assign a_j_skewed[row] = a_shift_regs[row-1];            
        end
    endgenerate
    
    generate
        genvar col;
        for (col = 1; col < SA_COLS; col++) begin : GEN_SKEW_COLS

            // row `col` has exactly `col` registers.
            operand_t b_shift_regs [0:col-1];

            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    for (int d = 0; d < col; d++) begin
                        b_shift_regs[d] <= '0;
                    end
                end else begin
                    b_shift_regs[0] <= b_i[col];
                    for (int d = 1; d < col; d++) begin
                        b_shift_regs[d] <= b_shift_regs[d-1];
                    end
                end
            end
            assign b_i_skewed[col] = b_shift_regs[col-1];            
        end
    endgenerate
    
endmodule
