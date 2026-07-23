`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/26/2026 09:55:26 AM
// Design Name: 
// Module Name: mxu
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

module mxu(
    
    input clk, rst_n,
    
    // Central control
    input  logic mxu_start,
    output logic mxu_done, 
    
    input  n_dim_t n,
    input  m_dim_t m,
    input  p_dim_t p,
    
    // to sram_control  
    output logic mxu_reading_ram,  
    
    // External wires for Operand handler
    input  operand_bus_t in_a,
    input  operand_bus_t in_b,
    output dim_t dim_to_fetch,
    
    // External wires for Systolic Array
    output accumulator_t c [0:SA_ROWS-1][0:SA_COLS-1],
    output accumulator_t row_max [0:SA_ROWS-1] 
);

    //-----------------------------------
    // mxu control initialization
    //-----------------------------------
    
    // Internal inputs for control
    logic pe00_valid;
    logic dim_valid;
    
    // Internal outputs fpr control
    logic array_en;
    logic clr_acc_n;
    dim_t dim_idx;
    
    mxu_ctrl U_MXU_CTRL (
        .clk       (clk),
        .rst_n     (rst_n),
        .mxu_start (mxu_start),
        .mxu_done  (mxu_done),
        .pe00_valid(pe00_valid),
        .array_en  (array_en),
        .clr_acc_n (clr_acc_n),
        .dim_idx   (dim_idx),
        .dim_valid (dim_valid),
        .n(n),
        .m(m),
        .p(p),
        .mxu_reading_ram(mxu_reading_ram)
    );
    
    //-----------------------------------
    // Operand Handler initialization
    //-----------------------------------
      
    // Internal outputs
    operand_t a_j [0:SA_ROWS-1];
    operand_t b_i [0:SA_COLS-1];
    logic d_valid;  
      
    assign using_buffer = d_valid;
    
    mxu_op_handler U_MXU_OPH (
        .clk      (clk),
        .rst_n    (rst_n),
        .dim_idx  (dim_idx),
        .dim_valid(dim_valid),
        .in_a     (in_a),
        .in_b     (in_b),
        .dim_to_fetch(dim_to_fetch),
        .a_j      (a_j),
        .b_i      (b_i),
        .d_valid  (d_valid)
    );
    
    //---------------------------------
    // Operand Skewer initialization
    //-----------------------------------
    
    // Internal outputs
    operand_t a_j_skewed [0:SA_ROWS-1];
    operand_t b_i_skewed [0:SA_COLS-1];
    
    mxu_op_skewer U_MXU_OPS (
        .clk       (clk),
        .rst_n     (rst_n),
        .a_j       (a_j),
        .b_i       (b_i),
        .d_valid   (d_valid),
        .a_j_skewed(a_j_skewed),
        .b_i_skewed(b_i_skewed),
        .pe00_valid(pe00_valid)
    );
    
    //-----------------------------------
    // Systolic Array initialization
    //-----------------------------------
    mxu_systolic_array U_MXU_SA (
        .clk       (clk),
        .rst_n     (rst_n),
        .array_en  (array_en),
        .clr_acc_n (clr_acc_n),
        .a_j_skewed(a_j_skewed),
        .b_i_skewed(b_i_skewed),
        .c         (c),
        .row_max   (row_max)
    );

endmodule
