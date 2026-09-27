`timescale 1ns/1ps

/*
 * ============================================================================
 *  Module: uart_tx
 * ============================================================================
 *
 *  Description:
 *      Simple UART transmitter that sends one 8-bit data byte using the
 *      standard UART frame:
 *
 *          1 start bit
 *          8 data bits, LSB first
 *          1 stop bit
 *
 *      The transmitter accepts a new byte when ready is high and valid is
 *      asserted. Once transmission starts, ready goes low until the complete
 *      10-bit UART frame has been sent.
 *
 *      CLKS_PER_BIT defines how many input clock cycles correspond to one UART
 *      bit period and therefore determines the baud rate.
 *
 * Author: Paulo Dietrich via an agentic workflow
 * ============================================================================
 */

module uart_tx #(parameter int CLKS_PER_BIT=868) (
    input logic clk, rst_n,
    
    input logic [7:0] data,
    input logic valid,
    
    output logic ready, 
    output logic tx
);

    // Counter width required to count one full UART bit period.
    localparam int CW = $clog2(CLKS_PER_BIT + 1);
    
    logic busy;
    logic [CW-1:0] count;
    logic [3:0] bit_idx;
    logic [9:0] frame;
    
    // New data can only be accepted when no transmission is active.
    assign ready = !busy;

    // UART line remains high while idle.
    assign tx = busy ? frame[bit_idx] : 1'b1;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy    <= 0;
            count   <= '0;
            bit_idx <= '0;
            frame   <= '1;
        end else if (!busy) begin
            // Capture a new byte and build the full UART frame.
            if (valid) begin
                frame   <= {1'b1, data, 1'b0};
                busy    <= 1;
                bit_idx <= 0;
                count   <= CW'(CLKS_PER_BIT - 1);
            end
        end else if (count != 0) 
            // Hold the current UART bit for CLKS_PER_BIT clock cycles.
            count <= count - 1'b1;
        else if (bit_idx == 9) 
            // Stop bit has completed, return to the idle state.
            busy <= 0;
        else begin
            // Advance to the next bit in the UART frame.
            bit_idx <= bit_idx + 1'b1;
            count   <= CW'(CLKS_PER_BIT - 1);
        end
    end

endmodule