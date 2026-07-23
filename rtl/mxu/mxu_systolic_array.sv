`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/20/2026 05:20:36 PM
// Design Name: 
// Module Name: mxu_systolic_array
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

module mxu_systolic_array(
    // Signals
    input  clk, rst_n,
    
    // From Systolic Controll
    input logic array_en,
    input logic clr_acc_n,
    
    // Input operands
    input  operand_t a_j_skewed [0:SA_ROWS-1],
    input  operand_t b_i_skewed [0:SA_COLS-1],
     
    // Output accumulator
    output accumulator_t c [0:SA_ROWS-1][0:SA_COLS-1],
    
    // Output max
    output accumulator_t row_max [0:SA_ROWS-1] 
);

    // Interconnect fabric
    operand_t      inter_cols [0:SA_ROWS-1][0:SA_COLS];
    operand_t      inter_rows [0:SA_ROWS][0:SA_COLS-1];
    accumulator_t  inter_max  [0:SA_ROWS-1][0:SA_COLS];

    // Input data to the fabric
    always_comb begin        
        // Populate rows
        for(int j = 0; j < SA_ROWS; j++) begin
            inter_cols[j][0] = a_j_skewed[j];
            inter_max [j][0] = 32'h80000000;
        end
        
        // Populate columns
        for(int i = 0; i < SA_COLS; i++) begin
            inter_rows [0][i] = b_i_skewed[i];
        end
    end

    // Generate and connect PEs
    generate
        genvar i, j;
        for (j = 0; j < SA_COLS; j++) begin : GEN_COL
            for (i = 0; i < SA_ROWS; i++) begin : GEN_ROW                
                pe U_PE(
                    .clk  (clk),
                    .rst_n    (rst_n),
                    .clr_acc_n(clr_acc_n),
                    .array_en (array_en),
                    .in_a   (inter_cols[j][i]),
                    .in_b   (inter_rows[j][i]),
                    .in_max (inter_max[j][i]),
                    .out_a  (inter_cols[j][i+1]),
                    .out_b  (inter_rows[j+1][i]),
                    .out_max(inter_max[j][i+1]),
                    .c      (c[j][i])
                );
            end
        end
    endgenerate

    always_comb begin
        for (int j = 0; j < SA_ROWS; j++) begin
            row_max[j] = inter_max[j][SA_ROWS];
        end
    end

endmodule
