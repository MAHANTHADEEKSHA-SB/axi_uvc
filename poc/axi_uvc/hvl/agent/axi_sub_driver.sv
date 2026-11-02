// -----------------------------------------------------------------------------
// axi_sub_driver — non-parameterized AXI Subordinate driver (ADR-001 decision 3)
//
// Uses only the abstract respond capability from axi_agent_cfg. Two loops run
// side by side (reactive pattern, AXI_PROTOCOL_CONTRACT section 8):
//   * request loop: every complete request the BFM accepted is taken with
//     get_request() and written to request_ap, which axi_sub_agent connects
//     to the sequencer's request FIFO;
//   * response loop: every item a response sequence sends is handed to the
//     BFM with send_response() and completed in place (status).
// The BFM keeps accepting requests while responses are pending, up to its
// queue depth (POL-08).
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_sub_driver extends uvm_driver #(axi_transaction);
  `uvm_component_utils(axi_sub_driver)

  axi_agent_cfg                        cfg;  // set by axi_sub_agent
  uvm_analysis_port #(axi_transaction) request_ap;
  int unsigned                         num_requests;
  int unsigned                         num_responses;

  protected axi_respond_proxy_base respond;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Create the request port and take the respond capability from the cfg; an
  // active Subordinate without one is a configuration error (CFG-07).
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    request_ap = new("request_ap", this);
    if (cfg == null)
      `uvm_fatal("AXI_SUB_DRV", "axi_agent_cfg not set by the agent")
    respond = cfg.respond;
    if (respond == null)
      `uvm_fatal("AXI_SUB_DRV", {cfg.get_name(), ": active Subordinate without a respond proxy"})
  endfunction

  // Push the feature set and the READY policy (POL-06) to the BFM, then enable
  // it: the bus leaves 'z at time 0, before the first reset release.
  virtual function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (!respond.configure(cfg.features))
      `uvm_fatal("AXI_SUB_DRV", {cfg.get_name(), ": Subordinate BFM rejected the feature set"})
    respond.set_ready_delays(cfg.aw_ready_delay, cfg.w_ready_delay, cfg.ar_ready_delay);
    respond.set_enable(1'b1);
  endfunction

  // Request loop and response loop, independent of each other.
  virtual task run_phase(uvm_phase phase);
    fork
      forever begin
        axi_transaction request;
        respond.get_request(request);
        num_requests++;
        `uvm_info("AXI_SUB_DRV", {"request: ", request.convert2string()}, UVM_HIGH)
        request_ap.write(request);
      end
      forever begin
        seq_item_port.get_next_item(req);
        respond.send_response(req);
        num_responses++;
        report_result(req);
        seq_item_port.item_done();
      end
    join
  endtask

  // A response to a request from before a reset is dropped by design (RST-8);
  // other refusals were reported by the adapter; a disabled BFM is fatal.
  protected function void report_result(axi_transaction t);
    case (t.status)
      AXI_ST_OK:
        `uvm_info("AXI_SUB_DRV", {"response: ", t.convert2string()}, UVM_HIGH)
      AXI_ST_RESET_ABORTED:
        `uvm_info("AXI_SUB_DRV", {"dropped, request predates a reset: ", t.convert2string()},
                  UVM_MEDIUM)
      AXI_ST_NOT_ENABLED:
        `uvm_fatal("AXI_SUB_DRV", {"Subordinate BFM not enabled: ", t.convert2string()})
      default:  // AXI_ST_BAD_REQUEST: the adapter already reported why
        `uvm_info("AXI_SUB_DRV", {"refused: ", t.convert2string()}, UVM_MEDIUM)
    endcase
  endfunction

endclass : axi_sub_driver
