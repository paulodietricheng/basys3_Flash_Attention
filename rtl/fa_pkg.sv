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
    // Public architectural parameters
    // ------------------------------------------------------------
    localparam SA_COLS    = 8;
    localparam SA_ROWS    = 8;
    localparam D_MODEL    = 16;
    localparam OPERAND_W  = 8; // INT8
    localparam ACC_W      = 32; // INT32
    localparam SRAM_WORD_W = 32;

    // ------------------------------------------------------------
    // Systolic Array
    // ------------------------------------------------------------

    // DON'T TOUCH
    
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
    
    // Words per SRAM address.
    localparam WPA = SRAM_WORD_W / OPERAND_W;
    
    // Address width of pingpong buffer
    localparam ADDR_W = $clog2(1024);

    // Width of a full vector sent into the operand handler.
    localparam OPERAND_BUS_W = SA_ROWS * OPERAND_W;

    // Systolic latency parameter
    localparam DSP_LAT = 4;

    // Total result latency from first PE token to final valid result.
    localparam RESULT_LAT_W = $clog2(SA_ROWS + SA_COLS + D_MODEL - 2 + DSP_LAT + SA_COLS);

    // Scalar data types
    typedef logic signed [OPERAND_W-1:0] operand_t;
    typedef logic signed [ACC_W-1:0]     accumulator_t;
    typedef logic [SRAM_WORD_W-1:0]      sram_word_t;

    // Vector with N operands
    typedef logic [OPERAND_BUS_W-1:0] operand_bus_t;

endpackage
