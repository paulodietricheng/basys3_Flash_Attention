`timescale 1ns/1ps

/*
 * ============================================================================
 *  Module: uart_rx
 * ============================================================================
 *
 *  Description:
 *      Simple UART receiver that samples an asynchronous serial input and
 *      reconstructs one 8-bit data byte.
 *
 *      The receiver expects the standard UART frame:
 *
 *          1 start bit
 *          8 data bits, LSB first
 *          1 stop bit
 *
 *      The asynchronous RX input is first passed through a two-register
 *      synchronizer before being used by the receive state machine.
 *
 *      Once a falling edge is detected, the receiver waits half of a bit
 *      period and samples the start bit near its center. If the start bit is
 *      valid, the module samples each data bit once per bit period.
 *
 *      After all 8 data bits are received, the stop bit is checked. A valid
 *      stop bit produces a one-cycle valid pulse and updates data. An invalid
 *      stop bit produces a one-cycle framing_error pulse and waits for the
 *      RX line to return high before receiving another frame.
 *
 *      CLKS_PER_BIT defines how many input clock cycles correspond to one UART
 *      bit period and therefore determines the baud rate.
 *
 * Author: Paulo Dietrich via an agentic workflow
 * ============================================================================
 */

module uart_rx #(parameter int CLKS_PER_BIT = 868) (
    input logic clk, rst_n, 
   
    input logic rx,
    
    output logic [7:0] data,
    
    // Flags
    output logic valid, framing_error
);

    // Counter width required to count one full UART bit period.
    localparam int CW = $clog2(CLKS_PER_BIT + 1);
    
    // Two-stage synchronizer for the asynchronous RX input.
    (* ASYNC_REG="TRUE" *) logic rx_meta, rx_sync;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            rx_meta <= 1;
            rx_sync <= 1;
        end else begin 
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end
    
    // UART receive state machine.
    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        STOP,
        WAIT_HIGH
    } state_t ;
    
    state_t state;
    logic [CW-1:0] count;
    logic [2:0] bit_idx;
    logic [7:0] shift;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            
            // Receive metadata and data.
            count   <= '0;
            bit_idx <= '0;
            shift   <= '0;
            data    <= '0;
            
            // Flags.
            valid         <= 0;
            framing_error <= 0;
        end else begin
            // Flags are pulsed for one clock cycle.
            valid         <= 0;
            framing_error <= 0;
            
            case (state)

                // Wait for the RX line to go low, indicating a possible start bit.
                IDLE: begin
                    if (!rx_sync) begin 
                        count <= CW'(CLKS_PER_BIT/2-1);
                        state <= START;
                    end
                end
                
                // Sample the start bit near its center.
                START: begin
                    if (count != 0) 
                        count <= count - 1'b1;
                    else if (rx_sync)
                        state <= IDLE;
                    else begin 
                        count   <= CW'(CLKS_PER_BIT-1);
                        bit_idx <= 0;
                        state   <= DATA;
                    end
                end
                
                // Sample each data bit once per UART bit period.
                DATA: begin
                    if (count != 0) 
                        count <= count - 1'b1;
                    else begin
                        shift[bit_idx] <= rx_sync;
                        count <= CW'(CLKS_PER_BIT - 1);
                        if (bit_idx==7)
                            state <= STOP;
                        else 
                            bit_idx <= bit_idx+1'b1;
                    end
                end
                
                // Check the stop bit and complete the received byte.
                STOP: begin 
                    if (count != 0) 
                        count <= count - 1'b1;
                    else if (rx_sync) begin 
                        data <= shift;
                        valid <= 1;
                        state <= IDLE;
                    end else begin
                        framing_error <= 1;
                        state <= WAIT_HIGH;
                    end
                end
                
                // After a framing error, wait for the RX line to return idle.
                WAIT_HIGH: 
                    if (rx_sync) 
                        state<=IDLE;

                default: state<=IDLE;
            endcase
        end
    end
    
    // Require enough clock cycles per UART bit for reliable sampling.
    initial assert(CLKS_PER_BIT>=8) else $fatal(1,"UART needs at least 8 clocks/bit");

endmodule