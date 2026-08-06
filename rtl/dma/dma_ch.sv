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
module dma_ch (
    input logic clk, rst_n,

    // Requests
    input  dma_rq_t dma_rq,
    input  logic dma_start,
    output logic dma_busy,
    output logic dma_done,

    // HBM interface
    output logic [HBM_ADDR_W-1:0] hbm_addr [8],
    output bram_word_t hbm_din [8],
    input  bram_word_t hbm_dout [8],
    input  logic hbm_rvalid [8],

    // SRAM interface
    output logic [SRAM_ADDR_W-1:0] sram_addr [2],
    output sram_word_t sram_din [2],
    input  sram_word_t sram_dout [2],

    output logic dma_using_mem
);

    // Latch request
    dma_rq_t rq_reg;
    
    // Decode write enables from direction
    logic hbm_we;
    logic sram_we;
    
    always_comb begin
        hbm_we  <= rq_reg.direction;
        sram_we <= !rq_reg.direction;
    end
    
    // Register file for transpose
    logic [31:0] reg_file [8];
    
    // Despite not being the most efficient, the policy adopted 
    // for the DMA transpose is the following:
    // As there is an effective 4:1 production/absorption of data
    // betweem the hbm and the on chip sram, the transfer from hbm
    // to the dma register fille will occur once, and then the dimensions
    // will be drained 1 by cycle to fill the sram, stalling the hbm -> 
    // dma process. 
    
    // This policy was adopted to allow for the development of the 
    // MVP, which was stuck in this module. 
    
    // States declaration
    typedef enum logic [3:0] {
        d_IDLE,
        d_SETUP,
        
        // HBM -> SRAM op
        d_HBM_READ,
        d_ACCUM,
        d_SRAM_WRITE,
        
        // SRAM -> HBM op
        d_SRAM_READ,
        d_ACCUM_REV,
        d_HBM_WRITE,   
        
        d_DONE
    } dma_state_t;

    // FSM Control
    dma_state_t curr_state;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= d_IDLE;
            
            // Safe defaults
            dma_busy <= 1'b0;
            dma_done <= 1'b0;
            
            for (int i = 0; i < 8; i++) begin
                hbm_addr[i] <= '0;
                hbm_din [i] <= '0;
            end
            
            for (int i = 0; i < 2; i++) begin
                sram_addr[i] <= '0;
                sram_din [i] <= '0;
            end
            
            dma_using_mem <= '0;          
        end else begin
        
            // Safe defaults
            dma_busy <= 1'b0;
            dma_done <= 1'b0;
            
            for (int i = 0; i < 8; i++) begin
                hbm_addr[i] <= '0;
                hbm_din [i] <= '0;
            end
            
            for (int i = 0; i < 2; i++) begin
                sram_addr[i] <= '0;
                sram_din [i] <= '0;
            end
            
            dma_using_mem <= '0;  
            
            case (curr_state)
                d_IDLE : begin
                    if (dma_start) begin
                        rq_reg <= dma_rq;
                        curr_state <= d_SETUP;
                    end
                end
                
                d_SETUP : begin
                    dma_busy      <= 1'b1;
                    dma_using_mem <= 1'b1;
                                        
                    curr_state <= rq_reg.direction ? d_HBM_READ : d_SRAM_READ;
                end
                
                d_HBM_READ : begin
                    dma_busy      <= 1'b1;
                    dma_using_mem <= 1'b1;
                    
                    for (int i = 0; i < 8; i++) begin
                        hbm_addr[i] <= rq_reg.hbm_base_addr + 
                    end
                end
            endcase
        end
    end

endmodule