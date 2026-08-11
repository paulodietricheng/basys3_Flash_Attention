`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.07.2026 18:55:25
// Design Name: 
// Module Name: sram_ctrl
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

module sram_ctrl (
    input logic clk, rst_n,
    
    // -----------
    // db_control
    // -----------
    
    // From tr_control
    input  logic Atile_advance,
    
    // From dma
    input  logic dma_chA_done,
    input  logic dma_chB_done,
    
    // From mxu_ctrl
    input logic mxu_reading_ram,
    
    // To double_buffer
    output logic bufA_read_ram,
    output logic bufB_read_ram,
    output logic bufC_read_ram,
    output logic bufD_read_ram,
    
    // ------------
    // rd_addr_gen
    // ------------
    
    // From operand_handler
    input  k_dim_t a_k_rd_idx,
    input  k_dim_t b_k_rd_idx,
    
    // To sram
    output logic [SRAM_ADDR_W-1:0] rd_addr [NUM_BUF][NUM_PORTS]

);

    db_ctrl U_DBC (
        .clk(clk), 
        .rst_n(rst_n),
        .Atile_advance(Atile_advance),
        .dma_chA_done (dma_chA_done),
        .dma_chB_done (dma_chB_done),
        .bufA_read_ram(bufA_read_ram),
        .bufB_read_ram(bufB_read_ram),
        .bufC_read_ram(bufA_read_ram),
        .bufD_read_ram(bufB_read_ram),
        .mxu_reading_ram  (mxu_reading_ram)
    );
    
    rd_addr_gen U_RAG (
        .a_k_rd_idx    (a_k_rd_idx),
        .a_k_rd_idx    (a_k_rd_idx),
        .bufA_rd_addr_a(bufA_rd_addr_a),
        .bufA_rd_addr_b(bufA_rd_addr_b),
        .bufB_rd_addr_a(bufB_rd_addr_a), 
        .bufB_rd_addr_b(bufB_rd_addr_b)
    );
    
endmodule
