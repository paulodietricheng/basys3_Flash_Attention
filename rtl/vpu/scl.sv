//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.08.2026 18:55:25
// Design Name: 
// Module Name: scl
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

module scl (
    input logic clk, rst_n,
    
    input logic start,
    output logic busy,
    output logic done,
    
    input accumulator_t in_vector [0:D_MODEL-1],
    input accumulator_t in_scalar,
    
    output accumulator_t out_vector [0:D_MODEL-1]
);

    // Parameters
    localparam NUM_ELEMENTS = 2;
    localparam NUM_ITERATIONS = D_MODEL / NUM_ELEMENTS;
    localparam NUM_I_W = $clog2(NUM_ITERATIONS);
    
    // registers
    accumulator_t reg_vector [0:D_MODEL-1];
    accumulator_t reg_scalar;

    logic [NUM_I_W-1:0] iteration;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy      <= 1'b0;
            done      <= 1'b0;
            iteration <= '0;
            reg_scalar <= '0;

            for (int i = 0; i < D_MODEL; i++) begin
                reg_vector[i] <= '0;
                out_vector[i] <= '0;
            end
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                busy       <= 1'b1;
                iteration  <= '0;
                reg_scalar <= in_scalar;

                // Latch input vector
                for (int i = 0; i < D_MODEL; i++) begin
                    reg_vector[i] <= in_vector[i];
                end
            end else if (busy) begin
                for (int j = 0; j < NUM_ELEMENTS; j++) begin
                    out_vector[iteration * NUM_ELEMENTS + j] <=
                    reg_vector[iteration * NUM_ELEMENTS + j] * reg_scalar;
                end
                // Last iteration
                if (iteration == NUM_ITERATIONS - 1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
                else begin
                    iteration <= iteration + 1'b1;
                end
            end
        end
    end  
endmodule