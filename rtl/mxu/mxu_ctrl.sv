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
    
    input  n_dim_t n,
    input  m_dim_t m,
    input  p_dim_t p,   
    
    // From operand skewer
    input  logic pe00_valid,

    // To systolic array
    output logic array_en,
    output logic clr_acc_n,

    // To operand_handler
    output dim_t dim_idx,
    output logic dim_valid,
    
    // To db_control
    output logic mxu_reading_ram
);

    logic [RESULT_LAT_W - 1:0] result_lat; // Placeholder 5
    assign result_lat = 2*n + m - 2 + DSP_LAT + n; 

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

    logic first_pe_token;
    
    assign first_pe_token = pe00_valid && ((curr_state == m_STREAM) || (curr_state == m_DRAIN));

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

    // FSM Controller
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= m_IDLE;

            array_en  <= 1'b0;
            clr_acc_n <= 1'b1;
            mxu_done  <= 1'b0;
            dim_valid <= 1'b0;
            dim_idx   <= '0;
            mxu_reading_ram <= 1'b0;
        end
        else begin
        
            // safe defaults
            array_en  <= 1'b0;
            clr_acc_n <= 1'b1;
            mxu_done  <= 1'b0;
            dim_valid <= 1'b0;
            dim_idx   <= dim_idx;
            mxu_reading_ram <= 1'b0;

            case (curr_state)

                m_IDLE : begin
                    dim_idx <= '0;
                    curr_state <= mxu_start ? m_CLEAR : m_IDLE;
                end

                m_CLEAR : begin
                    clr_acc_n <= 1'b0;
                    dim_idx   <= '0;

                    curr_state <= m_STREAM;
                end

                m_STREAM : begin
                    array_en  <= 1'b1;
                    clr_acc_n <= 1'b1;
                    dim_valid <= 1'b1;
                    mxu_reading_ram <= 1'b1;

                    if (dim_idx == D_MODEL-1) begin
                        curr_state <= m_DRAIN;
                    end
                    else begin
                        dim_idx <= dim_idx + 1'b1;
                    end
                end

                m_DRAIN : begin
                    array_en  <= 1'b1;
                    clr_acc_n <= 1'b1;
                    dim_valid <= 1'b0;
                    dim_idx   <= '0;
                    mxu_reading_ram <= 1'b0;

                    curr_state <= (counter == (result_lat - 1)) ? m_DONE : m_DRAIN;
                end

                m_DONE : begin
                    mxu_done  <= 1'b1;
                    array_en  <= 1'b0;
                    clr_acc_n <= 1'b1;
                    dim_valid <= 1'b0;
                    dim_idx   <= '0;
                    mxu_reading_ram <= 1'b0;

                    curr_state <= m_IDLE;
                end

                default : curr_state <= m_IDLE;
            endcase
        end
    end

endmodule
