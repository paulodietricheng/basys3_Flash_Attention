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
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

import fa_pkg::*;

module vpu_row (
    input  logic clk, rst_n,

    // VPU control
    input  logic vpu_row_start,
    output logic vpu_row_busy,
    output logic vpu_row_done,

    // Input row / running statistics
    input accumulator_t x_i [0:SA_COLS-1],

    input accumulator_t in_m_i,
    input accumulator_t in_m_i_minus_1,

    input accumulator_t in_d_i,
    input accumulator_t in_d_i_minus_1,

    input accumulator_t in_o_i         [0:D_MODEL-1],
    input accumulator_t in_o_i_minus_1 [0:D_MODEL-1],

    // V tile
    input operand_t V [0:SA_COLS-1][0:D_MODEL-1],

    // Outputs
    output accumulator_t out_m_i,
    output accumulator_t out_m_i_minus_1,

    output accumulator_t out_d_i,
    output accumulator_t out_d_i_minus_1,

    output accumulator_t out_o_norm        [0:D_MODEL-1],
    output accumulator_t out_o_i           [0:D_MODEL-1],
    output accumulator_t out_o_i_minus_1   [0:D_MODEL-1]
);

    // CONSTANTS / PARAMETERS
    localparam accumulator_t NEG_INF = 32'h80000000;
    localparam int COL_IDX_W = (SA_COLS > 1) ? $clog2(SA_COLS) : 1;

    // EXP UNIT
    accumulator_t exp_in;
    accumulator_t exp_out;

    logic exp_start;
    logic exp_busy;
    logic exp_done;    

    exp U_EXP (
        .clk  (clk),
        .rst_n(rst_n),
        .start(exp_start),
        .busy (exp_busy),
        .done (exp_done),
        .in   (exp_in),
        .out  (exp_out)
    );

    // SCL UNIT
    accumulator_t scl_in_vector  [0:D_MODEL-1];
    accumulator_t scl_in_scalar;

    accumulator_t scl_out_vector [0:D_MODEL-1];

    logic scl_start;
    logic scl_done;
    logic scl_busy;

    scl U_SCL (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (scl_start),
        .busy      (scl_busy),
        .done      (scl_done),
        .in_vector (scl_in_vector),
        .in_scalar (scl_in_scalar),
        .out_vector(scl_out_vector)
    );

    // RCP UNIT
    accumulator_t rcp_in;
    accumulator_t rcp_out;

    logic rcp_start;
    logic rcp_busy;
    logic rcp_done;    

    rcp U_RCP (
        .clk  (clk),
        .rst_n(rst_n),
        .start(rcp_start),
        .busy (rcp_busy),
        .done (rcp_done),
        .in   (rcp_in),
        .out  (rcp_out) 
    );

    // SOFTMAX REGISTERS
    
    // Column iteration
    logic [COL_IDX_W-1:0] col_idx;

    // Input row register
    accumulator_t x_i_reg [0:SA_COLS-1];

    // Current / previous running maximum
    accumulator_t m_i;
    accumulator_t m_i_minus_1;

    // Current / previous denominator
    accumulator_t d_i;
    accumulator_t d_i_minus_1;

    // Reciprocal of final denominator
    accumulator_t d_inv;

    // Current / previous output accumulation
    accumulator_t o_i         [0:D_MODEL-1];
    accumulator_t o_i_minus_1 [0:D_MODEL-1];

    // Normalized output
    accumulator_t o_norm [0:D_MODEL-1];

    // Current column data
    accumulator_t x_cur;
    assign x_cur = x_i_reg[col_idx];

    accumulator_t V_cur [0:D_MODEL-1];
    genvar i;
    generate
        for (i = 0; i < D_MODEL; i++) begin
            assign V_cur[i] = accumulator_t'(V[col_idx][i]);
        end
    endgenerate

    // Variable computation
    accumulator_t max_diff;
    assign max_diff  = m_i_minus_1 - m_i;

    // x_i - m_i
    accumulator_t safe_diff;
    assign safe_diff = x_cur - m_i;

    // exp(m_i_minus_1 - m_i)
    accumulator_t exp_max_diff;

    // exp(x_i - m_i)
    accumulator_t exp_safe_diff;

    // Softmax recurrence coefficients
    accumulator_t alpha;
    assign alpha = d_i_minus_1 * exp_max_diff;

    accumulator_t beta;
    assign beta  = exp_safe_diff;
    
    // Vector scaling results
    accumulator_t o_scaled [0:D_MODEL-1];
    accumulator_t v_scaled [0:D_MODEL-1];    

    // States
    typedef enum logic [3:0] {
        vr_IDLE,
        vr_MAX,
        vr_EXP_SAFE,
        vr_EXP_MAX,
        vr_UPDATE_D,
        vr_SCALE_O,
        vr_SCALE_V,
        vr_UPDATE_O,
        vr_UPDATE_REG,
        vr_NEW_X,
        vr_RCP,
        vr_NORM_O,
        vr_ROW_DONE
    } vpu_row_state_t;

    vpu_row_state_t curr_state;

    // FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin       
            col_idx <= '0;
            vpu_row_busy <= 1'b0;
            vpu_row_done <= 1'b0;
            exp_start <= 1'b0;
            rcp_start <= 1'b0;
            scl_start <= 1'b0;
            
            m_i         <= NEG_INF;
            m_i_minus_1 <= NEG_INF;
            
            d_i <= '0; 
            d_i_minus_1 <= '0;
            
            for (int i = 0; i < D_MODEL; i++) begin 
                o_i [i] <= '0; 
                o_i_minus_1 [i] <= '0;
                o_norm [i] <= '0;
            end  
            
            out_m_i         <= NEG_INF;
            out_m_i_minus_1 <= NEG_INF;
            
            out_d_i <= '0; 
            out_d_i_minus_1 <= '0;
            
            for (int i = 0; i < D_MODEL; i++) begin 
                out_o_i [i] <= '0; 
                out_o_i_minus_1 [i] <= '0;
                out_o_norm [i] <= '0;
            end  
            
            curr_state <= vr_IDLE;          
        end else begin
            $display("Time=%0t State=%s col_idx=%0d m_i=%0d d_i=%0d exp_done=%b scl_done=%b rcp_done=%b", 
                     $time, curr_state.name(), col_idx, m_i, d_i, exp_done, scl_done, rcp_done);           
            case (curr_state)
                vr_IDLE: begin
                    if (vpu_row_start) begin
                        vpu_row_busy <= 1'b1;
                        x_i_reg     <= x_i;
                        m_i         <= in_m_i;
                        m_i_minus_1 <= in_m_i_minus_1;
                        d_i         <= in_d_i;
                        d_i_minus_1 <= in_d_i_minus_1;
                        o_i         <= in_o_i;
                        o_i_minus_1 <= in_o_i_minus_1;
                        curr_state  <= vr_MAX;
                    end
                    col_idx <= '0;
                    vpu_row_done <= 1'b0;
                    exp_start <= 1'b0;
                    rcp_start <= 1'b0;
                    scl_start <= 1'b0;
                end
                
                vr_MAX: begin
                    m_i <= (x_i_reg[col_idx] > m_i_minus_1) ? x_i_reg[col_idx] : m_i_minus_1;
                    curr_state <= vr_EXP_SAFE;
                end
                
                vr_EXP_SAFE: begin
                    if (!exp_busy) begin
                        exp_in <= safe_diff;
                        exp_start <= 1'b1;
                    end else begin
                        exp_start <= 1'b0;
                    end
                    if (exp_done) begin
                        exp_safe_diff <= exp_out;
                        curr_state <= vr_EXP_MAX;
                    end else
                        curr_state <= vr_EXP_SAFE;
                end     
                 
                vr_EXP_MAX: begin
                    if (!exp_busy) begin
                        exp_in <= max_diff;
                        exp_start <= 1'b1;
                    end else begin
                        exp_start <= 1'b0;
                    end
                    if (exp_done) begin
                        exp_max_diff <= exp_out;
                        curr_state <= vr_UPDATE_D;
                    end else
                        curr_state <= vr_EXP_MAX;
                end  
                  
                vr_UPDATE_D: begin
                    d_i <= alpha + beta;
                    curr_state <= vr_SCALE_V;
                end          
                
                vr_SCALE_V: begin
                if (!scl_busy) begin
                        scl_start <= 1'b1;
                        scl_in_vector <= V_cur;
                        scl_in_scalar <= beta;
                    end else begin
                        scl_start <= 1'b0;
                    end
                    if (scl_done) begin
                        v_scaled <= scl_out_vector;
                        curr_state <= vr_SCALE_O;
                    end else
                        curr_state <= vr_SCALE_V;    
                end
                
                vr_SCALE_O: begin
                    if (!scl_busy) begin
                        scl_start <= 1'b1;
                        scl_in_vector <= o_i_minus_1;
                        scl_in_scalar <= alpha;
                    end else begin
                        scl_start <= 1'b0;
                    end
                    if (scl_done) begin
                        o_scaled <= scl_out_vector;
                        curr_state <= vr_UPDATE_O;
                    end else
                        curr_state <= vr_SCALE_O;    
                end
                
                vr_UPDATE_O: begin
                    for (int i = 0; i < D_MODEL; i++) begin 
                        o_i [i] <= o_scaled [i] + v_scaled [i]; 
                    end 
                    
                    curr_state <= vr_UPDATE_REG;                
                end
                
                vr_UPDATE_REG: begin
                    m_i_minus_1 <= m_i;
                    d_i_minus_1 <= d_i;
                    o_i_minus_1 <= o_i;
                    
                    if (col_idx == (SA_COLS-1))
                        curr_state <= vr_RCP;
                    else
                        curr_state <= vr_NEW_X;
                end
                
                vr_NEW_X: begin
                    col_idx <= col_idx + 1;
                    curr_state <= vr_MAX;
                end
                
                vr_RCP: begin
                    if (!rcp_busy) begin
                        rcp_in <= d_i;
                        rcp_start <= 1'b1;
                    end else begin
                        rcp_start <= 1'b0;
                    end
                    if (rcp_done) begin
                        d_inv <= rcp_out;
                        curr_state <= vr_NORM_O;
                    end else
                        curr_state <= vr_RCP;
                end
                
                vr_NORM_O: begin
                if (!scl_busy) begin
                        scl_start <= 1'b1;
                        scl_in_vector <= o_i;
                        scl_in_scalar <= d_inv;
                    end else begin
                        scl_start <= 1'b0;
                    end
                    if (scl_done) begin
                        o_norm <= scl_out_vector;
                        curr_state <= vr_ROW_DONE;
                    end else
                        curr_state <= vr_NORM_O;    
                end
                
                vr_ROW_DONE: begin
                    // Outputs
                    out_o_norm <= o_norm;
                    out_o_i <= o_i;
                    out_o_i_minus_1 <= o_i_minus_1;
                    out_d_i <= d_i;
                    out_d_i_minus_1 <= d_i_minus_1;
                    out_m_i <= m_i;
                    out_m_i_minus_1 <= m_i_minus_1;
                    
                    vpu_row_busy <= 1'b0;
                    vpu_row_done <= 1'b1;
                                        
                    curr_state <= vr_IDLE;
                end           
            endcase         
        end
    end
endmodule