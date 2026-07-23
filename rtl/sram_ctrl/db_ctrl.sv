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
    input  logic Atile_advance,
    input  logic dmaA_wr_done,
    input  logic dmaB_wr_done,

    // From mxu_ctrl
    input  logic mxu_reading_ram,

    // To double_buffer
    output logic bufA_read_ram,
    output logic bufB_read_ram
);

    logic a_advance_pending;
    logic b_advance_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bufA_read_ram     <= 1'b0;
            bufB_read_ram     <= 1'b0;
            a_advance_pending <= 1'b0;
            b_advance_pending <= 1'b0;
        end else begin
            // latch the request
            if (dmaA_wr_done & Atile_advance)
                a_advance_pending <= 1'b1;

            if (dmaB_wr_done)
                b_advance_pending <= 1'b1;

            // fire the flip as soon as the MXU is clear of the ram
            if (a_advance_pending & !mxu_reading_ram) begin
                bufA_read_ram     <= ~bufA_read_ram;
                a_advance_pending <= 1'b0;
            end

            if (b_advance_pending & !mxu_reading_ram) begin
                bufB_read_ram     <= ~bufB_read_ram;
                b_advance_pending <= 1'b0;
            end
        end
    end

endmodule
