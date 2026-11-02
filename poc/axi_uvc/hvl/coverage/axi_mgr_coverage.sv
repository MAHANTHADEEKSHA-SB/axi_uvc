// -----------------------------------------------------------------------------
// axi_mgr_coverage — coverage of what the Manager controls (owner decision A-5)
//
// Adds to axi_coverage: the order of write data and write address (data
// first, same edge, address first — AXI-R06 allows all three), partial
// write strobes, and the back-pressure the Manager put on the responses
// (cycles BVALID or RVALID waited for BREADY or RREADY). Derived from the
// monitor's cycle stamps and wait counts.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_mgr_coverage extends axi_coverage;
  `uvm_component_utils(axi_mgr_coverage)

  typedef enum { DATA_FIRST, SAME_EDGE, ADDR_FIRST } data_order_e;

  // Sampled once per observed transaction (writes only for order and strobes).
  covergroup cg_mgr with function sample(axi_dir_e dir, data_order_e order, bit partial_strb,
                                         int unsigned resp_backpressure);
    option.per_instance = 1;

    cp_dir          : coverpoint dir;
    cp_order        : coverpoint order iff (dir == AXI_WRITE);
    cp_partial_strb : coverpoint partial_strb iff (dir == AXI_WRITE);
    cp_backpressure : coverpoint resp_backpressure {
      bins none = {0};
      bins one  = {1};
      bins some = {[2:$]};
    }

    x_dir_backpressure : cross cp_dir, cp_backpressure;
  endgroup : cg_mgr

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_mgr = new();
  endfunction

  // Name the role covergroup instance after this component as well.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cg_mgr.set_inst_name({get_full_name(), ".mgr"});
  endfunction

  // Role hook (owner decision A-3)
  protected virtual function void sample_coverage(axi_transaction t);
    data_order_e order        = SAME_EDGE;
    bit          partial_strb = 1'b0;
    int unsigned backpressure = 0;
    if (t.first_data_cycle < t.addr_cycle)      order = DATA_FIRST;
    else if (t.first_data_cycle > t.addr_cycle) order = ADDR_FIRST;
    if (t.dir == AXI_WRITE) begin
      backpressure = t.resp_wait;
      foreach (t.wstrb[i])
        if (t.wstrb[i] !== t.lanes_of(i)) partial_strb = 1'b1;
    end else begin
      foreach (t.data_wait[i])
        if (t.data_wait[i] > backpressure) backpressure = t.data_wait[i];
    end
    cg_mgr.sample(t.dir, order, partial_strb, backpressure);
  endfunction

  // Role coverage summary next to the common one.
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("AXI_COV", $sformatf("%s: Manager coverage %0.1f%%", get_full_name(),
                                   cg_mgr.get_inst_coverage()), UVM_LOW)
  endfunction

endclass : axi_mgr_coverage
