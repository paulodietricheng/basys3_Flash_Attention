`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.08.2026 16:10:14
// Design Name: 
// Module Name: vpu
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

//import fa_pkg::*;

module vpu (
    input clk, rst_n,

    // mxu
    input accumulator_t c [0:SA_ROWS-1][0:SA_COLS-1],
    input logic vpu_start,
    
    // Fetch V_tile
    input operand_t V [0:SA_COLS-1][0:D_MODEL-1],
    // SRAM ADDRESSING
    
    // Output data o
    output operand_t O_N [0:SA_ROWS][0:D_MODEL]
);

    //REGISTERS
    accumulator_t m_i         [SA_ROWS];
    accumulator_t m_i_minus_1 [SA_ROWS];

    // Current / previous denominator
    accumulator_t d_i         [SA_ROWS];
    accumulator_t d_i_minus_1 [SA_ROWS];

    // Current / previous output accumulation
    accumulator_t o_i         [0:D_MODEL-1][SA_ROWS];
    accumulator_t o_i_minus_1 [0:D_MODEL-1][SA_ROWS];

    // Normalized output
    accumulator_t o_norm [0:D_MODEL-1][SA_ROWS];
    
    typedef enum logic [1:0]{
        v_IDLE,
        v_NEXT_ROW,
        v_COMPUTE,
        v_DONE
    } vpu_state_t ;
    
    // Row index
    localparam ROW_IDX_W = $clog2(SA_ROWS);
    logic [ROW_IDX_W-1:0] row_idx;

    // vpu_row instantiation
    // control
    logic vpu_row_start;
    logic vpu_row_done;
    
    // Input row
    accumulator_t x_i [0:SA_COLS-1];

    // Current / previous running maximum
    accumulator_t in_m_i;
    accumulator_t in_m_i_minus_1;

    // Current / previous denominator
    accumulator_t in_d_i;
    accumulator_t in_d_i_minus_1;

    // Reciprocal of final denominator
    accumulator_t in_d_inv;

    // Current / previous output accumulation
    accumulator_t in_o_i         [0:D_MODEL-1];
    accumulator_t in_o_i_minus_1 [0:D_MODEL-1];
    
    // Current / previous running maximum
    accumulator_t out_m_i;
    accumulator_t out_m_i_minus_1;

    // Current / previous denominator
    accumulator_t out_d_i;
    accumulator_t out_d_i_minus_1;

    // Reciprocal of final denominator
    accumulator_t out_d_inv;

    // Current / previous output accumulation
    accumulator_t out_o_i         [0:D_MODEL-1];
    accumulator_t out_o_i_minus_1 [0:D_MODEL-1];

    // Normalized output
    accumulator_t out_o_norm [0:D_MODEL-1];
    
    // V_tile_register
    operand_t V_reg [0:SA_COLS-1][0:D_MODEL-1];
    
    // Latch V_tile
    always_ff @(posedge clk) begin
        if (vpu_start)
            V_reg <= V;
    end
    
endmodule