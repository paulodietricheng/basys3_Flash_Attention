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
    input accumulator_t x_i,

    // Control
    input logic mxu_done,
    input logic last_kv_tile,
    output logic vpu_done,

    // SRAM
    input operand_t V_i [0:D_MODEL-1],
    output operand_t O_N [0:D_MODEL-1]
);

    // Registers
    accumulator_t m_i, m_i_minus_1;
    accumulator_t d_i, d_i_minus_1;
    accumulator_t o_i, o_i_minus_1;

    // Intermediate signals
    accumulator_t max_diff;
    accumulator_t safe_diff;

    accumulator_t exp_max_diff;
    accumulator_t exp_safe_diff;

    accumulator_t alpha;
    accumulator_t beta;

    // EXP units
    exp U_EXP0 (
        .in  (max_diff),
        .out (exp_max_diff)
    );

    exp U_EXP1 (
        .in  (safe_diff),
        .out (exp_safe_diff)
    );
    
    // Combinational datapath
    assign max_diff  = m_i_minus_1 - m_i;
    assign safe_diff = x_i - m_i;

    assign alpha = d_i_minus_1 * exp_max_diff;
    assign beta  = exp_safe_diff;

    // States
    typedef enum logic [2:0] {
        v_IDLE,
        v_MAX,
        v_SUM,
        v_UPDATE,
        v_DONE
    } vpu_state_t;

    vpu_state_t curr_state;

    // Control flags
    logic max_done;
    logic sum_done;
    logic update_done;

    // FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset state
            curr_state <= v_IDLE;

            // Reset registers
            m_i         <= 32'hFF800000; // -infinity
            m_i_minus_1 <= 32'hFF800000;

            d_i         <= 32'h0;
            d_i_minus_1 <= 32'h0;

            o_i         <= 32'h0;
            o_i_minus_1 <= 32'h0;

            // Reset output/control
            vpu_done <= 1'b0;
        end else begin
            case (curr_state)
                // IDLE
                v_IDLE: begin
                    vpu_done <= 1'b0;
                    if (mxu_done) begin
                        curr_state <= v_MAX;
                    end
                end

                // MAX
                v_MAX: begin
                    // m_i = max(m_i_minus_1, x_i)

                    if (x_i > m_i_minus_1)
                        m_i <= x_i;
                    else
                        m_i <= m_i_minus_1;

                    if (max_done) begin
                        curr_state <= v_SUM;
                    end
                end

                // SUM
                v_SUM: begin
                    // Differences needed by exponential units
                    //
                    // max_diff  = m_(i-1) - m_i
                    // safe_diff = x_i - m_i

                    // d_i =
                    //     d_(i-1) * exp(m_(i-1)-m_i)
                    //     + exp(x_i-m_i)

                    d_i <=
                        d_i_minus_1 * exp_max_diff
                        + exp_safe_diff;

                    if (sum_done) begin
                        curr_state <= v_UPDATE;
                    end
                end
                // UPDATE
                v_UPDATE: begin

                    // Save previous values
                    m_i_minus_1 <= m_i;
                    d_i_minus_1 <= d_i;

                    // ------------------------------------------------
                    // Output update
                    // ------------------------------------------------
                    //
                    // alpha =
                    // d_(i-1) * exp(m_(i-1)-m_i)
                    //
                    // beta =
                    // exp(x_i-m_i)
                    //
                    // o_i =
                    // (alpha / d_i) * o_(i-1)
                    // +
                    // (beta / d_i) * V_i
                    //

                    if (update_done) begin
                        o_i_minus_1 <= o_i;
                        
                        if (last_kv_tile) begin
                            curr_state <= v_DONE;
                        end
                        else begin
                            curr_state <= v_IDLE;
                        end
                    end
                end

                // DONE
                v_DONE: begin
                    vpu_done <= 1'b1;
                    curr_state <= v_DONE;
                end

                default: begin
                    curr_state <= v_IDLE;
                end
            endcase
        end
    end
    
endmodule