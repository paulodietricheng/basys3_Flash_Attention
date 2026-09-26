import fa_pkg::*;

module attention_ctrl (
    input logic clk, rst_n,

    // cpu
    input  logic start,
    input  logic [MAX_TILE_SQ_LEN_W-1:0] tile_sq_len,
    output logic busy,
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
    logic [MAX_TILE_W-1:0] num_batches;

    localparam SHIFT = $clog2(BATCH_SIZE);

    assign num_batches = tile_sq_len >> SHIFT; 

    typedef enum logic [1:0] {
        fa_IDLE,
        fa_SEND_CMD,
        fa_COMPUTE,
        fa_DONE
    } fa_state_t ;
    
    fa_state_t curr_state;
       
    assign busy = (curr_state != fa_IDLE) && (curr_state != fa_DONE);

    assign done = (curr_state == fa_DONE);
            
    // state controler
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mxu_cmd <= '0;
            mxu_start <= '0;
            q_batch_idx <= '0;
            kv_batch_idx <= '0;
            
            curr_state <= fa_IDLE;
        end else begin
            mxu_start <= 1'b0;
            case (curr_state) 
                fa_IDLE: begin
                    mxu_cmd <= '0;
                    mxu_start <= '0;
                    if (start) begin
                        q_batch_idx  <= '0;
                        kv_batch_idx <= '0;
                        curr_state   <= fa_SEND_CMD;
                    end
                end   
                
                fa_SEND_CMD: begin
                    mxu_cmd.m <= SA_ROWS;
                    mxu_cmd.n <= SA_COLS;
                    mxu_cmd.k <= D_MODEL;
                    mxu_cmd.a_m_offset <= BATCH_SIZE * q_batch_idx;
                    mxu_cmd.a_k_offset <= '0;
                    mxu_cmd.b_k_offset <= '0;
                    mxu_cmd.b_n_offset <= BATCH_SIZE * kv_batch_idx;

                    mxu_start <= 1'b1;
                    
                    curr_state <= fa_COMPUTE;
                end
                
                fa_COMPUTE: begin
                    if (vpu_done) begin
                        if(kv_batch_idx == num_batches - 1) begin
                            q_batch_idx <= q_batch_idx + 1;
                            kv_batch_idx <= '0;
                            if(q_batch_idx == num_batches - 1) begin
                                q_batch_idx <= '0;
                                curr_state <= fa_DONE;
                            end else begin
                                curr_state <= fa_SEND_CMD;
                            end            
                        end else begin
                            kv_batch_idx <= kv_batch_idx + 1;
                            
                            curr_state <= fa_SEND_CMD;
                        end                           
                    end else
                        curr_state <= fa_COMPUTE;
                end
                
                fa_DONE: begin
                    curr_state <= fa_IDLE;
                end    
            endcase
        end
    end
endmodule