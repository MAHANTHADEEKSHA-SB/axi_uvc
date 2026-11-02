// HDL-only smoke: reusable core + example top + smoke test (no UVM).
// Use with -F: paths are relative to this file's directory.
-F axi_hdl.f
../examples/axi_hdl_top.sv
../tests/axi_hdl_smoke.sv
