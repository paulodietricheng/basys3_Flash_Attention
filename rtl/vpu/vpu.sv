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
    // mxu
    input accumulator_t c [0:SA_ROWS-1][0:SA_COLS-1],
    input logic vpu_start,
    
    // Fetch V
    input operand_t V [0:SA_COLS-1][0:D_MODEL-1]
        
    // Output data o
    output operand_t O_N [0:SA_ROWS][0:D_MODEL]
);

endmodule