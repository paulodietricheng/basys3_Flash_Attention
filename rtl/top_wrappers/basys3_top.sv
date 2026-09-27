`timescale 1ns/1ps

/*
 * ============================================================================
 *  Module: basys3_top
 * ============================================================================
 *
 *  Description:
 *      Top-level module for the Basys3 FPGA implementation of the Flash
 *      Attention accelerator system.
 *
 *      The module performs three main functions:
 *
 *          1. Generates the 80 MHz system clock used by the design from the
 *             Basys3 100 MHz input clock.
 *
 *          2. Generates a synchronized active-low system reset. The reset is
 *             asserted immediately whenever the user presses the center
 *             button or the clock generator loses lock, and is released
 *             synchronously to the 80 MHz system clock.
 *
 *          3. Instantiates the UART-connected accelerator system and routes
 *             its status signals to the Basys3 LEDs.
 *
 *      LED mapping:
 *
 *          led[0] - Accelerator busy
 *          led[1] - Operation completed
 *          led[2] - Error detected
 *          led[3] - System out of reset
 *
 * In this project, AI playied a role in generating some modules. All the use of AI in modules 
 * is propperly disclaimed in three ways:
 * 
 * No AI:
 *      Author: Paulo Dietrich
 *
 * AI used to review code and discuss:
 *      Author: Paulo Dietrich, assisted by an AI agent
 *
 * AI used to generate the code:
 *      Author: Paulo Dietrich via an AI agentic workflor
 *
 * Author: Paulo Dietrich via an agentic workflow
 * ============================================================================
 */

module basys3_top (
    input  logic clk, 
    
    // Reset button
    input  logic btnC, 
    
    // UART signals
    input  logic RsRx,
    output logic RsTx,
    
    // Basys3 status LEDs
    output logic [3:0] led
);

    wire clk_80;
    wire clk_locked;

    // Generate the 80 MHz system clock from the Basys3 100 MHz input clock.
    clk_wiz_0 U_CLOCK (
        .clk_in1 (clk),
        .clk_out1(clk_80),
        .reset   (btnC),
        .locked  (clk_locked)
    );

    // Hold the system in reset while the button is pressed or the clock is unstable.
    wire reset_request = btnC | ~clk_locked;

    // Shift register used to synchronize reset release to the 80 MHz clock.
    (* ASYNC_REG = "TRUE" *)
    logic [3:0] reset_pipe = 4'b1111;

    // Assert reset asynchronously and release it synchronously.
    always_ff @(posedge clk_80 or posedge reset_request) begin
        if (reset_request)
            reset_pipe <= 4'b1111;
        else
            reset_pipe <= {reset_pipe[2:0], 1'b0};
    end

    // Active-low system reset.
    wire rst_n = ~reset_pipe[3];

    // UART interface and accelerator top-level system.
    fa_uart_top #(
        .CLK_HZ(80_000_000),
        .BAUD  (115_200)
    ) U_SYSTEM (
        .clk          (clk_80),
        .rst_n        (rst_n),
        .uart_rx_pin  (RsRx),
        .uart_tx_pin  (RsTx),
        .busy         (led[0]),
        .done_latched (led[1]),
        .error_latched(led[2])
    );

    // Indicates that the system has successfully left reset.
    assign led[3] = rst_n;

endmodule