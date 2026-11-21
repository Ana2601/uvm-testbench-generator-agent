// APB3 register block: control, data, a write counter and a write-1-to-clear status.
module apb_regs (
    input  logic        pclk,
    input  logic        presetn,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [3:0]  paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr
);
    localparam logic [3:0] A_CTRL = 4'h0, A_DATA = 4'h4, A_WCNT = 4'h8, A_STAT = 4'hC;

    logic [7:0]  ctrl;          // RW, 8 bits
    logic [31:0] data;          // RW
    logic [15:0] wcnt;          // RO: number of successful writes to DATA
    logic [1:0]  stat;          // W1C: bit0 set by a DATA write, bit1 set by a CTRL write

    wire access = psel && penable;
    wire valid  = (paddr == A_CTRL) || (paddr == A_DATA) || (paddr == A_WCNT) || (paddr == A_STAT);
    wire wr     = access && pwrite && valid && (paddr != A_WCNT);

    assign pready  = 1'b1;
    assign pslverr = access && (!valid || (pwrite && paddr == A_WCNT));

    always_comb begin
        case (paddr)
            A_CTRL:  prdata = {24'b0, ctrl};
            A_DATA:  prdata = data;
            A_WCNT:  prdata = {16'b0, wcnt};
            A_STAT:  prdata = {30'b0, stat};
            default: prdata = '0;
        endcase
    end

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ctrl <= '0;
            data <= '0;
            wcnt <= '0;
            stat <= '0;
        end else if (wr) begin
            case (paddr)
                A_CTRL: begin ctrl <= pwdata[7:0]; stat[1] <= 1'b1; end
                A_DATA: begin data <= pwdata; wcnt <= wcnt + 1'b1; stat[0] <= 1'b1; end
                A_STAT: stat <= stat & ~pwdata[1:0];
                default: ;
            endcase
        end
    end
endmodule
