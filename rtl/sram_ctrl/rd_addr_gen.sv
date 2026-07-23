`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08.07.2026 14:41:43
// Design Name: 
// Module Name: rd_addr_gen
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

module rd_addr_gen (

    // From operand_handler
    input  k_dim_t a_k_rd_idx,
    input  k_dim_t b_k_rd_idx,
    
    // To sram
    output logic [ADDR_W-1:0] bufA_rd_addr_a,
    output logic [ADDR_W-1:0] bufA_rd_addr_b,
    output logic [ADDR_W-1:0] bufB_rd_addr_a,
    output logic [ADDR_W-1:0] bufB_rd_addr_b
);
    always_comb begin
        bufA_rd_addr_a = a_k_rd_idx << 1;
        bufA_rd_addr_b = (a_k_rd_idx << 1) + 1;
        bufB_rd_addr_a = b_k_rd_idx << 1;
        bufB_rd_addr_b = (b_k_rd_idx << 1) + 1;
    end
endmodule
