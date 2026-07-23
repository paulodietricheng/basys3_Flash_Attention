`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/24/2026 09:54:48 AM
// Design Name: 
// Module Name: mxu_op_handler
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

import tpu_pkg::*;

module mxu_op_handler (
    input  logic clk, rst_n,
    
    // From MXU Control:
    input  dim_t dim_idx,
    input  logic dim_valid,
    
    // SRAM
    input  operand_bus_t in_a,
    input  operand_bus_t in_b,
    
    // DMA
    output dim_t dim_to_fetch,
    
    // To operand skewer
    output operand_t a_j [0:SA_ROWS-1],
    output operand_t b_i [0:SA_COLS-1],
    output logic d_valid
);

    // Generate dimensional base address
    assign dim_to_fetch = dim_idx;
    
    // Assert the validity of the data
    assign d_valid = dim_valid;
    
    // slice incoming vectors / output 0 for invalid dimentions
    generate
    genvar row;
        for (row = 0; row < SA_ROWS; row++) begin : GEN_ROW_SLICER
            always_comb begin
                if (d_valid) begin
                    a_j[row] = in_a [8*row + 7 : 8*row];     
                end else begin
                    a_j[row] = '0;
                end   
            end
        end        
    endgenerate
    
    generate
    genvar col;
        for (col = 0; col < SA_COLS; col++) begin : GEN_COL_SLICER
            always_comb begin
                if (d_valid) begin
                    b_i[col] = in_b [8*col + 7 : 8*col];     
                end else begin
                    b_i[col] = '0;
                end   
            end
        end        
    endgenerate

endmodule
