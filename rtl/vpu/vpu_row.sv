`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.08.2026 17:39:14
// Design Name: 
// Module Name: vpu_row
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

//import fa_pkg::*;

//module vpu_row (
//    input logic clk, rst_n,

//    // MXU
//    input logic mxu_done,
//    input accumulator_t scores [0:SA_COLS-1],
//    input accumulator_t row_max,
//    input accumulator_t row_sum,
    
//    // Control
//    input logic last_kv_tile,
//    output logic done,

//    // SRAM
//    input operand_t V_tile [0:SA_COLS-1][0:D_MODEL-1],
//    output accumulator_t O_row [0:D_MODEL-1]
//);

//    // Registers
//    accumulator_t m_reg;
//    accumulator_t l_reg;
//    accumulator_t O_reg[0:D_MODEL-1];
    
//    accumulator_t m_next;
//    accumulator_t l_next;
//    accumulator_t O_next[0:D_MODEL-1];

//    logic update_done;

//    vpu_softmax softmax (
//        .clk(clk),
//        .rst(rst),
//        .valid(mxu_done),
//        .m_old(m_reg),
//        .l_old(l_reg),
//        .row_max(row_max),
//        .row_sum(row_sum),
//        .m_new(m_next),
//        .l_new(l_next),
//        .alpha(alpha),
//        .done(softmax_done)
//    );


//    vpu_accum accum (
//        .clk(clk),
//        .rst_n(rst_n),
//        .valid(softmax_done),
//        .alpha(alpha),
//        .scores(scores),
//        .V_tile(V_tile),
//        .O_old(O_reg),
//        .O_new(O_next),
//        .done(accum_done)
//    );


//    always_ff @(posedge clk) begin
//        if(!rst_n) begin
//            m_reg <= '0;
//            l_reg <= '0;
            
//            for(int i=0; i < D_MODEL; i++)
//                O_reg[i] <= '0;
                
//            done <= 0;
//        end else begin
//            done <= 0;
//            if(accum_done) begin

//                m_reg <= m_next;
//                l_reg <= l_next;

//                for(int i=0;i<D_MODEL;i++)
//                    O_reg[i] <= O_next[i];
                    
//                if(last_kv_tile)
//                    done <= 1;
//            end
//        end
//    end

//    assign O_row = O_reg;

//endmodule