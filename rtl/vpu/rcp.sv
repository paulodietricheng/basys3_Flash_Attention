`timescale 1ns/1ps
// PLACEHOLDER: preserves the supplied in-2 function. Not reciprocal.
module rcp (
    input logic clk, rst_n, start,
    output logic busy, done,
    input logic [31:0] in,
    output logic [31:0] out
);
    typedef enum logic [1:0] {IDLE, COMPUTE, FINISH} state_t;
    state_t state;
    logic [31:0] in_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; busy <= 0; done <= 0; out <= 0; in_reg <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: if (start) begin in_reg <= in; busy <= 1; state <= COMPUTE; end
                COMPUTE: begin out <= in_reg - 32'd2; state <= FINISH; end
                FINISH: begin busy <= 0; done <= 1; state <= IDLE; end
                default: begin state <= IDLE; busy <= 0; end
            endcase
        end
    end
endmodule
