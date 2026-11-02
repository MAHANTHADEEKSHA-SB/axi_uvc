// -----------------------------------------------------------------------------
// axi_mgr_agent — AXI Manager agent (owner decision A-1)
//
// Extends axi_base_agent with the Manager role: Manager coverage always; the
// Manager sequencer and driver when active. A passive axi_mgr_agent is a pure
// observer of a bus (instance P of the POC). Not parameterized (ADR-001
// decision 3).
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_mgr_agent extends axi_base_agent;
  `uvm_component_utils(axi_mgr_agent)

  axi_mgr_sequencer sequencer;
  axi_mgr_driver    driver;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // The cfg must describe a Manager.
  protected virtual function void check_role();
    if (cfg.role != AXI_ROLE_MANAGER)
      `uvm_fatal("AXI_AGENT", {get_full_name(), ": axi_mgr_agent needs cfg.role ",
                               "AXI_ROLE_MANAGER, got ", cfg.role.name()})
  endfunction

  // Manager coverage: what the Manager controls (owner decision A-5)
  protected virtual function axi_coverage create_coverage();
    axi_mgr_coverage c = axi_mgr_coverage::type_id::create("coverage", this);
    return c;
  endfunction

  // Sequencer and driver, each given the cfg handle
  protected virtual function void build_active();
    sequencer     = axi_mgr_sequencer::type_id::create("sequencer", this);
    sequencer.cfg = cfg;
    driver        = axi_mgr_driver::type_id::create("driver", this);
    driver.cfg    = cfg;
  endfunction

  // Standard pull port: the driver takes one item at a time (POL-02)
  protected virtual function void connect_active();
    driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : axi_mgr_agent
