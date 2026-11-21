// Sequential shift-add multiplier with a start / busy / done handshake.
module seq_mult #(
    parameter int W = 16
) (
    input  logic           clk,
    input  logic           rst_n,
    input  logic           start,
    input  logic [W-1:0]   a,
    input  logic [W-1:0]   b,
    output logic           busy,
    output logic           done,
    output logic [2*W-1:0] p
);
    localparam int CW = $clog2(W + 1);

    logic [2*W-1:0] acc, mcand;
    logic [W-1:0]   mplier;
    logic [CW-1:0]  left;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy   <= 1'b0;
            done   <= 1'b0;
            p      <= '0;
            acc    <= '0;
            mcand  <= '0;
            mplier <= '0;
            left   <= '0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                if (start) begin
                    busy   <= 1'b1;
                    acc    <= '0;
                    mcand  <= (2*W)'(a);
                    mplier <= b;
                    left   <= CW'(W);
                end
            end else begin
                if (mplier[0]) acc <= acc + mcand;
                mcand  <= mcand << 1;
                mplier <= mplier >> 1;
                left   <= left - 1'b1;
                if (left == CW'(1)) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    p    <= mplier[0] ? acc + mcand : acc;
                end
            end
        end
    end
endmodule
