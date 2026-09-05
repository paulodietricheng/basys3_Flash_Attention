import fa_pkg::*;

module attention_ctrl (
    input logic clk, rst_n,

    // cpu
    input  logic start,
    input  logic [MAX_SQ_LEN-1:0] tile_sq_len,
    output logic done,

    // mxu
    output logic mxu_start,
    output mxu_cmd_t mxu_cmd,
    
    // VPU
    input  logic vpu_done
);

    // Batch indexes
    logic [MAX_TILE_W-1:0] q_batch_idx;
    logic [MAX_TILE_W-1:0] kv_batch_idx;
    logic [MAX_TILE_W-1:0] batch_size;

    assign batch_size = tile_sq_len >> 3;

    // States: IDLE, COMPUTE, DONE
    typedef enum logic [1:0] {
        fa_IDLE,
        fa_COMPUTE,
        fa_DONE
    } fa_state_t ;
    
    fa_state_t curr_state;
    logic last_tile;
    
    assign last_tile = (q_batch_idx == batch_size);
    
    // state controler
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= fa_IDLE;
        end else begin
            case (curr_state) 
                fa_IDLE:
                    curr_state <= start ? fa_COMPUTE : fa_SQ_LEN;    
                    
                fa_COMPUTE: begin
                    curr_state <=  last_tile ? fa_DONE : fa_COMPUTE;
                end
                
                fa_DONE: begin
                    curr_state <= start ? fa_COMPUTE : fa_IDLE;
                end
                
            endcase
        end
    end

endmodule