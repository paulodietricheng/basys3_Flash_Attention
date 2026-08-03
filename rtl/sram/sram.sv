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

module sram (
    input  logic clk,

    // Input data
    input  sram_word_t din_a [NUM_BUF],
    input  sram_word_t din_b [NUM_BUF],

    // Double buffer control
    input  logic read_bank [NUM_BUF],

    // Addresses
    input  logic [SRAM_ADDR_W-1:0] wr_addr_a [NUM_BUF],
    input  logic [SRAM_ADDR_W-1:0] wr_addr_b [NUM_BUF],
    input  logic [SRAM_ADDR_W-1:0] rd_addr_a [NUM_BUF],
    input  logic [SRAM_ADDR_W-1:0] rd_addr_b [NUM_BUF],

    // Output data
    output sram_word_t dout_a [NUM_BUF],
    output sram_word_t dout_b [NUM_BUF],

    // Busy signals
    input  logic mxu_using_mem [NUM_BUF],
    input  logic vpu_using_mem [NUM_BUF],
    input  logic dma_using_mem [NUM_BUF],

    output logic busy [NUM_BUF]
);

    genvar i;
    generate
        for (i = 0; i < NUM_BUF; i++) begin : g_double_buf
            double_buf u_double_buf (
                .clk          (clk),
                .din_a        (din_a[i]),
                .din_b        (din_b[i]),
                .read_bank    (read_bank[i]),
                .busy         (busy[i]),
                .dma_using_mem(dma_using_mem[i]),
                .mxu_using_mem(mxu_using_mem[i]),
                .vpu_using_mem(vpu_using_mem[i]),
                .rd_addr_a    (rd_addr_a[i]),
                .rd_addr_b    (rd_addr_b[i]),
                .wr_addr_a    (wr_addr_a[i]),
                .wr_addr_b    (wr_addr_b[i]),
                .dout_a       (dout_a[i]),
                .dout_b       (dout_b[i])
            );
        end
    endgenerate

endmodule
