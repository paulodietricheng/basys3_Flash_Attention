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
    input  logic dmaA_wr_done,
    input  logic dmaB_wr_done,
    
    // From mxu_ctrl
    input logic mxu_reading_ram,
    
    // To double_buffer
    output logic bufA_read_ram,
    output logic bufB_read_ram,
    
    // ------------
    // rd_addr_gen
    // ------------
    
    // From operand_handler
    input  dim_t dim_to_fetch,
    
    // To sram
    output logic [ADDR_W-1:0] bufA_rd_addr_a,
    output logic [ADDR_W-1:0] bufA_rd_addr_b,
    output logic [ADDR_W-1:0] bufB_rd_addr_a,
    output logic [ADDR_W-1:0] bufB_rd_addr_b
);

    db_ctrl U_DBC (
        .clk(clk), 
        .rst_n(rst_n),
        .Atile_advance(Atile_advance),
        .dmaA_wr_done (dmaA_wr_done),
        .dmaB_wr_done (dmaB_wr_done),
        .bufA_read_ram(bufA_read_ram),
        .bufB_read_ram(bufB_read_ram),
        .mxu_reading_ram  (mxu_reading_ram)
    );
    
    rd_addr_gen U_RAG (
        .dim_to_fetch (dim_to_fetch),
        .bufA_rd_addr_a(bufA_rd_addr_a),
        .bufA_rd_addr_b(bufA_rd_addr_b),
        .bufB_rd_addr_a(bufB_rd_addr_a), 
        .bufB_rd_addr_b(bufB_rd_addr_b)
    );
    
endmodule
