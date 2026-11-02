// -----------------------------------------------------------------------------
// axi_mgr_driver — non-parameterized AXI Manager driver (ADR-001 decision 3)
//
// Uses only the abstract drive capability from axi_agent_cfg; it never sees a
// virtual interface. One item is one transaction, run to completion before
// the next item is taken (POL-02: one transaction at a time from the UVM
// side; more outstanding transactions are milestone M2). Items are updated in
// place with the response (bresp or rdata/rresp, resp_id, beats_done, wait
// counts, status) before item_done(), so a sequence reads the result from the
// item it sent.
//
// Reset (RST-3/RST-5): after an item ends with AXI_ST_RESET_ABORTED the
// driver waits for reset release before taking the next item.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_mgr_driver extends uvm_driver #(axi_transaction);
  `uvm_component_utils(axi_mgr_driver)

  axi_agent_cfg cfg;  // set by axi_mgr_agent
  int unsigned  num_sent;

  protected axi_drive_proxy_base drive;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Take the drive capability from the cfg the agent passed in; an active
  // Manager without one is a configuration error (CFG-07).
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null)
      `uvm_fatal("AXI_DRV", "axi_agent_cfg not set by the agent")
    drive = cfg.drive;
    if (drive == null)
      `uvm_fatal("AXI_DRV", {cfg.get_name(), ": active Manager without a drive proxy"})
  endfunction

  // Push the policies and the feature set to the adapter and BFM, then enable
  // driving: the bus leaves 'z at time 0, before the first reset release.
  virtual function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    drive.max_wait_cycles = cfg.max_wait_cycles;
    drive.allow_x_wdata   = cfg.allow_x_wdata;
    if (!drive.configure(cfg.features))
      `uvm_fatal("AXI_DRV", {cfg.get_name(), ": Manager BFM rejected the feature set"})
    drive.set_enable(1'b1);
  endfunction

  // Wait for reset release (RST-5), then serve items until one is abandoned by
  // reset (RST-3), then wait for the next release. Each item is completed in place.
  virtual task run_phase(uvm_phase phase);
    forever begin
      drive.wait_for_reset_release(cfg.post_reset_idle_cycles);
      do begin
        seq_item_port.get_next_item(req);
        drive.send(req);
        num_sent++;
        report_result(req);
        seq_item_port.item_done();
      end while (req.status != AXI_ST_RESET_ABORTED);
    end
  endtask

  // Report each outcome at a severity that matches its status (UVM-09). A SLVERR
  // or DECERR response is a legal protocol outcome, not a UVC error; timeouts are
  // errors, a disabled BFM is fatal, rejections were already reported.
  protected function void report_result(axi_transaction t);
    case (t.status)
      AXI_ST_OK, AXI_ST_ERROR:
        `uvm_info("AXI_DRV", t.convert2string(), UVM_HIGH)
      AXI_ST_RESET_ABORTED:
        `uvm_info("AXI_DRV", {"abandoned by reset: ", t.convert2string()}, UVM_MEDIUM)
      AXI_ST_FAULT_INJECTED:
        `uvm_info("AXI_DRV", {"fault injected: ", t.convert2string()}, UVM_MEDIUM)
      AXI_ST_TIMEOUT:
        `uvm_error("AXI_TIMEOUT", $sformatf("stalled for %0d cycles: %s", cfg.max_wait_cycles,
                                            t.convert2string()))
      AXI_ST_NOT_ENABLED:
        `uvm_fatal("AXI_DRV", {"Manager BFM not enabled: ", t.convert2string()})
      default:  // AXI_ST_BAD_REQUEST: the adapter already reported why
        `uvm_info("AXI_DRV", {"rejected: ", t.convert2string()}, UVM_MEDIUM)
    endcase
  endfunction

endclass : axi_mgr_driver
