`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/20/2026 04:25:34 PM
// Design Name: 
// Module Name: pe
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

import tpu_pkg::*;

module pe (
    input  logic clk, rst_n, clr_acc_n,

    input  operand_t in_a, in_b,
    input  accumulator_t in_max,
    input  logic array_en,
    
    output operand_t out_a, out_b, 
    output accumulator_t out_max,  
    output accumulator_t c
);

    // Input Pipeline Stage
    operand_t areg, breg;
    accumulator_t maxreg;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            areg <= '0;
            breg <= '0;
            maxreg <= '0;
        end else if (array_en) begin
            areg <= in_a;
            breg <= in_b;
            maxreg <= in_max;
        end
    end
    
    // Pass registered outputs to next processing elements
    assign out_a = areg;
    assign out_b = breg;     

    // Dedicated MAC Core Stage
    (* use_dsp = "yes", multstyle = "dsp" *) 
    accumulator_t acc_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_reg <= '0;
        end else if (array_en) begin
            if (!clr_acc_n) begin
                acc_reg <= '0; 
            end else begin
                acc_reg <= acc_reg + (areg * breg);
            end
        end
    end
    
    assign c = acc_reg;
    
    // Compare incoming max to present accumulator
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out_max <= 32'h80000000;
        else if (array_en)
            out_max <= (maxreg > acc_reg) ? maxreg : acc_reg;
    end
       
endmodule
