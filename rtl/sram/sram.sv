`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.07.2026 15:58:15
// Design Name: 
// Module Name: sram
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

module sram(
 
    input  logic clk,
    
    // DMA wires
    input sram_word_t dinA_a,
    input sram_word_t dinA_b,
    input sram_word_t dinB_a,
    input sram_word_t dinB_b,
    
    input  logic bufA_read_ram,     // 0 = reads ram0, 1 = reads 
    input  logic bufB_read_ram,     // 0 = reads ram0, 1 = reads 
    
    input  logic [ADDR_W-1:0] bufA_wr_addr_a,
    input  logic [ADDR_W-1:0] bufA_wr_addr_b,
    input  logic [ADDR_W-1:0] bufB_wr_addr_a,
    input  logic [ADDR_W-1:0] bufB_wr_addr_b,
    input  logic [ADDR_W-1:0] bufA_rd_addr_a,
    input  logic [ADDR_W-1:0] bufA_rd_addr_b,
    input  logic [ADDR_W-1:0] bufB_rd_addr_a,
    input  logic [ADDR_W-1:0] bufB_rd_addr_b,
    
    // To Word Packer
    output sram_word_t bufA_dout_a,
    output sram_word_t bufA_dout_b,
    output sram_word_t bufB_dout_a,
    output sram_word_t bufB_dout_b
);

    // Initialize buffers
    double_buf U_BUFA (
        .clk(clk),
        .din_a(dinA_a),
        .din_b(dinA_b),
        .read_ram(bufA_read_ram),
        .rd_addr_a(bufA_rd_addr_a),
        .rd_addr_b(bufA_rd_addr_b),
        .wr_addr_a(bufA_wr_addr_a),
        .wr_addr_b(bufA_wr_addr_b),
        .dout_a(bufA_dout_a),
        .dout_b(bufA_dout_b)
    );
    
    double_buf U_BUFB (
        .clk(clk),
        .din_a(dinB_a),
        .din_b(dinB_b),
        .read_ram(bufB_read_ram),
        .rd_addr_a(bufB_rd_addr_a),
        .rd_addr_b(bufB_rd_addr_b),
        .wr_addr_a(bufB_wr_addr_a),
        .wr_addr_b(bufB_wr_addr_b),
        .dout_a(bufB_dout_a),
        .dout_b(bufB_dout_b)
    );
endmodule
