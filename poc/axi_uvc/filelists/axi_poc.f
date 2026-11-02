// Full UVM POC: reusable HDL + HVL core, example HDL top, tests, HVL top.
// Tops: axi_hdl_top axi_hvl_top. UVM library supplied by the simulator.
// Use with -F: paths are relative to this file's directory.
-F axi_hdl.f
-F axi_hvl.f
../examples/axi_hdl_top.sv
+incdir+../tests
../tests/axi_poc_test_pkg.sv
../examples/axi_hvl_top.sv
