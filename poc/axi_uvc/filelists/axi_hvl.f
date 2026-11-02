// Reusable AXI UVC HVL core, in compile order.
// Compile after filelists/axi_hdl.f and the simulator's UVM library (uvm_pkg).
// Use with -F: paths are relative to this file's directory.
+incdir+../hvl/types
+incdir+../hvl/api
+incdir+../hvl/adapter
+incdir+../hvl/config
+incdir+../hvl/agent
+incdir+../hvl/coverage
+incdir+../hvl/sequences
../hvl/pkg/axi_api_pkg.sv
../hvl/pkg/axi_uvc_pkg.sv
../hvl/pkg/axi_adapter_pkg.sv
