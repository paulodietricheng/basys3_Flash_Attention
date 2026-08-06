`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/05/2026 17:10:26 AM
// Design Name: 
// Module Name: dma
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
module dma (
    input logic clk, rst_n,

    // Requests
    input dma_rq_t rq [DMA_CH],
    input logic dma_start [DMA_CH],

    output logic dma_done [DMA_CH],

    // HBM interface
    output logic hbm_we [DMA_CH],
    output logic [HBM_ADDR_W-1:0] hbm_addr [DMA_CH],
    output bram_word_t hbm_wdata [DMA_CH],
    input  bram_word_t hbm_rdata [DMA_CH],

    // SRAM interface
    output logic [SRAM_ADDR_W-1:0] sram_wr_addr [NUM_BUF],
    output logic [SRAM_ADDR_W-1:0] sram_rd_addr [NUM_BUF],
    output sram_word_t sram_din_a  [NUM_BUF],
    output sram_word_t sram_din_b  [NUM_BUF],
    input  sram_word_t sram_dout_a [NUM_BUF],
    input  sram_word_t sram_dout_b [NUM_BUF],

    output logic dma_using_mem [NUM_BUF]
);

endmodule