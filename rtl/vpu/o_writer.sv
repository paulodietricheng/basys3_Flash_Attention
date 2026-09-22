module o_writer (
    input  logic clk,
    input  logic rst_n,

    // VPU
    input  operand_t o_in [SA_ROWS][D_MODEL],
    input  logic     vpu_done,

    // SRAM: word-addressed, row-major layout
    output logic [BUF_ADDR_W-1:0] wr_addr  [NUM_PORTS],
    output logic                  we       [NUM_PORTS],
    output buf_word_t             embd_out [NUM_PORTS],

    // Attention control
    output logic o_write_done
);

    localparam int D_WIDTH = $clog2(D_MODEL);

    localparam int V_WIDTH = $clog2(BATCH_SIZE);

    localparam int DIMS_PER_WRITE = NUM_PORTS * WPA;

    typedef enum logic [1:0] {
        o_IDLE,
        o_WRITE,
        o_DONE
    } state_t;

    state_t curr_state;

    logic [D_WIDTH-1:0]    d_idx;
    logic [V_WIDTH-1:0]    v_idx;
    logic [BUF_ADDR_W-1:0] word_addr;

    operand_t o_reg [SA_ROWS][D_MODEL];

    // Capture only when accepting a new operation.
    always_ff @(posedge clk) begin
        if (rst_n && (curr_state == o_IDLE) && vpu_done) begin
            for (int r = 0; r < SA_ROWS; r++) begin
                for (int c = 0; c < D_MODEL; c++) begin
                    o_reg[r][c] <= o_in[r][c];
                end
            end
        end
    end

    // State, operand indices, and running SRAM word address.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= o_IDLE;
            d_idx      <= '0;
            v_idx      <= '0;
            word_addr  <= '0;
        end else begin
            case (curr_state)
                o_IDLE: begin
                    d_idx     <= '0;
                    v_idx     <= '0;
                    word_addr <= '0;

                    if (vpu_done)
                        curr_state <= o_WRITE;
                end

                o_WRITE: begin
                    if (d_idx == D_MODEL - DIMS_PER_WRITE) begin
                        d_idx <= '0;

                        if (v_idx == BATCH_SIZE - 1) begin
                            curr_state <= o_DONE;
                        end else begin
                            v_idx <= v_idx + 1'b1;
                            word_addr <= word_addr + BUF_ADDR_W'(NUM_PORTS);
                        end
                    end else begin
                        d_idx <= d_idx + D_WIDTH'(DIMS_PER_WRITE);
                        word_addr <= word_addr + BUF_ADDR_W'(NUM_PORTS);
                    end
                end

                o_DONE: begin
                    curr_state <= o_IDLE;
                end

                default: begin
                    curr_state <= o_IDLE;
                    d_idx      <= '0;
                    v_idx      <= '0;
                    word_addr  <= '0;
                end
            endcase
        end
    end

    assign o_write_done = rst_n && (curr_state == o_DONE);

    generate
        for (genvar p = 0; p < NUM_PORTS; p++) begin : GEN_PORTS
            assign we[p] = rst_n && (curr_state == o_WRITE);

            // Consecutive ports write consecutive packed SRAM words.
            assign wr_addr[p] =  we[p] ? (word_addr + BUF_ADDR_W'(p)) : '0;

            for (genvar b = 0; b < WPA; b++) begin : GEN_OPERANDS
                // All multiplication here is evaluated at elaboration.
                localparam int DIM_OFFSET = p * WPA + b;
                localparam int SLICE_MSB  = BUF_PORT_W - 1 - b * OPERAND_W;

                // Smallest dimension occupies the most significant bits.
                assign embd_out[p][SLICE_MSB -: OPERAND_W] =  we[p] ? o_reg[v_idx][d_idx + DIM_OFFSET] : '0;
            end
        end
    endgenerate

endmodule