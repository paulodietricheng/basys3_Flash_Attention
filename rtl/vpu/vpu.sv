`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.08.2026 16:10:14
// Design Name: 
// Module Name: vpu
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

module vpu (
    input clk, rst_n,

    // mxu
    input accumulator_t scores [0:SA_ROWS-1][0:SA_COLS-1],
    input logic vpu_start,
    
    // Fetch V_tile
    input operand_t V [0:SA_COLS-1][0:D_MODEL-1],
    // SRAM ADDRESSING
    
    // Output data o
    output operand_t O_N [0:SA_ROWS][0:D_MODEL],
    output logic     vpu_done
);
    localparam accumulator_t NEG_INF = 32'h80000000;
    
    //REGISTERS
    accumulator_t m_i         [SA_ROWS];
    accumulator_t m_i_minus_1 [SA_ROWS];

    // Current / previous denominator
    accumulator_t d_i         [SA_ROWS];
    accumulator_t d_i_minus_1 [SA_ROWS];

    // Current / previous output accumulation
    accumulator_t o_i         [SA_ROWS][0:D_MODEL-1];
    accumulator_t o_i_minus_1 [SA_ROWS][0:D_MODEL-1];

    // Normalized output
    accumulator_t o_norm [0:D_MODEL-1][SA_ROWS];

    // vpu_row instantiation
    // control
    logic vpu_row_start;
    logic vpu_row_busy;
    logic vpu_row_done;
    
    // Input row
    accumulator_t x_i [0:SA_COLS-1];

    // Current / previous running maximum
    accumulator_t in_m_i;
    accumulator_t in_m_i_minus_1;

    // Current / previous denominator
    accumulator_t in_d_i;
    accumulator_t in_d_i_minus_1;

    // Reciprocal of final denominator
    accumulator_t in_d_inv;

    // Current / previous output accumulation
    accumulator_t in_o_i         [0:D_MODEL-1];
    accumulator_t in_o_i_minus_1 [0:D_MODEL-1];
    
    // Current / previous running maximum
    accumulator_t out_m_i;
    accumulator_t out_m_i_minus_1;

    // Current / previous denominator
    accumulator_t out_d_i;
    accumulator_t out_d_i_minus_1;

    // Reciprocal of final denominator
    accumulator_t out_d_inv;

    // Current / previous output accumulation
    accumulator_t out_o_i         [0:D_MODEL-1];
    accumulator_t out_o_i_minus_1 [0:D_MODEL-1];

    // Normalized output
    accumulator_t out_o_norm [0:D_MODEL-1];
    
    // V_tile_register
    operand_t V_reg [0:SA_COLS-1][0:D_MODEL-1];

    // Instantiate vpu_row module
    vpu_row U_VROW (
        .clk            (clk),
        .rst_n          (rst_n),
        .vpu_row_start  (vpu_row_start),
        .vpu_row_busy   (vpu_row_busy),
        .vpu_row_done   (vpu_row_done),
        .x_i            (x_i),
        .in_m_i         (in_m_i),
        .in_m_i_minus_1 (in_m_i_minus_1),
        .in_d_i         (in_d_i),
        .in_d_i_minus_1 (in_d_i_minus_1),
        .in_o_i         (in_o_i),
        .in_o_i_minus_1 (in_o_i_minus_1),
        .V              (V_reg),
        .out_m_i        (out_m_i),
        .out_m_i_minus_1(out_m_i_minus_1),
        .out_d_i        (out_d_i),
        .out_d_i_minus_1(out_d_i_minus_1),
        .out_o_i        (out_o_i),
        .out_o_i_minus_1(out_o_i_minus_1),
        .out_o_norm     (out_o_norm)
    );
    
    typedef enum logic [1:0]{
        v_IDLE,
        v_NEXT_ROW,
        v_COMPUTE_ROW,  
        v_DONE
    } vpu_state_t ;
    
    // Row index
    localparam ROW_IDX_W = $clog2(SA_ROWS);
    logic [ROW_IDX_W-1:0] row_idx;
    
    vpu_state_t curr_state;
    
    // Latch the incoming scores
    accumulator_t x_reg [0:SA_ROWS-1][0:SA_COLS-1];
    
    // FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= v_IDLE;
    
            row_idx    <= '0;
            vpu_row_start <= 1'b0;
            vpu_done      <= 1'b0;
    
            // Initialize running values
            for (int j = 0; j < SA_ROWS; j++) begin
                m_i[j]         <= NEG_INF;
                m_i_minus_1[j] <= NEG_INF;
                d_i[j]         <= '0;
                d_i_minus_1[j] <= '0;
            end
    
            for (int i = 0; i < D_MODEL; i++) begin
                for (int j = 0; j < SA_ROWS; j++) begin
                    o_i[j][i]         <= '0;
                    o_i_minus_1[j][i] <= '0;
                    o_norm[j][i]      <= '0;
                end
            end
    
            for (int j = 0; j < SA_ROWS; j++) begin
                for (int i = 0; i < D_MODEL; i++) begin
                    O_N[j][i] <= '0;
                end
            end
    
            // Inputs to vpu_row
            in_m_i         <= NEG_INF;
            in_m_i_minus_1 <= NEG_INF;
            in_d_i         <= '0;
            in_d_i_minus_1 <= '0;
    
            for (int i = 0; i < D_MODEL; i++) begin
                in_o_i[i]         <= '0;
                in_o_i_minus_1[i] <= '0;
            end
    
        end else begin
    
            // Default values every cycle
            vpu_row_start <= 1'b0;
            vpu_done      <= 1'b0;
    
            case (curr_state)
    
                v_IDLE: begin
    
                    if (vpu_start) begin
    
                        row_idx <= '0;
    
                        // Latch the input
                        x_reg <= scores;
    
                        // Initialize first row
                        in_m_i         <= NEG_INF;
                        in_m_i_minus_1 <= NEG_INF;
    
                        in_d_i         <= '0;
                        in_d_i_minus_1 <= '0;
    
                        for (int i = 0; i < D_MODEL; i++) begin
                            in_o_i[i]         <= '0;
                            in_o_i_minus_1[i] <= '0;
                        end
    
                        curr_state <= v_COMPUTE_ROW;
                    end
                end
    
                v_COMPUTE_ROW: begin
    
                    // Start vpu_row
                    if (!vpu_row_busy) begin
                        for (int i = 0; i < D_MODEL; i++)
                            x_i[i]     <= x_reg[row_idx][i];
                            
                        in_m_i         <= m_i[row_idx];
                        in_m_i_minus_1 <= m_i_minus_1[row_idx];
                        in_d_i         <= d_i[row_idx];
                        in_d_i_minus_1 <= d_i_minus_1[row_idx];
                        
                        in_o_i <= o_i [row_idx];
                        in_o_i_minus_1 <= o_i_minus_1 [row_idx];
                    end else begin
                        vpu_row_start <= 1'b0;
                    end    
                    if (vpu_row_done) begin
    
                        // Save results from vpu_row
                        m_i[row_idx] <= out_m_i;
                        m_i_minus_1[row_idx] <= out_m_i_minus_1;
    
                        d_i[row_idx] <= out_d_i;
                        d_i_minus_1[row_idx] <= out_d_i_minus_1;
    
                        for (int i = 0; i < D_MODEL; i++) begin
                            o_i[row_idx][i] <= out_o_i[i];
                            o_i_minus_1[row_idx][i] <= out_o_i_minus_1[i];
    
                            o_norm[row_idx][i] <= out_o_norm[i];
                        end
    
                        // Last row?
                        if (row_idx == SA_ROWS-1) begin
                            curr_state <= v_DONE;
                        end
                        else begin
                            curr_state <= v_NEXT_ROW;
                        end
                    end else 
                        curr_state <= v_COMPUTE_ROW;
                end
    
                v_NEXT_ROW: begin
    
                    row_idx <= row_idx + 1'b1;
    
                    curr_state <= v_COMPUTE_ROW;
                end
    
                 v_DONE: begin
    
                    vpu_done <= 1'b1;
    
                    curr_state <= v_IDLE;
                end
    
            endcase
        end
    end
    
endmodule