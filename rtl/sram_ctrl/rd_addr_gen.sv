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
    output logic [SRAM_ADDR_W-1:0] rd_addr [NUM_BUF][NUM_PORTS]
);
    always_comb begin
        rd_addr[0][0] = a_k_rd_idx << 1;
        rd_addr[0][1] = (a_k_rd_idx << 1) + 1;
        
        rd_addr[1][0] = b_k_rd_idx << 1;
        rd_addr[1][1] = (b_k_rd_idx << 1) + 1;
    end
    
    // Add logic for VPU
endmodule
