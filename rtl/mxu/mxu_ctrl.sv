`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/22/2026 03:14:37 PM
// Design Name: 
// Module Name: mxu_ctrl
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

module mxu_ctrl(
    input  logic clk, rst_n,

    // From/to Central control
    input  logic mxu_start,
    output logic mxu_done, 
    input mxu_cmd_t mxu_cmd,
    
    // To systolic array
    output logic array_en,
    output logic clr_acc_n,

    // To operand_handler
    output k_dim_t a_k_idx,
    output k_dim_t b_k_idx,
    output logic a_k_valid,
    output logic b_k_valid,
    
    // To db_control
    output logic mxu_reading_ram
);

    // latch the command
    mxu_cmd_t reg_cmd;
    always_ff @(posedge clk) begin
        if (mxu_start)
            reg_cmd <= mxu_cmd;
    end

    logic [RESULT_LAT_W - 1:0] result_lat; 
    assign result_lat = reg_cmd.m + reg_cmd.n + reg_cmd.k - 2 + DSP_LAT + reg_cmd.n; 

    logic [RESULT_LAT_W - 1:0] counter;

    // Controller state type
    typedef enum logic [2:0] {
        m_IDLE,
        m_CLEAR,
        m_STREAM,
        m_DRAIN,
        m_DONE
    } mxu_state_t;

    mxu_state_t curr_state;

    // Counter to determine the result
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= '0;
        end
        else if (curr_state == m_IDLE || curr_state == m_CLEAR || curr_state == m_DONE) begin
            counter <= '0;
        end
        else if (curr_state == m_STREAM || curr_state == m_DRAIN) begin
            counter <= counter + 1;
        end
    end
    
    // a_k_valid condition
    assign a_k_valid = (curr_state == m_STREAM) && (a_k_idx < reg_cmd.k + reg_cmd.a_k_offset);
    assign b_k_valid = (curr_state == m_STREAM) && (b_k_idx < reg_cmd.k + reg_cmd.b_k_offset);

    // FSM Controller
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= m_IDLE;

            array_en  <= 1'b0;
            clr_acc_n <= 1'b1;
            mxu_done  <= 1'b0;
            a_k_idx   <= '0;
            b_k_idx   <= '0;
            mxu_reading_ram <= 1'b0;
        end
        else begin
        
            // safe defaults
            array_en  <= 1'b0;
            clr_acc_n <= 1'b1;
            mxu_done  <= 1'b0;
            a_k_idx   <= '0;
            b_k_idx   <= '0;
            mxu_reading_ram <= 1'b0;

            case (curr_state)

                m_IDLE : begin
                    a_k_idx   <= '0;
                    b_k_idx   <= '0;
                    
                    curr_state <= mxu_start ? m_CLEAR : m_IDLE;
                end

                m_CLEAR : begin
                    clr_acc_n <= 1'b0;
                    a_k_idx   <= reg_cmd.a_k_offset;
                    b_k_idx   <= reg_cmd.b_k_offset;

                    curr_state <= m_STREAM;
                end

                m_STREAM : begin
                    array_en  <= 1'b1;
                    clr_acc_n <= 1'b1;
                    mxu_reading_ram <= 1'b1;

                    if (!(a_k_valid & b_k_valid)) begin
                        curr_state <= m_DRAIN;
                    end
                    else begin
                        a_k_idx <= a_k_idx + 1'b1;
                        b_k_idx <= b_k_idx + 1'b1;
                    end
                end

                m_DRAIN : begin
                    array_en  <= 1'b1;
                    clr_acc_n <= 1'b1;
                    a_k_idx   <= '0;
                    b_k_idx   <= '0;
                    mxu_reading_ram <= 1'b0;

                    curr_state <= (counter == result_lat) ? m_DONE : m_DRAIN;
                end

                m_DONE : begin
                    mxu_done  <= 1'b1;
                    array_en  <= 1'b0;
                    clr_acc_n <= 1'b1;
                    a_k_idx   <= '0;
                    b_k_idx   <= '0;
                    mxu_reading_ram <= 1'b0;

                    curr_state <= m_IDLE;
                end

                default : curr_state <= m_IDLE;
            endcase
        end
    end

endmodule
