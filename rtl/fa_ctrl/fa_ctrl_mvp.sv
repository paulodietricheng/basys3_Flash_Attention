import fa_pkg::*;

module fa_ctrl_mvp (
    input logic clk, rst_n,

    // cpu
    input  logic fa_start,
    output logic fa_done,

    // mxu
    output logic mxu_start,
    output mxu_cmd_t mxu_cmd,
    
    // VPU
    input  logic vpu_done,

    // sram_controller
    input logic Q_tile_done,
    input logic KV_tile_done
);

// Implement the simple flash attention algorithim. Double buffering,
// DMA loads, and CPU interfacing shall be implemented in V2. 

    // Subtile Counter
    logic [MAX_STC_W-1:0] stile_count;

    // Indexes  
    logic [MAX_STC_W-1:0] q_subtile_idx;
    logic [MAX_STC_W-1:0] kv_subtile_idx;

    // Compute subtile count given the sequence length, assuming each 
    // vector spans D_MODEL / WPA addresses. 
    
    // FSM states: IDLE, ATTENTION, DONE.
    
    // In Attention state, need to perform an outer loop over Q and 
    // Inner loop over kv, updating the idxes. At every vpu_done, 
    // increment kv_idx + 1. once vpu done && kv_idx = stile_count,
    // increment q_idx + 1. Loop until q_idx == stile_count, then output 
    // fa_done. This will eventually trigger the load KV, and will repeat.
    // Once KV_idx is == KV_tile count, then increment the Q_tile count. 
    // So the work division should be: this module should be the inner tile
    // scheduler, and the other module should be the outer tile scheduler. 
    
    // Perhaps having a tile scheduler for memory management and an
    // attention controller would be best? So the tile scheduler would
    // Worry about Q, KV loads, and the attention controller would just
    // Controll the on chip computation? so this module should be actually
    // the attention controller, and there should be another called tile sch,
    // and they could be a part of a bigger block called control. 

endmodule

    