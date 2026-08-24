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
    input logic clk,

    // Input data
    input sram_word_t din [NUM_BUF][NUM_PORTS],

    // Double buffer control
    input logic read_bank [NUM_BUF],

    // Write addresses
    input logic [SRAM_ADDR_W-1:0] wr_addr [NUM_BUF][NUM_PORTS],

    // Read addresses
    input logic [SRAM_ADDR_W-1:0] rd_addr [NUM_BUF][NUM_PORTS],

    // Output data
    output sram_word_t dout [NUM_BUF][NUM_PORTS],

    // Busy signals
    input logic mxu_using_mem,
    input logic vpu_using_mem,

    output logic busy [NUM_BUF]
);

    genvar i;
    generate
        for (i = 0; i < NUM_BUF; i++) begin : g_double_buf
            double_buf U_DB (
                .clk          (clk),
                .din          (din[i]),
                .read_bank    (read_bank[i]),
                .busy         (busy[i]),
                .dma_using_mem(dma_using_mem),
                .mxu_using_mem(mxu_using_mem),
                .vpu_using_mem(vpu_using_mem),
                .rd_addr      (rd_addr[i]),
                .wr_addr      (wr_addr[i]),
                .dout         (dout[i])
            );
        end
    endgenerate

endmodule
