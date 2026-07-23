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
    
    // TBD
    input mxu_cmd_t mxu_cmd,
    
    // to sram_control  
    output logic mxu_reading_ram,  
    
    // External wires for Operand handler
    input  operand_bus_t in_a,
    input  operand_bus_t in_b,
    output k_dim_t a_k_rd_idx,
    output k_dim_t b_k_rd_idx,
    
    // External wires for Systolic Array
    output accumulator_t c [0:SA_ROWS-1][0:SA_COLS-1],
    output accumulator_t row_max [0:SA_ROWS-1] 
);

    //-----------------------------------
    // mxu control initialization
    //-----------------------------------
    
    // Internal inputs for control
    logic a_k_valid;
    logic b_k_valid;
    
    // Internal outputs fpr control
    logic array_en;
    logic clr_acc_n;
    k_dim_t a_k_idx;
    k_dim_t b_k_idx;
    
    mxu_ctrl U_MXU_CTRL (
        .clk            (clk),
        .rst_n          (rst_n),
        .mxu_start      (mxu_start),
        .mxu_done       (mxu_done),
        .mxu_cmd        (mxu_cmd),
        .array_en       (array_en),
        .clr_acc_n      (clr_acc_n),
        .a_k_idx        (a_k_idx),
        .b_k_idx        (b_k_idx),
        .a_k_valid      (a_k_valid),
        .b_k_valid      (b_k_valid),
        .mxu_reading_ram(mxu_reading_ram)
    );
    
    //-----------------------------------
    // Operand Handler initialization
    //-----------------------------------
      
    // Internal outputs
    operand_t a_j [0:SA_ROWS-1];
    operand_t b_i [0:SA_COLS-1];
          
    mxu_op_handler U_MXU_OPH (
        .clk       (clk),
        .rst_n     (rst_n),
        .a_k_idx   (a_k_idx),
        .b_k_idx   (b_k_idx),
        .a_k_valid (a_k_valid),
        .b_k_valid (b_k_valid),
        .in_a      (in_a),
        .in_b      (in_b),
        .a_k_rd_idx(a_k_rd_idx),
        .b_k_rd_idx(b_k_rd_idx),
        .a_j       (a_j),
        .b_i       (b_i)
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
        .a_j_skewed(a_j_skewed),
        .b_i_skewed(b_i_skewed)
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
