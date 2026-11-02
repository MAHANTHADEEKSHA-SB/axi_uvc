// -----------------------------------------------------------------------------
// axi_drive_proxy_base — abstract AXI Manager drive capability (ADR-001, ADR-002)
//
// Not parameterized by bus width. The Manager driver holds only this handle;
// a width-specialized adapter (axi_adapter_pkg::axi_drive_proxy) implements
// it over a typed virtual Manager-BFM handle. Neither a monitor nor the
// Subordinate role receives this type.
// Included by axi_api_pkg.
// -----------------------------------------------------------------------------

virtual class axi_drive_proxy_base extends uvm_object;

  // Policies copied from axi_agent_cfg by the driver (AXI_PROTOCOL_CONTRACT)
  int unsigned max_wait_cycles = 1024;  // POL-01: TIMEOUT after this many stalled cycles; 0 = off
  bit          allow_x_wdata   = 1'b0;  // section 6: X/Z write data only for fault injection

  function new(string name = "axi_drive_proxy_base");
    super.new(name);
  endfunction

  // Physical parameters of the bound bus (CFG-06 cross-checks)
  pure virtual function int unsigned get_addr_width();
  pure virtual function int unsigned get_data_width();
  pure virtual function int unsigned get_id_w_width();
  pure virtual function int unsigned get_id_r_width();

  // Push the instance feature set to the BFM; 0 = rejected
  pure virtual function bit configure(axi_features_t features);

  // 1: drive the bus; 0: release every Manager output to 'z
  pure virtual function void set_enable(bit en);

  // Deliberate protocol faults for negative tests
  pure virtual function void set_fault(axi_fault_e fault);

  // RST-5: return once reset is released, plus idle_cycles ACLK edges
  pure virtual task wait_for_reset_release(int unsigned idle_cycles);

  // Run one transaction (write or read). Fills req.bresp or req.rdata/rresp,
  // resp_id, beats_done, the wait counts and status (AXI_ST_BAD_REQUEST when the
  // request cannot be driven losslessly or legally).
  pure virtual task send(axi_transaction req);

endclass : axi_drive_proxy_base
