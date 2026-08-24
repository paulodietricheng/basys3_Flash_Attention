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

//    // DMA
//    input logic dma_using_mem,
    input sram_word_t din [NUM_PORTS],
    input logic [SRAM_ADDR_W-1:0] wr_addr [NUM_PORTS],

    // SRAM_Control
    input logic read_bank,
    output logic busy,

    // addr_gen
    input logic [SRAM_ADDR_W-1:0] rd_addr [NUM_PORTS],

    // mxu
    input logic mxu_using_mem,

    // vpu
    input logic vpu_using_mem,

    // To Word Packer
    output sram_word_t dout [NUM_PORTS]
);

    assign busy = mxu_using_mem | vpu_using_mem;

    sram_word_t bank0_dout [NUM_PORTS];
    sram_word_t bank1_dout [NUM_PORTS];

    logic [SRAM_ADDR_W-1:0] bank0_addr [NUM_PORTS];
    logic [SRAM_ADDR_W-1:0] bank1_addr [NUM_PORTS];

    // Ping-pong read/write addressing.
    always_comb begin
        for (int p = 0; p < NUM_PORTS; p++) begin
            if (read_bank) begin
                bank1_addr[p] = rd_addr[p];
                bank0_addr[p] = wr_addr[p];
            end else begin
                bank1_addr[p] = wr_addr[p];
                bank0_addr[p] = rd_addr[p];
            end
        end
    end

    bram U_BANK0 (
        .clk   (clk),
        .din_a (din[0]),
        .addr_a(bank0_addr[0]),
        .we_a  (read_bank),
        .dout_a(bank0_dout[0]),
        .din_b (din[1]),
        .addr_b(bank0_addr[1]),
        .we_b  (read_bank),
        .dout_b(bank0_dout[1])
    );

    bram U_BANK1 (
        .clk   (clk),
        .din_a (din[0]),
        .addr_a(bank1_addr[0]),
        .we_a  (~read_bank),
        .dout_a(bank1_dout[0]),
        .din_b (din[1]),
        .addr_b(bank1_addr[1]),
        .we_b  (~read_bank),
        .dout_b(bank1_dout[1])
    );

    always_comb begin
        for (int p = 0; p < NUM_PORTS; p++) begin
            dout[p] = read_bank ? bank1_dout[p] : bank0_dout[p];
        end
    end

endmodule
