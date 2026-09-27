`timescale 1ns / 1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: vpu_row
 * ============================================================================
 *
 *  Description:
 *      Processes one row of the Flash Attention score matrix using the online
 *      softmax recurrence.
 *
 *      The module maintains the running maximum, denominator, and output
 *      accumulation across the columns of the current score row.
 *
 *      For every score value:
 *
 *          1. Update the running maximum.
 *          2. Compute exp(x_i - m_i).
 *          3. Compute exp(m_i_minus_1 - m_i).
 *          4. Update the running denominator.
 *          5. Scale the previous output accumulation.
 *          6. Scale the current V row.
 *          7. Add both contributions to update the output accumulation.
 *
 *      After all columns have been processed, the denominator reciprocal is
 *      calculated and used to normalize the final output vector.
 *
 *      The EXP, SCL, and RCP functional units operate through start/busy/done
 *      handshakes and are reused throughout the row computation.
 *
 * Author: Paulo Dietrich
 * ============================================================================
 */

module vpu_row (
    input logic clk, rst_n,

    // control
    input  logic vpu_row_start,
    output logic vpu_row_busy,
    output logic vpu_row_done,

    // score row
    input accumulator_t x_i [0:SA_COLS-1],

    // running maximum
    input accumulator_t in_m_i,
    input accumulator_t in_m_i_minus_1,

    // running denominator
    input accumulator_t in_d_i,
    input accumulator_t in_d_i_minus_1,

    // running output
    input accumulator_t in_o_i         [0:D_MODEL-1],
    input accumulator_t in_o_i_minus_1 [0:D_MODEL-1],

    // v tile
    input operand_t V [0:SA_COLS-1][0:D_MODEL-1],

    // outputs
    output accumulator_t out_m_i,
    output accumulator_t out_m_i_minus_1,
    output accumulator_t out_d_i,
    output accumulator_t out_d_i_minus_1,
    output accumulator_t out_o_norm      [0:D_MODEL-1],
    output accumulator_t out_o_i         [0:D_MODEL-1],
    output accumulator_t out_o_i_minus_1 [0:D_MODEL-1]
);

    localparam accumulator_t NEG_INF = 32'h80000000;
    localparam int COL_IDX_W = (SA_COLS > 1) ? $clog2(SA_COLS) : 1;

    // exp
    accumulator_t exp_in;
    accumulator_t exp_out;
    logic exp_start, exp_busy, exp_done;

    exp U_EXP (
        .clk  (clk),
        .rst_n(rst_n),
        .start(exp_start),
        .busy (exp_busy),
        .done (exp_done),
        .in   (exp_in),
        .out  (exp_out)
    );

    // scaler
    accumulator_t scl_in_vector [0:D_MODEL-1];
    accumulator_t scl_in_scalar;
    accumulator_t scl_out_vector[0:D_MODEL-1];
    logic scl_start, scl_done, scl_busy;

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

    // reciprocal
    accumulator_t rcp_in;
    accumulator_t rcp_out;
    logic rcp_start, rcp_busy, rcp_done;

    rcp U_RCP (
        .clk  (clk),
        .rst_n(rst_n),
        .start(rcp_start),
        .busy (rcp_busy),
        .done (rcp_done),
        .in   (rcp_in),
        .out  (rcp_out)
    );

    // column iteration
    logic [COL_IDX_W-1:0] col_idx;

    // input score row
    accumulator_t x_i_reg [0:SA_COLS-1];

    // running maximum
    accumulator_t m_i;
    accumulator_t m_i_minus_1;

    // running denominator
    accumulator_t d_i;
    accumulator_t d_i_minus_1;

    // reciprocal of the final denominator
    accumulator_t d_inv;

    // running output accumulation
    accumulator_t o_i         [0:D_MODEL-1];
    accumulator_t o_i_minus_1 [0:D_MODEL-1];

    // normalized output
    accumulator_t o_norm [0:D_MODEL-1];

    // current score value
    accumulator_t x_cur;
    assign x_cur = x_i_reg[col_idx];

    // Current V row converted into accumulator fixed-point format.
    accumulator_t V_cur [0:D_MODEL-1];

    for (genvar i = 0; i < D_MODEL; i++) begin : GEN_V_CUR
        assign V_cur[i] = accumulator_t'(V[col_idx][i]) <<< FRAC_BITS;
    end

    // Difference between the old and updated running maximum.
    accumulator_t max_diff;
    assign max_diff = (d_i_minus_1 == '0) ? '0 : m_i_minus_1 - m_i;

    // Difference between the current score and updated running maximum.
    accumulator_t safe_diff;
    assign safe_diff = x_cur - m_i;

    // Exponential recurrence terms.
    accumulator_t exp_max_diff;
    accumulator_t exp_safe_diff;

    // Softmax recurrence coefficients.
    accumulator_t alpha;
    accumulator_t beta;

    assign alpha = acc_mul(d_i_minus_1, exp_max_diff);
    assign beta  = exp_safe_diff;

    // Scaled output contributions.
    accumulator_t o_scaled [0:D_MODEL-1];
    accumulator_t v_scaled [0:D_MODEL-1];

    // Functional-unit handshake tracking.
    logic exp_pending, scl_pending, rcp_pending;

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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exp_pending  <= 1'b0;
            scl_pending  <= 1'b0;
            rcp_pending  <= 1'b0;
            col_idx      <= '0;
            vpu_row_busy <= 1'b0;
            vpu_row_done <= 1'b0;
            exp_start    <= 1'b0;
            rcp_start    <= 1'b0;
            scl_start    <= 1'b0;

            m_i         <= NEG_INF;
            m_i_minus_1 <= NEG_INF;
            d_i         <= '0;
            d_i_minus_1 <= '0;

            for (int i = 0; i < D_MODEL; i++) begin
                o_i[i]         <= '0;
                o_i_minus_1[i] <= '0;
                o_norm[i]      <= '0;
            end

            out_m_i         <= NEG_INF;
            out_m_i_minus_1 <= NEG_INF;
            out_d_i         <= '0;
            out_d_i_minus_1 <= '0;

            for (int i = 0; i < D_MODEL; i++) begin
                out_o_i[i]         <= '0;
                out_o_i_minus_1[i] <= '0;
                out_o_norm[i]      <= '0;
            end

            curr_state <= vr_IDLE;
        end else begin
            exp_start <= 1'b0;
            scl_start <= 1'b0;
            rcp_start <= 1'b0;

            case (curr_state)

                // Capture the row and running Flash Attention state.
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

                    col_idx      <= '0;
                    vpu_row_done <= 1'b0;
                    exp_start    <= 1'b0;
                    rcp_start    <= 1'b0;
                    scl_start    <= 1'b0;
                end

                // Update the running maximum.
                vr_MAX: begin
                    m_i <= (x_i_reg[col_idx] > m_i_minus_1) ? x_i_reg[col_idx] : m_i_minus_1;
                    curr_state <= vr_EXP_SAFE;
                end

                // Compute exp(x_i - m_i).
                vr_EXP_SAFE: begin
                    if (!exp_pending && !exp_busy) begin
                        exp_pending <= 1'b1;
                        exp_in      <= safe_diff;
                        exp_start   <= 1'b1;
                    end else begin
                        exp_start <= 1'b0;
                    end

                    if (exp_pending && exp_done) begin
                        exp_pending  <= 1'b0;
                        exp_safe_diff <= exp_out;
                        curr_state   <= vr_EXP_MAX;
                    end else
                        curr_state <= vr_EXP_SAFE;
                end

                // Compute exp(m_i_minus_1 - m_i).
                vr_EXP_MAX: begin
                    if (!exp_pending && !exp_busy) begin
                        exp_pending <= 1'b1;
                        exp_in      <= max_diff;
                        exp_start   <= 1'b1;
                    end else begin
                        exp_start <= 1'b0;
                    end

                    if (exp_pending && exp_done) begin
                        exp_pending  <= 1'b0;
                        exp_max_diff <= (d_i_minus_1 == '0) ? '0 : exp_out;
                        curr_state   <= vr_UPDATE_D;
                    end else
                        curr_state <= vr_EXP_MAX;
                end

                // Update the running softmax denominator.
                vr_UPDATE_D: begin
                    d_i <= alpha + beta;
                    curr_state <= vr_SCALE_V;
                end

                // Scale the current V vector by the new softmax contribution.
                vr_SCALE_V: begin
                    if (!scl_pending && !scl_busy) begin
                        scl_pending   <= 1'b1;
                        scl_start     <= 1'b1;
                        scl_in_vector <= V_cur;
                        scl_in_scalar <= beta;
                    end else begin
                        scl_start <= 1'b0;
                    end

                    if (scl_pending && scl_done) begin
                        scl_pending <= 1'b0;
                        v_scaled    <= scl_out_vector;
                        curr_state  <= vr_SCALE_O;
                    end else
                        curr_state <= vr_SCALE_V;
                end

                // Rescale the previous output when the running maximum changes.
                vr_SCALE_O: begin
                    if (!scl_pending && !scl_busy) begin
                        scl_pending   <= 1'b1;
                        scl_start     <= 1'b1;
                        scl_in_vector <= o_i_minus_1;
                        scl_in_scalar <= exp_max_diff;
                    end else begin
                        scl_start <= 1'b0;
                    end

                    if (scl_pending && scl_done) begin
                        scl_pending <= 1'b0;
                        o_scaled    <= scl_out_vector;
                        curr_state  <= vr_UPDATE_O;
                    end else
                        curr_state <= vr_SCALE_O;
                end

                // Add the previous output contribution and current V contribution.
                vr_UPDATE_O: begin
                    for (int i = 0; i < D_MODEL; i++)
                        o_i[i] <= o_scaled[i] + v_scaled[i];

                    curr_state <= vr_UPDATE_REG;
                end

                // Store the new running state before processing the next score.
                vr_UPDATE_REG: begin
                    m_i_minus_1 <= m_i;
                    d_i_minus_1 <= d_i;
                    o_i_minus_1 <= o_i;

                    if (col_idx == COL_IDX_W'(SA_COLS-1))
                        curr_state <= vr_RCP;
                    else
                        curr_state <= vr_NEW_X;
                end

                // Advance to the next score in the row.
                vr_NEW_X: begin
                    col_idx <= col_idx + 1;
                    curr_state <= vr_MAX;
                end

                // Calculate the reciprocal of the final denominator.
                vr_RCP: begin
                    if (!rcp_pending && !rcp_busy) begin
                        rcp_pending <= 1'b1;
                        rcp_in      <= d_i;
                        rcp_start   <= 1'b1;
                    end else begin
                        rcp_start <= 1'b0;
                    end

                    if (rcp_pending && rcp_done) begin
                        rcp_pending <= 1'b0;
                        d_inv       <= rcp_out;
                        curr_state  <= vr_NORM_O;
                    end else
                        curr_state <= vr_RCP;
                end

                // Normalize the accumulated output by the final denominator.
                vr_NORM_O: begin
                    if (!scl_pending && !scl_busy) begin
                        scl_pending   <= 1'b1;
                        scl_start     <= 1'b1;
                        scl_in_vector <= o_i;
                        scl_in_scalar <= d_inv;
                    end else begin
                        scl_start <= 1'b0;
                    end

                    if (scl_pending && scl_done) begin
                        scl_pending <= 1'b0;
                        o_norm      <= scl_out_vector;
                        curr_state  <= vr_ROW_DONE;
                    end else
                        curr_state <= vr_NORM_O;
                end

                // Export the updated running state and normalized output.
                vr_ROW_DONE: begin
                    out_o_norm      <= o_norm;
                    out_o_i         <= o_i;
                    out_o_i_minus_1 <= o_i_minus_1;
                    out_d_i         <= d_i;
                    out_d_i_minus_1 <= d_i_minus_1;
                    out_m_i         <= m_i;
                    out_m_i_minus_1 <= m_i_minus_1;

                    vpu_row_busy <= 1'b0;
                    vpu_row_done <= 1'b1;

                    curr_state <= vr_IDLE;
                end

                default: begin
                    curr_state   <= vr_IDLE;
                    vpu_row_busy <= 1'b0;
                    vpu_row_done <= 1'b0;
                    exp_pending  <= 1'b0;
                    scl_pending  <= 1'b0;
                    rcp_pending  <= 1'b0;
                end

            endcase
        end
    end

endmodule