// -----------------------------------------------------------------------------
// axi_monitor_proxy_base — abstract AXI observe capability (ADR-001, ADR-002)
//
// Not parameterized by bus width. The UVM monitor holds only this handle; a
// width-specialized adapter (axi_adapter_pkg::axi_monitor_proxy) implements
// it over a typed virtual monitor-BFM handle. It offers no drive or respond
// operation.
// Included by axi_api_pkg.
// -----------------------------------------------------------------------------

virtual class axi_monitor_proxy_base extends uvm_object;

  function new(string name = "axi_monitor_proxy_base");
    super.new(name);
  endfunction

  // Physical parameters of the bound bus (CFG-03/04/06 checks)
  pure virtual function int unsigned get_addr_width();
  pure virtual function int unsigned get_data_width();
  pure virtual function int unsigned get_id_w_width();
  pure virtual function int unsigned get_id_r_width();

  // Push the instance feature set to the BFM; 0 = rejected
  pure virtual function bit configure(axi_features_t features);

  // Enable the BFM observation queues (only once a consumer exists)
  pure virtual function void set_publish(bit en);

  // Print each protocol violation from the BFM as it happens
  pure virtual function void set_verbose(bit en);

  // Blocks until the next completed transaction; returns a new object per call
  pure virtual task receive(output axi_transaction observed);

  // Blocks until the next reset edge after the first release (RST-4); new object
  pure virtual task wait_reset_event(output axi_reset_event ev);

  // Protocol violations detected by the BFM (axi_bfm_pkg::axi_mon_error_e)
  pure virtual function int unsigned get_error_count(axi_mon_error_e code);
  pure virtual function int unsigned get_total_errors();
  pure virtual function void         clear_errors();

  // Activity counters kept by the BFM
  pure virtual function int unsigned get_transfer_count();  // completed transactions
  pure virtual function int unsigned get_reset_count();     // resets after the first release
  pure virtual function int unsigned get_open_count();      // started, not completed

endclass : axi_monitor_proxy_base
