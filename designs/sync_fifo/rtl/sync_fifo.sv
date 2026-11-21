// Synchronous FIFO with valid/ready on both sides and first-word fall-through.
module sync_fifo #(
    parameter int W     = 8,
    parameter int DEPTH = 8                  // power of two
) (
    input  logic                     clk,
    input  logic                     rst_n,
    // write side
    input  logic                     wr_valid,
    input  logic [W-1:0]             wr_data,
    output logic                     wr_ready,
    // read side
    output logic                     rd_valid,
    output logic [W-1:0]             rd_data,
    input  logic                     rd_ready,
    // status
    output logic [$clog2(DEPTH):0]   count
);
    localparam int AW = $clog2(DEPTH);

    logic [W-1:0]  mem [DEPTH];
    logic [AW-1:0] wptr, rptr;

    wire push = wr_valid && wr_ready;
    wire pop  = rd_valid && rd_ready;

    assign wr_ready = (count != (AW+1)'(DEPTH));
    assign rd_valid = (count != '0);
    assign rd_data  = mem[rptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr  <= '0;
            rptr  <= '0;
            count <= '0;
        end else begin
            if (push) wptr <= wptr + 1'b1;
            if (pop)  rptr <= rptr + 1'b1;
            case ({push, pop})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: ;
            endcase
        end
    end

    always_ff @(posedge clk)
        if (push) mem[wptr] <= wr_data;
endmodule
