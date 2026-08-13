//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.08.2026 18:55:25
// Design Name: 
// Module Name: exp
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

module exp (
    input  logic clk, rst_n,
    
    input  logic start,
    output logic busy,
    output logic done,
    
    input  logic [31:0] in,
    output logic [31:0] out
);
    // Register the request
    logic [31:0] in_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            in_reg <= 1'b0;
        else if (start)
            in_reg <= in;
    end
    
    // Placeholder computation
    always_ff @(posedge clk) begin
        out <= (in_reg << 1) + 1;
        done <= 1'b1;
    end    

endmodule