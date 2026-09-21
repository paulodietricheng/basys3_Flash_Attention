`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/26/2026 10:04:57 AM
// Design Name: 
// Module Name: fa_pkg
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


package fa_pkg;
    
    //=============================================================================
    // Model Precision
    //============================================================================
    localparam OPERAND_W  = 8; // INT8
    localparam ACC_W      = 32; // INT32
    localparam D_MODEL    = 16;
    localparam TOKEN_SIZE = OPERAND_W * D_MODEL; //bits

    //=============================================================================
    // BRAM organization
    //============================================================================
    localparam BUF_PORT_W = 32;
    localparam BUF_DEPTH = 1024;
    localparam NUM_PORTS = 2;
    
    localparam WPA = BUF_PORT_W / OPERAND_W;
    localparam WPA_W = $clog2(WPA);
    
    localparam BUF_ADDR_W = $clog2(BUF_DEPTH);
    
    localparam BUF_SIZE = BUF_PORT_W * BUF_DEPTH; //bits
    
    //=============================================================================
    // Buffer organization
    //============================================================================
    localparam NUM_BUF = 4;
    localparam BATCH_SIZE = 8;
    localparam MAX_TOKENS = BUF_SIZE / TOKEN_SIZE;
    
    localparam ADDR_PER_DIM = MAX_TOKENS / WPA;
    localparam ADDR_PER_DIM_W = $clog2(ADDR_PER_DIM);
    
    // ============================================================================
    // Systolic Array
    // ============================================================================
       
    // Input matrices bus widths
    
    // The maximum size of a result of a MxKxN GEMM is a MxN
    // matrix, thus, as the os systolic array produces at max 
    // an SA_SIZE x SA_SIZE matrix, 
    localparam SA_COLS    = 8;
    localparam SA_ROWS    = 8;
    
    localparam M_W = $clog2(MAX_TOKENS + 1); // + 1 to range from 1
    localparam N_W = $clog2(MAX_TOKENS + 1); // to MAX_TOKENS.
    localparam K_W = $clog2(D_MODEL + 1); 
    
    typedef logic [M_W-1:0] m_dim_t;
    typedef logic [N_W-1:0] n_dim_t;
    typedef logic [K_W-1:0] k_dim_t;
    
    typedef struct packed {
        // Matrix dimensions 
        m_dim_t m;
        n_dim_t n;
        k_dim_t k;
        
        // Matrix A
        m_dim_t a_m_offset;
        k_dim_t a_k_offset;
        
        // Matrix B
        k_dim_t b_k_offset;
        n_dim_t b_n_offset;
                
        // Matrix C
        m_dim_t c_m_offset;
        n_dim_t c_n_offset;
        
    } mxu_cmd_t ;

    // Total result latency from first PE token to final valid result.
    localparam RESULT_LAT_W = $clog2(2*SA_ROWS + SA_COLS + D_MODEL - 2);

    // ============================================================================
    // Scalar datatypes
    // ============================================================================
    typedef logic signed [OPERAND_W-1:0]   operand_t;
    typedef logic signed [ACC_W-1:0]       accumulator_t;
    typedef logic        [BUF_PORT_W-1:0]  buf_word_t;
    
    //=============================================================================
    // Tile Organization
    //============================================================================
    localparam int MAX_TILE = (BUF_DEPTH * WPA) / (SA_COLS * D_MODEL);
    localparam int MAX_TILE_W = $clog2(MAX_TILE);
    localparam int MAX_TILE_SQ_LEN_W = BUF_SIZE / TOKEN_SIZE; //bits
    
    // ============================================================================
    // VPU
    // ============================================================================
    localparam row_idx_w = $clog2(SA_ROWS);
    localparam colg_idx_w = $clog2(D_MODEL / (NUM_PORTS * WPA));
    localparam V_IDX_W = row_idx_w + colg_idx_w;

endpackage
