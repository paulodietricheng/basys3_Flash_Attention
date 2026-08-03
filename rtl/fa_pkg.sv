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

    // ------------------------------------------------------------
    // Public architectural parameters (unify sram addressing space)
    // ------------------------------------------------------------
    localparam SA_COLS    = 8;
    localparam SA_ROWS    = 8;
    localparam D_MODEL    = 16;
    
    // Model precision parameters
    localparam OPERAND_W  = 8; // INT8
    localparam ACC_W      = 32; // INT32

    //=============================================================================
    // BRAM organization
    //=============================================================================
    
    // Bram parameters
    localparam BRAM_WORD_W = 32;
    localparam BRAM_DEPTH  = 1024;
    
    // Capacity of one BRAM primitive
    localparam BRAM_BYTE_COUNT = BRAM_DEPTH * (BRAM_WORD_W / 8);
    localparam BRAM_BC_W       = $clog2(BRAM_BYTE_COUNT);
    
    //=============================================================================
    // On-chip SRAM
    //=============================================================================
    
    localparam int NUM_BUF = 4;
   
    // Four BRAMs combined into one SRAM buffer
    localparam SRAM_WORD_W = 32;
    localparam SRAM_DEPTH  = NUM_BUF * BRAM_DEPTH;
    localparam SRAM_ADDR_W = $clog2(BRAM_DEPTH);
    
    //=============================================================================
    // Fake HBM organization
    //=============================================================================
    //
    // The HBM model is composed of 16 BRAM primitives:
    //
    //   - 4 BRAMs : Query  (Q)
    //   - 4 BRAMs : Key    (K)
    //   - 4 BRAMs : Value  (V)
    //   - 4 BRAMs : Output (O)
    //
    // Therefore each matrix occupies four BRAM primitives.
    //=============================================================================
    
    localparam HBM_DEPTH      = 16 * BRAM_DEPTH;
    localparam HBM_ADDR_W     = $clog2(HBM_DEPTH);
    localparam HBM_BYTE_COUNT = HBM_DEPTH * (BRAM_WORD_W / 8);
    
    // Number of BRAMs allocated to each matrix
    localparam BRAMS_PER_MATRIX = 4;
    
    // Storage available for a single matrix (Q, K, V or O)
    localparam MATRIX_BYTE_COUNT = HBM_BYTE_COUNT / BRAMS_PER_MATRIX;
    
    //=============================================================================
    // Tiling parameters
    //=============================================================================
    
    // Storage required for one token (embedding vector)
    localparam BYTES_PER_TOKEN = (D_MODEL * OPERAND_W) / 8;
    
    // Maximum sequence length that fits entirely in one matrix stored in HBM
    localparam MAX_SQ_LEN = MATRIX_BYTE_COUNT / BYTES_PER_TOKEN;
    localparam MAX_SQ_L_W = $clog2(MAX_SQ_LEN);
    
    // Maximum sequence length that fits in one BRAM tile
    localparam MAX_TILE_SQ_LEN = BRAM_BYTE_COUNT / BYTES_PER_TOKEN;
    localparam MAX_TSQ_L_W = $clog2(MAX_TILE_SQ_LEN);
    
    // Number of BRAM tiles required to process the largest sequence stored in HBM.
    localparam MAX_TILE_COUNT = (MAX_SQ_LEN + MAX_TILE_SQ_LEN - 1) / MAX_TILE_SQ_LEN;
    localparam MAX_TC_W = $clog2(MAX_TILE_COUNT);
    
    // Number of MXU subtiles (SA_ROWS tokens per subtile) required to process
    // the largest BRAM tile.
    localparam MAX_STILE_COUNT = (MAX_TILE_SQ_LEN + SA_ROWS - 1) / SA_ROWS;
    localparam MAX_STC_W = $clog2(MAX_STILE_COUNT);
    
    // ------------------------------------------------------------
    // Systolic Array
    // ------------------------------------------------------------
       
    // Input matrices bus widths
    
    // The maximum size of a result of a MxKxN GEMM is a MxN
    // matrix, thus, as the os systolic array produces at max 
    // an SA_SIZE x SA_SIZE matrix, 
    
    localparam M_W = $clog2(SA_COLS + 1); // + 1 to range from 1
    localparam N_W = $clog2(SA_ROWS + 1); // to SA_SIZE.
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
    
    // DMA request
    typedef struct packed {
        logic direction; // 0 = HBM -> SRAM, 1 = SRAM -> HBM
        logic transpose; // 0 = false, 1 = true
        
        // Base addresses
        logic [HBM_ADDR_W-1:0] hbm_base_addr;
        logic [SRAM_ADDR_W-1:0] sram_base_addr;
        
        logic [BRAM_BC_W-1:0] byte_count;
    } dma_rq_t ;

    // Systolic latency parameter
    localparam DSP_LAT = 4;

    // Total result latency from first PE token to final valid result.
    localparam RESULT_LAT_W = $clog2(2*SA_ROWS + SA_COLS + D_MODEL - 2);

    // Scalar data types
    typedef logic signed [OPERAND_W-1:0] operand_t;
    typedef logic signed [ACC_W-1:0]     accumulator_t;
    typedef logic [SRAM_WORD_W-1:0]      sram_word_t;
    typedef logic [BRAM_WORD_W-1:0]      bram_word_t;
endpackage
