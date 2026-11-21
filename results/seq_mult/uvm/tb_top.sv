`timescale 1ns/1ps
module tb_top;
    import uvm_pkg::*;
    import seq_mult_tb_pkg::*;
    logic clk = 1'b0;
    always #5.0 clk = ~clk;
    seq_mult_if ifc (clk);
    initial ifc.rst_n = 1'b0;
    seq_mult #(.W(16)) dut (.clk(clk), .rst_n(ifc.rst_n), .start(ifc.start), .a(ifc.a), .b(ifc.b), .busy(ifc.busy), .done(ifc.done), .p(ifc.p));
    initial begin
        uvm_config_db #(virtual seq_mult_if)::set(null, "*", "vif", ifc);
        run_test("seq_mult_test");
    end
endmodule
