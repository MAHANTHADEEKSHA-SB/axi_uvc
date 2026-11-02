// -----------------------------------------------------------------------------
// axi_sub_coverage — coverage of what the Subordinate controls (owner decision A-5)
//
// Adds to axi_coverage: the back-pressure the Subordinate put on the address
// and write data channels (cycles AxVALID or WVALID waited for READY), the
// response latency (write: last data or address to B; read: address to first
// data), and the response code per direction. Derived from the monitor's
// cycle stamps and wait counts.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_sub_coverage extends axi_coverage;
  `uvm_component_utils(axi_sub_coverage)

  // Sampled once per observed transaction.
  covergroup cg_sub with function sample(axi_dir_e dir, int unsigned addr_backpressure,
                                         int unsigned wdata_backpressure, longint unsigned latency,
                                         logic [1:0] resp);
    option.per_instance = 1;

    cp_dir     : coverpoint dir;
    cp_addr_bp : coverpoint addr_backpressure {
      bins none = {0};
      bins one  = {1};
      bins some = {[2:$]};
    }
    cp_w_bp    : coverpoint wdata_backpressure iff (dir == AXI_WRITE) {
      bins none = {0};
      bins one  = {1};
      bins some = {[2:$]};
    }
    cp_latency : coverpoint latency {
      bins quick = {[0:1]};
      bins short = {[2:4]};
      bins long  = {[5:$]};
    }
    cp_resp    : coverpoint resp {
      bins okay   = {2'b00};
      bins exokay = {2'b01};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }

    x_dir_resp    : cross cp_dir, cp_resp;
    x_dir_latency : cross cp_dir, cp_latency;
  endgroup : cg_sub

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_sub = new();
  endfunction

  // Name the role covergroup instance after this component as well.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cg_sub.set_inst_name({get_full_name(), ".sub"});
  endfunction

  // Role hook (owner decision A-9)
  protected virtual function void sample_coverage(axi_transaction t);
    int unsigned     w_bp    = 0;
    longint unsigned start;
    longint unsigned latency = 0;
    if (t.dir == AXI_WRITE) begin
      foreach (t.data_wait[i])
        if (t.data_wait[i] > w_bp) w_bp = t.data_wait[i];
      // B can only follow both the address and the last data beat (AXI-R06)
      start = (t.last_data_cycle > t.addr_cycle) ? t.last_data_cycle : t.addr_cycle;
      if (t.resp_cycle > start) latency = t.resp_cycle - start;
    end else begin
      if (t.first_data_cycle > t.addr_cycle) latency = t.first_data_cycle - t.addr_cycle;
    end
    cg_sub.sample(t.dir, t.addr_wait, w_bp, latency, summary_resp(t));
  endfunction

  // Role coverage summary next to the common one.
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("AXI_COV", $sformatf("%s: Subordinate coverage %0.1f%%", get_full_name(),
                                   cg_sub.get_inst_coverage()), UVM_LOW)
  endfunction

endclass : axi_sub_coverage
