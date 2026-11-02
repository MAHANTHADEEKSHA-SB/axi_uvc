// -----------------------------------------------------------------------------
// axi_respond_proxy_base — abstract AXI Subordinate respond capability
//
// The Subordinate role's reactive API (owner decision A-1; ADR-002 extended to
// a third capability, see ADR-002 "AXI: three capabilities"). Not
// parameterized by bus width. The Subordinate driver holds only this handle;
// a width-specialized adapter (axi_adapter_pkg::axi_respond_proxy) implements
// it over a typed virtual Subordinate-BFM handle. The Manager role and the
// monitor never receive this type.
// Included by axi_api_pkg.
// -----------------------------------------------------------------------------

virtual class axi_respond_proxy_base extends uvm_object;

  function new(string name = "axi_respond_proxy_base");
    super.new(name);
  endfunction

  // Physical parameters of the bound bus (CFG-06 cross-checks)
  pure virtual function int unsigned get_addr_width();
  pure virtual function int unsigned get_data_width();
  pure virtual function int unsigned get_id_w_width();
  pure virtual function int unsigned get_id_r_width();

  // Push the instance feature set to the BFM; 0 = rejected
  pure virtual function bit configure(axi_features_t features);

  // 1: respond on the bus; 0: release every Subordinate output to 'z
  pure virtual function void set_enable(bit en);

  // READY policy per channel (POL-06): 0 = READY HIGH while there is room,
  // d > 0 = READY after the VALID waited d cycles
  pure virtual function void set_ready_delays(int unsigned aw, int unsigned w, int unsigned ar);

  // Deliberate protocol faults for negative tests
  pure virtual function void set_fault(axi_fault_e fault);

  // Blocks until the BFM holds a complete request; returns a new object per call
  // with the request fields, the write data and strobes, addr_cycle and req_epoch.
  pure virtual task get_request(output axi_transaction req);

  // Hand back the response to the oldest unanswered request of rsp.dir (same ID,
  // and same length for a read, AXI-R20): bresp and resp_delay for a write,
  // rdata, rresp and data_delay for a read. Sets rsp.status: AXI_ST_OK when
  // queued, AXI_ST_RESET_ABORTED when the request predates a reset (RST-8),
  // AXI_ST_BAD_REQUEST when it is illegal or answers no open request.
  pure virtual task send_response(axi_transaction rsp);

  // Requests completed by the BFM since time 0
  pure virtual function int unsigned get_request_count();

endclass : axi_respond_proxy_base
