`timescale 1ns/1ps
module tb_top;
    import uvm_pkg::*;
    import uart_tx_buggy_tb_pkg::*;
    logic clk = 1'b0;
    always #5.0 clk = ~clk;
    uart_tx_buggy_if ifc (clk);
    initial ifc.rst_n = 1'b0;
    uart_tx_buggy #(.CLKS_PER_BIT(4)) dut (.clk(clk), .rst_n(ifc.rst_n), .tx_valid(ifc.tx_valid), .tx_data(ifc.tx_data), .tx_ready(ifc.tx_ready), .txd(ifc.txd));
    initial begin
        uvm_config_db #(virtual uart_tx_buggy_if)::set(null, "*", "vif", ifc);
        run_test("uart_tx_buggy_test");
    end
endmodule
