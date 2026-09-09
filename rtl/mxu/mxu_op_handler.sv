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

import fa_pkg::*;

module mxu_op_handler (   
    input logic clk, rst_n,
    
    // From MXU Control:
    input  k_dim_t a_k_idx,
    input  k_dim_t b_k_idx,
    input  logic   a_k_valid,
    input  logic   b_k_valid,
    
    // SRAM
    input  operand_t in_a [SA_ROWS],
    input  operand_t in_b [SA_COLS],
    
    // rd_addr_gen
    output k_dim_t a_k_rd_idx,
    output k_dim_t b_k_rd_idx,
    
    // To operand skewer
    output operand_t a_j [SA_ROWS],
    output operand_t b_i [SA_COLS]
);

    // Registered valid signal to account for 1 cycle sram read latency
    logic a_k_valid_d;
    logic b_k_valid_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_k_valid_d <= 1'b0;
            b_k_valid_d <= 1'b0;
        end else begin
            a_k_valid_d <= a_k_valid;
            b_k_valid_d <= b_k_valid;
        end
    end
    
    // Generate dimensional base address
    assign a_k_rd_idx = a_k_idx;
    assign b_k_rd_idx = b_k_idx;
    
    
    // Forward incoming vectors / output 0 for invalid dimentions
    genvar row;
    generate
        for (row = 0; row < SA_ROWS; row++) begin : GEN_ROW_SLICER
            always_comb begin
                if (a_k_valid_d)
                    a_j[row] = in_a[row];
                else
                    a_j[row] = '0;
            end
        end
    endgenerate

    genvar col;
    generate
        for (col = 0; col < SA_COLS; col++) begin : GEN_COL_SLICER
            always_comb begin
                if (b_k_valid_d)
                    b_i[col] = in_b[col];
                else
                    b_i[col] = '0;
            end
        end
    endgenerate

endmodule
