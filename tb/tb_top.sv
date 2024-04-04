//------------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg :: *;
//------------------------------------------------------------------------------
`include "axi_defines.svh"
`include "axi_interface.sv"
//------------------------------------------------------------------------------
module tb_top;
   bit clk;
   bit rst_n;

   initial begin
       clk = 1'b1;
       rst = 1'b1;
   end

   always #5 clk = ~clk;

   initial begin
       run_test();
   end
endmodule : tb_top
