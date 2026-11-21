// UART transmitter: 8 data bits, no parity, 1 stop bit (8N1), LSB first.
// (Seeded with a realistic bug for the generator to find. See README.)
module uart_tx_buggy #(
    parameter int CLKS_PER_BIT = 4
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_valid,
    input  logic [7:0] tx_data,
    output logic       tx_ready,
    output logic       txd
);
    localparam int CW = $clog2(CLKS_PER_BIT);

    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t        state;
    logic [CW-1:0] tick;        // clocks spent in the current bit
    logic [2:0]    bit_idx;
    logic [7:0]    shreg;

    wire bit_done = (tick == CW'(CLKS_PER_BIT - 1));

    assign tx_ready = (state == IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            tick    <= '0;
            bit_idx <= '0;
            shreg   <= '0;
            txd     <= 1'b1;
        end else begin
            tick <= bit_done ? '0 : tick + 1'b1;
            case (state)
                IDLE: begin
                    tick <= '0;
                    txd  <= 1'b1;
                    if (tx_valid) begin
                        shreg <= tx_data;
                        state <= START;
                        txd   <= 1'b0;
                    end
                end
                START: if (bit_done) begin
                    state   <= DATA;
                    bit_idx <= '0;
                    txd     <= shreg[0];
                end
                DATA: if (bit_done) begin
                    if (bit_idx == 3'd7) begin
                        state <= STOP;
                        txd   <= 1'b1;
                    end else begin
                        bit_idx <= bit_idx + 1'b1;
                        txd     <= shreg[bit_idx + 1'b1];
                    end
                end
                STOP: if (tick == CW'(CLKS_PER_BIT - 2)) state <= IDLE;
            endcase
        end
    end
endmodule
