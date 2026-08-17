//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.08.2026 18:55:25
// Design Name: 
// Module Name: rcp
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

module rcp (
    input  logic clk, rst_n,
    
    input  logic start,
    output logic busy,
    output logic done,
    
    input  logic [31:0] in,
    output logic [31:0] out
);

    // Register the request
    logic [31:0] in_reg;
    
    // States
    typedef enum logic [1:0] {
        r_IDLE,
        r_COMPUTE,
        r_DONE
    } rcp_state_t ;
    
    rcp_state_t curr_state;
    
    // Place holder computation
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            in_reg <= 1'b0;
            
            busy <= 1'b0;
            done <= 1'b0;
            
            out <= '0;
            
            curr_state <= r_IDLE;
        end else begin
            case (curr_state)
                r_IDLE: begin
                    in_reg <= 1'b0;
            
                    busy <= 1'b0;
                    done <= 1'b0;
                    
                    out <= '0;
                    
                    if (start) begin
                        in_reg <= in;
                        busy <= 1'b1;
                        curr_state <= r_COMPUTE;
                    end
                end
                
                r_COMPUTE: begin
                    out  <= in_reg - 2;
                    done <= 1'b1;
                    curr_state <= r_DONE;               
                end
                
                r_DONE: begin
                    busy <= 1'b0;
                    curr_state <= r_IDLE;
                end
            endcase
        end
    end
endmodule