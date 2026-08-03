`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.07.2026 16:08:36
// Design Name: 
// Module Name: double_buf
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

module double_buf(

    input logic clk,
    
    // DMA
    input logic dma_using_mem,
    input sram_word_t din_a,
    input sram_word_t din_b,
    input  logic [SRAM_ADDR_W-1:0] wr_addr_a,
    input  logic [SRAM_ADDR_W-1:0] wr_addr_b,
   
    // SRAM_Control
    input  logic read_bank,     // 0 = reads ram0, 1 = reads ram1
    output logic busy,
   
    // addr_gen
    input  logic [SRAM_ADDR_W-1:0] rd_addr_a,
    input  logic [SRAM_ADDR_W-1:0] rd_addr_b,
    
    // mxu
    input  logic mxu_using_mem,
    
    // vpu
    input  logic vpu_using_mem,
    
    // To Word Packer
    output sram_word_t dout_a,
    output sram_word_t dout_b
);

    assign busy = mxu_using_mem | vpu_using_mem | dma_using_mem;

    // intermediate ramx_dout wires
    sram_word_t bank0_dout_a;
    sram_word_t bank0_dout_b;
    sram_word_t bank1_dout_a;
    sram_word_t bank1_dout_b;
    
    // intermediate address wires
    logic [SRAM_ADDR_W-1:0] bank0_addr_a;
    logic [SRAM_ADDR_W-1:0] bank0_addr_b;
    logic [SRAM_ADDR_W-1:0] bank1_addr_a;
    logic [SRAM_ADDR_W-1:0] bank1_addr_b;
    
    // ping-pong rd/wr addressing
    always_comb begin
        if (read_bank) begin
            bank1_addr_a = rd_addr_a;
            bank1_addr_b = rd_addr_b;
            bank0_addr_a = wr_addr_a;
            bank0_addr_b = wr_addr_b;
        end else begin
            bank1_addr_a = wr_addr_a;
            bank1_addr_b = wr_addr_b;
            bank0_addr_a = rd_addr_a;
            bank0_addr_b = rd_addr_b;
        end
    end

    bram U_BANK0 (
        .clk   (clk),
        .din_a (din_a),
        .addr_a(bank0_addr_a),
        .we_a  (read_bank),
        .dout_a(bank0_dout_a),
        .din_b (din_b),
        .addr_b(bank0_addr_b),
        .we_b  (read_bank),
        .dout_b(bank0_dout_b)
    );
    
    bram U_BANK1 (
        .clk   (clk),
        .din_a (din_a),
        .addr_a(bank1_addr_a),
        .we_a  (~read_bank),
        .dout_a(bank1_dout_a),
        .din_b (din_b),
        .addr_b(bank1_addr_b),
        .we_b  (~read_bank),
        .dout_b(bank1_dout_b)
    );
    
    always_comb begin
        if (read_bank) begin
            dout_a = bank1_dout_a;
            dout_b = bank1_dout_b;
        end else begin
            dout_a = bank0_dout_a;
            dout_b = bank0_dout_b;
        end
    end
    
endmodule
