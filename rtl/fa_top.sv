`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.07.2026 19:19:14
// Design Name: 
// Module Name: fa_top
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

module fa_top(
    input clk, rst_n    
);

    // -----------------
    // MXU declaration
    // -----------------
    
    // External signals for central control
    logic mxu_start;
    logic mxu_busy;
    logic mxu_done;  
    logic mxu_reading_ram;
    
    // External wires for Operand handler
    operand_bus_t in_a;
    operand_bus_t in_b;   
    dim_t dim_to_fetch;
    
    assign in_a = {bufA_dout_b, bufA_dout_a};
    assign in_b = {bufB_dout_b, bufB_dout_a};
    
    // External wires for Systolic Array
    accumulator_t c [0:SA_ROWS-1][0:SA_COLS-1];
    accumulator_t row_max [0:SA_ROWS-1];
    
    mxu U_MXU (
        .clk(clk),
        .rst_n(rst_n),
        .mxu_start(start),
        .mxu_busy(busy),
        .mxu_done(done),
        .in_a(in_a),
        .in_b(in_b),
        .dim_to_fetch(dim_to_fetch),
        .c(c),
        .row_max(row_max),
        .mxu_reading_ram(mxu_reading_ram)
    );

    // ------------------
    // SRAM declaration
    // ------------------

    // SRAM data input
    sram_word_t dinA_a;
    sram_word_t dinA_b;
    sram_word_t dinB_a;
    sram_word_t dinB_b;
    
    // SRAM data address
    logic [ADDR_W-1:0] bufA_rd_addr_a;
    logic [ADDR_W-1:0] bufA_rd_addr_b;
    logic [ADDR_W-1:0] bufB_rd_addr_a;
    logic [ADDR_W-1:0] bufB_rd_addr_b;
    logic [ADDR_W-1:0] bufA_wr_addr_a;
    logic [ADDR_W-1:0] bufA_wr_addr_b;
    logic [ADDR_W-1:0] bufB_wr_addr_a;
    logic [ADDR_W-1:0] bufB_wr_addr_b;
    
    // SRAM controller
    logic bufA_read_ram;
    logic bufB_read_ram;
    
    // SRAM data output 
    sram_word_t bufA_dout_a;
    sram_word_t bufA_dout_b;
    sram_word_t bufB_dout_a;
    sram_word_t bufB_dout_b;
    
    sram U_SRAM (
        .clk(clk),
        .dinA_a(dinA_a),
        .dinA_b(dinA_b),
        .dinB_a(dinB_a),
        .dinB_b(dinB_b),
        .bufA_read_ram(bufA_read_ram),
        .bufB_read_ram(bufB_read_ram),
        .bufA_rd_addr_a(bufA_rd_addr_a),
        .bufA_rd_addr_b(bufA_rd_addr_b),
        .bufB_rd_addr_a(bufB_rd_addr_a),
        .bufB_rd_addr_b(bufB_rd_addr_b),
        .bufA_wr_addr_a(bufA_wr_addr_a),
        .bufA_wr_addr_b(bufA_wr_addr_b),
        .bufB_wr_addr_a(bufB_wr_addr_a),
        .bufB_wr_addr_b(bufB_wr_addr_b), 
        .bufA_dout_a(bufA_dout_a),  
        .bufA_dout_b(bufA_dout_b),  
        .bufB_dout_a(bufB_dout_a),  
        .bufB_dout_b(bufB_dout_b)  
    );
    
    // -----------------------------
    // sram_controller declaration
    // -----------------------------
    
    logic Atile_advance;
    logic dmaB_wr_done;
    
    sram_ctrl U_SCTRL (
        .clk(clk),
        .rst_n(rst_n),
        .Atile_advance  (Atile_advance),
        .dmaB_wr_done   (dmaB_wr_done),
        .mxu_reading_ram(mxu_reading_ram),
        .bufA_read_ram  (bufA_read_ram),
        .bufB_read_ram  (bufB_read_ram),
        .dim_to_fetch   (dim_to_fetch),
        .bufA_rd_addr_a (bufA_rd_addr_a),
        .bufA_rd_addr_b (bufA_rd_addr_b),
        .bufB_rd_addr_a (bufB_rd_addr_a),
        .bufB_rd_addr_b (bufB_rd_addr_b)
    );

endmodule
