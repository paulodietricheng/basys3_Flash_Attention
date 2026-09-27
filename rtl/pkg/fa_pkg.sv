`timescale 1ns/1ps
package fa_pkg;
    localparam OPERAND_W = 8;
    localparam ACC_W = 32;
    localparam D_MODEL = 16;
    localparam TOKEN_SIZE = OPERAND_W * D_MODEL;
    localparam BUF_PORT_W = 32;
    localparam BUF_DEPTH = 1024;
    localparam NUM_PORTS = 2;
    localparam WPA = BUF_PORT_W / OPERAND_W;
    localparam WPA_W = $clog2(WPA);
    localparam BUF_ADDR_W = $clog2(BUF_DEPTH);
    localparam BUF_SIZE = BUF_PORT_W * BUF_DEPTH;
    localparam NUM_BUF = 4;
    localparam BATCH_SIZE = 8;
    localparam MAX_TOKENS = BUF_SIZE / TOKEN_SIZE;
    localparam ADDR_PER_DIM = MAX_TOKENS / WPA;
    localparam ADDR_PER_DIM_W = $clog2(ADDR_PER_DIM);
    localparam SA_COLS = 8;
    localparam SA_ROWS = 8;
    localparam M_W = $clog2(MAX_TOKENS + 1);
    localparam N_W = $clog2(MAX_TOKENS + 1);
    localparam K_W = $clog2(D_MODEL + 1);
    typedef logic [M_W-1:0] m_dim_t;
    typedef logic [N_W-1:0] n_dim_t;
    typedef logic [K_W-1:0] k_dim_t;
    typedef struct packed {
        m_dim_t m;
        n_dim_t n;
        k_dim_t k;
        m_dim_t a_m_offset;
        k_dim_t a_k_offset;
        k_dim_t b_k_offset;
        n_dim_t b_n_offset;
        m_dim_t c_m_offset;
        n_dim_t c_n_offset;
    } mxu_cmd_t;
    localparam RESULT_LAT_W = $clog2(2*SA_ROWS + SA_COLS + D_MODEL - 2);
    typedef logic signed [OPERAND_W-1:0] operand_t;
    typedef logic signed [ACC_W-1:0] accumulator_t;
    typedef logic [BUF_PORT_W-1:0] buf_word_t;
    // Default is the supplied integer-placeholder behavior. Q16 is only a
    // selectable validation format, not a claimed final precision choice.
`ifdef FA_REFERENCE_Q16
    localparam int FRAC_BITS = 16;
`else
    localparam int FRAC_BITS = 0;
`endif
    function automatic accumulator_t acc_mul(input accumulator_t a, b);
        logic signed [2*ACC_W-1:0] product;
        product = a * b;
        return accumulator_t'(product >>> FRAC_BITS);
    endfunction
    localparam int MAX_TILE = (BUF_DEPTH * WPA) / (SA_COLS * D_MODEL);
    localparam int MAX_TILE_W = $clog2(MAX_TILE);
    localparam int BATCH_COUNT_W = $clog2(MAX_TILE + 1);
    localparam int MAX_TILE_SQ_LEN_W = $clog2(MAX_TOKENS + 1);
    localparam row_idx_w = $clog2(SA_ROWS);
    localparam colg_idx_w = $clog2(D_MODEL / (NUM_PORTS * WPA));
    localparam V_IDX_W = $clog2(SA_COLS * ((D_MODEL + NUM_PORTS*WPA-1)/(NUM_PORTS*WPA)));
endpackage
