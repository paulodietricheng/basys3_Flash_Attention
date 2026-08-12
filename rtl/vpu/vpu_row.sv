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

import fa_pkg::*;

module vpu_row (
    input logic clk, rst_n,

    // MXU
    input accumulator_t x_i [0:SA_COLS-1],

    // Control
    input  logic vpu_row_start,
    output logic vpu_row_done,

    // V matrix
    input operand_t V_i [0:SA_COLS-1][0:D_MODEL-1],

    // Output
    output operand_t O_N [0:D_MODEL-1]
);

    // Constants
    localparam accumulator_t NEG_INF = 32'hFF800000;
    localparam int COL_IDX_W = $clog2(SA_COLS);

    // Running state
    // m_i        : current running maximum
    // m_i_minus_1: previous running maximum
    //
    // d_i        : current running denominator
    // d_i_minus_1: previous running sum
    //
    // o_i        : current running output
    // o_i_minus_1: previous running output
    //
    // o_norm: normalized output

    accumulator_t m_i;
    accumulator_t m_i_minus_1;

    accumulator_t d_i;
    accumulator_t d_i_minus_1;

    accumulator_t o_i         [0:D_MODEL-1];
    accumulator_t o_i_minus_1 [0:D_MODEL-1];

    accumulator_t o_norm [0:D_MODEL-1];


    // Row iteration
    logic [COL_IDX_W-1:0] col_idx;

    accumulator_t x_cur;
    operand_t     V_cur [0:D_MODEL-1];

    assign x_cur = x_i[col_idx];

    // Exponential datapath
    accumulator_t max_diff;
    accumulator_t safe_diff;

    accumulator_t exp_max_diff;
    accumulator_t exp_safe_diff;

    logic exp_max_start;
    logic exp_safe_start;
    logic exp_busy;

    logic exp_max_done;
    logic exp_safe_done;

    assign max_diff  = m_i_minus_1 - m_i;
    assign safe_diff = x_cur - m_i;

    exp U_EXP_MAX (
        .clk  (clk),
        .rst_n(rst_n),
        .start(exp_max_start),
        .in   (max_diff),
        .out  (exp_max_diff),
        .done (exp_max_done)
    );

    exp U_EXP_SAFE (
        .clk  (clk),
        .rst_n(rst_n),
        .start(exp_safe_start),
        .in   (safe_diff),
        .out  (exp_safe_diff),
        .done (exp_safe_done)
    );
    
    // Scaling constants
    accumulator_t alpha;
    accumulator_t beta;

    assign alpha = d_i_minus_1 * exp_max_diff;
    assign beta  = exp_safe_diff;

    accumulator_t o_scaled [0:D_MODEL-1];
    accumulator_t v_scaled [0:D_MODEL-1];

    always_comb begin
        for (int j = 0; j < D_MODEL; j++) begin
            o_scaled[j] = alpha * o_i_minus_1[j];
            v_scaled[j] = beta * V_cur[j];
        end
    end

    // Reciprocal unit d_inv = 1 / d_i
    accumulator_t d_inv;

    logic recip_start;
    logic recip_done;
    logic recip_busy;

    reciprocal U_RECIP (
        .clk  (clk),
        .rst_n(rst_n),
        .start(recip_start),
        .in   (d_i),
        .out  (d_inv),
        .done (recip_done)
    );

    // States
    typedef enum logic [3:0] {
        v_IDLE,
        v_NEW_X,
        v_MAX,
        v_EXP,
        v_UPDATE_D,
        v_UPDATE_O,
        v_UPDATE_REG,
        v_RCP,
        v_NORM,
        v_ROW_DONE
    } vpu_state_t;

    vpu_state_t curr_state;

    // FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_i         <= NEG_INF;
            m_i_minus_1 <= NEG_INF;
            
            d_i <= '0; 
            d_i_minus_1 <= '0;
            
            for (int i = 0; i < D_MODEL; i++) begin 
                o_i [i] <= '0; 
                o_i_minus_1 [i] <= '0;
                o_norm [i] <= '0;
            end
            
            col_idx <= '0;
            vpu_row_done <= 1'b0;
            exp_safe_start <= 1'b0;
            exp_max_start <= 1'b0;
            recip_start <= 1'b0;
        end else begin
            
            case (curr_state)
                v_IDLE: begin
                    curr_state <= vpu_row_start ? v_MAX : v_IDLE;
                    col_idx <= '0;
                    vpu_row_done <= 1'b0;
                    exp_safe_start <= 1'b0;
                    exp_max_start  <= 1'b0;
                    recip_start <= 1'b0;
                end
                
                v_NEW_X: begin
                    col_idx <= col_idx + 1;
                    curr_state <= v_MAX;
                end
                
                v_MAX: begin
                    m_i <= (x_i[col_idx] > m_i_minus_1) ? x_i[col_idx] : m_i_minus_1;
                    curr_state <= v_EXP;
                end
                
                v_EXP: begin
                    if (!exp_busy) begin
                        exp_safe_start <= 1'b1;
                        exp_max_start <= 1'b1;
                        exp_busy <= 1'b1;
                    end else
                        exp_busy <= 1'b1;
                    
                    if (exp_max_done && exp_safe_done) begin
                        curr_state <= v_UPDATE_D;
                        exp_busy <= 1'b0;
                    end else
                        curr_state <= v_EXP;
                end      
                
                v_UPDATE_D: begin
                    d_i <= alpha + beta;
                    curr_state <= v_UPDATE_O;
                end          
                
                v_UPDATE_O: begin
                    for (int i = 0; i < D_MODEL; i++) begin 
                        o_i [i] <= o_scaled [i] + v_scaled [i]; 
                    end 
                    
                    curr_state <= v_UPDATE_REG;                
                end
                
                v_UPDATE_REG: begin
                    m_i_minus_1 <= m_i;
                    d_i_minus_1 <= d_i;
                    o_i_minus_1 <= o_i;
                    
                    if (col_idx == (SA_COLS-1))
                        curr_state <= v_RCP;
                    else
                        curr_state <= v_NEW_X;
                end
                
                v_RCP: begin
                    if (!exp_busy) begin
                        recip_start <= 1'b1;
                        recip_busy <= 1'b1;
                    end else
                        recip_busy <= 1'b1;
                    if (recip_done) begin
                        curr_state <= v_NORM;
                        recip_busy <= 1'b0;
                    end else
                        curr_state <= v_RCP;
                end
                
                v_NORM: begin
                    for (int i = 0; i < D_MODEL; i++) begin
                        o_norm [i] <= o_i [i] * d_inv;
                    end  
                end
                
                v_ROW_DONE: begin
                    vpu_row_done <= 1'b1;
                    O_N <= o_norm;
                    
                    curr_state <= v_IDLE;
                end           
            endcase         
        end
    end
endmodule