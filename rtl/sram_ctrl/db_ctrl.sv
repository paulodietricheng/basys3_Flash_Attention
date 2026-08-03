`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08.07.2026 14:46:38
// Design Name: 
// Module Name: db_ctrl
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

module db_ctrl (
    input  logic clk, rst_n,

    // From Central control
    input  logic Q_tile_done,
    input  logic KV_tile_done,

    //double_buffer
    input  logic bufA_busy,
    input  logic bufB_busy,
    input  logic bufC_busy,
    input  logic bufD_busy,
    
    output logic bufA_read_bank,
    output logic bufB_read_bank,
    output logic bufC_read_bank,
    output logic bufD_read_bank
);
    // Switch buffers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bufA_read_bank <= '0;
            bufB_read_bank <= '0;
            bufC_read_bank <= '0;
            bufD_read_bank <= '0;
        end else begin
            if (Q_tile_done && !bufA_busy)
                bufA_read_bank <= ~bufA_read_bank;
            
            if (KV_tile_done && !(bufB_busy || bufC_busy)) begin
                bufB_read_bank <= ~bufB_read_bank;
                bufC_read_bank <= ~bufC_read_bank;
            end
            
            if(Q_tile_done && !bufD_busy)
                bufD_read_bank <= ~bufD_read_bank;
        end
    end

endmodule
