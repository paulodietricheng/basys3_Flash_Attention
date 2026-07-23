`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.07.2026 15:45:05
// Design Name: 
// Module Name: bram
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


module bram(

    input logic clk,
    
    // Port A
    input  logic [31:0] din_a,
    input  logic [9:0]  addr_a,
    
    input  logic        we_a,
    
    output logic [31:0] dout_a,
    
    // Port B
    input  logic [31:0] din_b,
    input  logic [9:0]  addr_b,
    
    input  logic        we_b,
    
    output logic [31:0] dout_b
);

    logic [31:0] mem [0:2**10 - 1];

    // Port A
    always_ff @(posedge clk) begin
        if (we_a) 
            mem[addr_a] <= din_a;
        dout_a <= mem [addr_a];
    end
    
    // Port B
    always_ff @(posedge clk) begin
        if (we_b) 
            mem[addr_b] <= din_b;
        dout_b <= mem [addr_b];
    end
    
endmodule
