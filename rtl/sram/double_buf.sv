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
    input sram_word_t din_a,
    input sram_word_t din_b,
    input  logic read_ram,     // 0 = reads ram0, 1 = reads ram1
    input  logic [ADDR_W-1:0] wr_addr_a,
    input  logic [ADDR_W-1:0] wr_addr_b,
   
    // addr_gen
    input  logic [ADDR_W-1:0] rd_addr_a,
    input  logic [ADDR_W-1:0] rd_addr_b,
      
    // To Word Packer
    output sram_word_t dout_a,
    output sram_word_t dout_b
);

    // intermediate ramx_dout wires
    sram_word_t ram0_dout_a;
    sram_word_t ram0_dout_b;
    sram_word_t ram1_dout_a;
    sram_word_t ram1_dout_b;
    
    // intermediate address wires
    logic [ADDR_W-1:0] ram0_addr_a;
    logic [ADDR_W-1:0] ram0_addr_b;
    logic [ADDR_W-1:0] ram1_addr_a;
    logic [ADDR_W-1:0] ram1_addr_b;
    
    // ping-pong rd/wr addressing
    always_comb begin
        if (read_ram) begin
            ram1_addr_a = rd_addr_a;
            ram1_addr_b = rd_addr_b;
            ram0_addr_a = wr_addr_a;
            ram0_addr_b = wr_addr_b;
        end else begin
            ram1_addr_a = wr_addr_a;
            ram1_addr_b = wr_addr_b;
            ram0_addr_a = rd_addr_a;
            ram0_addr_b = rd_addr_b;
        end
    end

    bram U_RAM0 (
        .clk   (clk),
        .din_a (din_a),
        .addr_a(ram0_addr_a),
        .we_a  (read_ram),
        .dout_a(ram0_dout_a),
        .din_b (din_b),
        .addr_b(ram0_addr_b),
        .we_b  (read_ram),
        .dout_b(ram0_dout_b)
    );
    
    bram U_RAM1 (
        .clk   (clk),
        .din_a (din_a),
        .addr_a(ram1_addr_a),
        .we_a  (~read_ram),
        .dout_a(ram1_dout_a),
        .din_b (din_b),
        .addr_b(ram1_addr_b),
        .we_b  (~read_ram),
        .dout_b(ram1_dout_b)
    );
    
    always_comb begin
        if (read_ram) begin
            dout_a = ram1_dout_a;
            dout_b = ram1_dout_b;
        end else begin
            dout_a = ram0_dout_a;
            dout_b = ram0_dout_b;
        end
    end
    
endmodule
