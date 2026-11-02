// -----------------------------------------------------------------------------
// axi_monitor — non-parameterized passive AXI monitor (ADR-001 decision 3)
//
// One monitor class serves both roles: observing the bus is role-agnostic.
// Uses only the abstract observe capability from axi_agent_cfg, and works the
// same whether or not the agent is active, because the monitor BFM only reads
// pins (ADR-002 decision 9). Each completed transaction is published once on
// `ap`; every reset edge after the first release is published on `reset_ap`
// (RST-4), so subscribers can clear their models.
//
// This is the per-agent protocol checker of owner decision A-5: the checks
// run in the monitor BFM of every agent instance (active or passive) and are
// gated by the instance's protocol mode. check_phase reports them as
// uvm_error with ID "AXI_PROTOCOL", one line per violation type, and reports
// transactions left open at the end as "AXI_MON_OPEN" (when
// cfg.check_open_at_end). A negative test that expects violations demotes
// that ID on this component and checks the counts through cfg.observe itself.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_monitor extends uvm_monitor;
  `uvm_component_utils(axi_monitor)

  axi_agent_cfg                        cfg;  // set by the agent
  uvm_analysis_port #(axi_transaction) ap;
  uvm_analysis_port #(axi_reset_event) reset_ap;
  int unsigned                         num_observed;
  int unsigned                         num_reset_events;

  protected axi_monitor_proxy_base observe;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Create the analysis ports and take the observe capability from the cfg.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap       = new("ap", this);
    reset_ap = new("reset_ap", this);
    if (cfg == null)
      `uvm_fatal("AXI_MON", "axi_agent_cfg not set by the agent")
    observe = cfg.observe;
    if (observe == null)
      `uvm_fatal("AXI_MON", {cfg.get_name(), ": no observe proxy"})
  endfunction

  // Configure the BFM with the instance's protocol mode, then enable publishing
  // now that this consumer exists.
  virtual function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    observe.set_verbose(cfg.monitor_verbose);
    if (!observe.configure(cfg.features))
      `uvm_fatal("AXI_MON", {cfg.get_name(), ": monitor BFM rejected the feature set"})
    observe.set_publish(1'b1);
  endfunction

  // Two independent consumers of the BFM queues: one receive() per completed
  // transaction, published once on ap; one wait_reset_event() per reset edge.
  virtual task run_phase(uvm_phase phase);
    fork
      forever begin
        axi_transaction t;
        observe.receive(t);
        num_observed++;
        `uvm_info("AXI_MON", t.convert2string(), UVM_HIGH)
        ap.write(t);
      end
      forever begin
        axi_reset_event ev;
        observe.wait_reset_event(ev);
        num_reset_events++;
        `uvm_info("AXI_MON", ev.convert2string(), UVM_MEDIUM)
        reset_ap.write(ev);
      end
    join
  endtask

  // One AXI_PROTOCOL error per violation type counted by the BFM, and one
  // AXI_MON_OPEN error when transactions never completed. Negative tests demote
  // these IDs on this component and check the counts themselves (UVM-13).
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    for (int c = 0; c < AXI_MON_NUM_ERRORS; c++) begin
      axi_mon_error_e code = axi_mon_error_e'(c);
      int unsigned    n    = observe.get_error_count(code);
      if (n != 0)
        `uvm_error("AXI_PROTOCOL", $sformatf("%s: %0d x %s", cfg.get_name(), n, code.name()))
    end
    if (cfg.check_open_at_end && observe.get_open_count() != 0)
      `uvm_error("AXI_MON_OPEN", $sformatf("%s: %0d transactions started but never completed",
                                           cfg.get_name(), observe.get_open_count()))
  endfunction

  // Summary: transactions observed, resets seen, violations counted.
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("AXI_MON", $sformatf("%s: %0d transactions observed, %0d resets, %0d protocol errors",
                                   cfg.get_name(), num_observed, observe.get_reset_count(),
                                   observe.get_total_errors()), UVM_LOW)
  endfunction

endclass : axi_monitor
