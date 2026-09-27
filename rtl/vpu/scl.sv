`timescale 1ns/1ps
import fa_pkg::*;
module scl (
    input logic clk, rst_n, start,
    output logic busy, done,
    input accumulator_t in_vector [D_MODEL],
    input accumulator_t in_scalar,
    output accumulator_t out_vector [D_MODEL]
);
    localparam int NUM_ELEMENTS = 2;
    localparam int NUM_ITERATIONS = (D_MODEL + NUM_ELEMENTS - 1)/NUM_ELEMENTS;
    localparam int ITER_W = (NUM_ITERATIONS > 1) ? $clog2(NUM_ITERATIONS) : 1;
    accumulator_t reg_vector[D_MODEL], reg_scalar;
    logic [ITER_W-1:0] iteration;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0; done <= 0; iteration <= 0; reg_scalar <= 0;
            for (int i=0; i<D_MODEL; i++) begin
                reg_vector[i] <= 0; out_vector[i] <= 0;
            end
        end else begin
            done <= 0;
            if (start && !busy) begin
                busy <= 1;
                iteration <= 0;
                reg_scalar <= in_scalar;
                reg_vector <= in_vector;
            end else if (busy) begin
                for (int lane=0; lane<NUM_ELEMENTS; lane++) begin
                    if (int'(iteration)*NUM_ELEMENTS+lane < D_MODEL)
                        out_vector[int'(iteration)*NUM_ELEMENTS+lane] <=
                            acc_mul(reg_vector[int'(iteration)*NUM_ELEMENTS+lane], reg_scalar);
                end
                if (iteration == ITER_W'(NUM_ITERATIONS-1)) begin
                    busy <= 0; done <= 1;
                end else iteration <= iteration + 1'b1;
            end
        end
    end
endmodule
