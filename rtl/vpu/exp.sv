//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.08.2026 18:55:25
// Design Name: 
// Module Name: exp
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

module exp (
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
        e_IDLE,
        e_COMPUTE,
        e_DONE
    } exp_state_t ;
    
    exp_state_t curr_state;
    
    // Place holder computation
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            in_reg <= 1'b0;
            
            busy <= 1'b0;
            done <= 1'b0;
            
            out <= '0;
            
            curr_state <= e_IDLE;
        end else begin
            case (curr_state)
                e_IDLE: begin
                    in_reg <= 1'b0;
            
                    busy <= 1'b0;
                    done <= 1'b0;
                    
                    out <= '0;
                    
                    if (start) begin
                        in_reg <= in;
                        busy <= 1'b1;
                        curr_state <= e_COMPUTE;
                    end
                end
                
                e_COMPUTE: begin
                    out  <= in_reg + 1;
                    curr_state <= e_DONE;               
                end
                
                e_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    curr_state <= e_IDLE;
                end
            endcase
        end
    end
endmodule