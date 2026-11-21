`timescale 1ns/1ps
module tb_top;
    import uvm_pkg::*;
    import sync_fifo_tb_pkg::*;
    logic clk = 1'b0;
    always #5.0 clk = ~clk;
    sync_fifo_if ifc (clk);
    initial ifc.rst_n = 1'b0;
    sync_fifo #(.W(8), .DEPTH(8)) dut (.clk(clk), .rst_n(ifc.rst_n), .wr_valid(ifc.wr_valid), .wr_data(ifc.wr_data), .rd_ready(ifc.rd_ready), .wr_ready(ifc.wr_ready), .rd_valid(ifc.rd_valid), .rd_data(ifc.rd_data), .count(ifc.count));
    initial begin
        uvm_config_db #(virtual sync_fifo_if)::set(null, "*", "vif", ifc);
        run_test("sync_fifo_test");
    end
endmodule
