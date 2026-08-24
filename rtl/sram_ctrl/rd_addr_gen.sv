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
    
    // From vpu_v_fetch
    input logic [V_IDX_W-1:0] vf_idx,
    
    // To sram
    output logic [SRAM_ADDR_W-1:0] rd_addr [NUM_BUF][NUM_PORTS]
);

    // Number of INT8 operands stored in one SRAM word.
    localparam int WPA_V = SRAM_WORD_W / OPERAND_W;

    // Number of SRAM addresses occupied by one complete V row.
    localparam int ADDR_PER_V = D_MODEL / WPA_V;
    
    always_comb begin
        rd_addr[0][0] = a_k_rd_idx << 1;
        rd_addr[0][1] = (a_k_rd_idx << 1) + 1;
        
        rd_addr[1][0] = b_k_rd_idx << 1;
        rd_addr[1][1] = (b_k_rd_idx << 1) + 1;
        
        for (int p = 0; p < NUM_PORTS; p++) begin
            rd_addr[2][p] = (vf_idx[V_IDX_W-1:1] * ADDR_PER_V)
                            + (vf_idx[0] * NUM_PORTS) + p;
        end
    end
   

endmodule
