// -----------------------------------------------------------------------------
// axi_base_agent — role-independent skeleton of the AXI UVC agents
//
// Owner decision A-2 (base class holds the shared skeleton, roles override
// empty hooks) applied where the skeleton is really shared: the base agent
// retrieves its axi_agent_cfg ONCE from uvm_config_db (field "cfg", exact
// agent path, UVM-06), validates it, and builds what every agent has — the
// monitor and the coverage collector — and passes the cfg handle to them.
// Role-specific parts come through the hooks below; axi_mgr_agent and
// axi_sub_agent override them. Passive mode is a runtime choice and does not
// change what is compiled (ADR-002 decision 9).
// Not parameterized (ADR-001 decision 3).
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_base_agent extends uvm_agent;
  `uvm_component_utils(axi_base_agent)

  axi_agent_cfg                        cfg;
  axi_monitor                          monitor;
  axi_coverage                         coverage;
  uvm_analysis_port #(axi_transaction) ap;        // the monitor's ports, re-exported
  uvm_analysis_port #(axi_reset_event) reset_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Get this instance's cfg once and validate it; build the monitor and coverage
  // always, the role's active part only when active. Children get the cfg
  // handle directly and never query uvm_config_db (UVM-06).
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("AXI_AGENT", {"no axi_agent_cfg registered for ", get_full_name()})
    cfg.validate();
    check_role();
    is_active = cfg.is_active;  // keep uvm_agent::get_is_active() consistent with the cfg
    `uvm_info("AXI_AGENT", cfg.convert2string(), UVM_LOW)

    monitor     = axi_monitor::type_id::create("monitor", this);
    monitor.cfg = cfg;
    if (cfg.enable_coverage) begin
      coverage     = create_coverage();
      coverage.cfg = cfg;
    end
    if (cfg.is_active == UVM_ACTIVE) build_active();
  endfunction

  // Re-export the monitor's ports, feed coverage, connect the role's active part.
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap       = monitor.ap;
    reset_ap = monitor.reset_ap;
    if (coverage != null) monitor.ap.connect(coverage.analysis_export);
    if (cfg.is_active == UVM_ACTIVE) connect_active();
  endfunction

  // ---- Role hooks (empty or generic here; overridden by the role agents) --------

  // Fatal when cfg.role does not match the agent class; the base agent accepts any
  // role and can serve as a passive observer.
  protected virtual function void check_role();
  endfunction

  // The coverage collector of the role (owner decision A-5: coverage per role)
  protected virtual function axi_coverage create_coverage();
    return axi_coverage::type_id::create("coverage", this);
  endfunction

  // Build the role's sequencer and driver and pass them the cfg (active only)
  protected virtual function void build_active();
  endfunction

  // Connect the role's driver and sequencer (active only)
  protected virtual function void connect_active();
  endfunction

endclass : axi_base_agent
