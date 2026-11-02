// -----------------------------------------------------------------------------
// axi_fake_proxies — test doubles of the three capability classes
//
// Report any widths without an HDL instance, so axi_cfg_negative_test can
// exercise the axi_agent_cfg legality checks (CFG-01..04, CFG-06, CFG-07) for
// widths that cannot be instantiated legally. Never connected to a bus.
// Contains axi_fake_drive_proxy, axi_fake_respond_proxy and
// axi_fake_monitor_proxy (FILE-02 helpers).
// Included by axi_poc_test_pkg.
// -----------------------------------------------------------------------------

class axi_fake_drive_proxy extends axi_drive_proxy_base;
  int unsigned aw = 32;
  int unsigned dw = 32;
  int unsigned iw = 4;
  int unsigned ir = 4;

  function new(string name = "axi_fake_drive_proxy");
    super.new(name);
  endfunction

  // The width getters return the knobs above; every other method is an inert stub.
  virtual function int unsigned get_addr_width();
    return aw;
  endfunction

  virtual function int unsigned get_data_width();
    return dw;
  endfunction

  virtual function int unsigned get_id_w_width();
    return iw;
  endfunction

  virtual function int unsigned get_id_r_width();
    return ir;
  endfunction

  virtual function bit configure(axi_features_t features);
    return 1'b1;
  endfunction

  virtual function void set_enable(bit en);
  endfunction

  virtual function void set_fault(axi_fault_e fault);
  endfunction

  virtual task wait_for_reset_release(int unsigned idle_cycles);
  endtask

  virtual task send(axi_transaction req);
    req.status = AXI_ST_NOT_ENABLED;
  endtask
endclass : axi_fake_drive_proxy


// Respond-side double with the same width knobs; it never holds a request.
class axi_fake_respond_proxy extends axi_respond_proxy_base;
  int unsigned aw = 32;
  int unsigned dw = 32;
  int unsigned iw = 4;
  int unsigned ir = 4;

  function new(string name = "axi_fake_respond_proxy");
    super.new(name);
  endfunction

  // The width getters return the knobs above; every other method is an inert stub.
  virtual function int unsigned get_addr_width();
    return aw;
  endfunction

  virtual function int unsigned get_data_width();
    return dw;
  endfunction

  virtual function int unsigned get_id_w_width();
    return iw;
  endfunction

  virtual function int unsigned get_id_r_width();
    return ir;
  endfunction

  virtual function bit configure(axi_features_t features);
    return 1'b1;
  endfunction

  virtual function void set_enable(bit en);
  endfunction

  virtual function void set_ready_delays(int unsigned aw, int unsigned w, int unsigned ar);
  endfunction

  virtual function void set_fault(axi_fault_e fault);
  endfunction

  virtual task get_request(output axi_transaction req);
    req = null;
  endtask

  virtual task send_response(axi_transaction rsp);
    rsp.status = AXI_ST_NOT_ENABLED;
  endtask

  virtual function int unsigned get_request_count();
    return 0;
  endfunction
endclass : axi_fake_respond_proxy


// Observe-side double with the same width knobs; it never receives anything.
class axi_fake_monitor_proxy extends axi_monitor_proxy_base;
  int unsigned aw = 32;
  int unsigned dw = 32;
  int unsigned iw = 4;
  int unsigned ir = 4;

  function new(string name = "axi_fake_monitor_proxy");
    super.new(name);
  endfunction

  // The width getters return the knobs above; every other method is an inert stub.
  virtual function int unsigned get_addr_width();
    return aw;
  endfunction

  virtual function int unsigned get_data_width();
    return dw;
  endfunction

  virtual function int unsigned get_id_w_width();
    return iw;
  endfunction

  virtual function int unsigned get_id_r_width();
    return ir;
  endfunction

  virtual function bit configure(axi_features_t features);
    return 1'b1;
  endfunction

  virtual function void set_publish(bit en);
  endfunction

  virtual function void set_verbose(bit en);
  endfunction

  virtual task receive(output axi_transaction observed);
    observed = null;
  endtask

  virtual task wait_reset_event(output axi_reset_event ev);
    ev = null;
  endtask

  virtual function int unsigned get_error_count(axi_mon_error_e code);
    return 0;
  endfunction

  virtual function int unsigned get_total_errors();
    return 0;
  endfunction

  virtual function void clear_errors();
  endfunction

  virtual function int unsigned get_transfer_count();
    return 0;
  endfunction

  virtual function int unsigned get_reset_count();
    return 0;
  endfunction

  virtual function int unsigned get_open_count();
    return 0;
  endfunction
endclass : axi_fake_monitor_proxy
