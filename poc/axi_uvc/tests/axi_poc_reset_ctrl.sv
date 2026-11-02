// -----------------------------------------------------------------------------
// axi_poc_reset_ctrl — abstract handle for pulsing an instance's reset
//
// A package cannot hold hierarchical references to the design, so tests reach
// the reset generators of examples/axi_hdl_top through this capability. The
// HVL top implements it (it may use hierarchical references, LANG-12) and
// registers it under uvm_test_top, field "reset_ctrl". Test code only.
// Included by axi_poc_test_pkg.
// -----------------------------------------------------------------------------

virtual class axi_poc_reset_ctrl extends uvm_object;

  function new(string name = "axi_poc_reset_ctrl");
    super.new(name);
  endfunction

  // Assert ARESETn of instance inst ("a" or "b") now, release it on a falling
  // ACLK edge after `cycles` rising edges (RST-2).
  pure virtual task pulse_reset(string inst, int unsigned cycles);

endclass : axi_poc_reset_ctrl
