// -----------------------------------------------------------------------------
// axi_sub_agent — AXI Subordinate agent (owner decision A-1)
//
// Extends axi_base_agent with the Subordinate role: Subordinate coverage
// always; when active, the Subordinate sequencer and driver, connected in the
// reactive pattern (requests from the driver into the sequencer's request
// FIFO, responses from a response sequence back to the driver). A response
// sequence such as axi_sub_mem_seq must run on the sequencer for requests to
// be answered. Not parameterized (ADR-001 decision 3).
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_sub_agent extends axi_base_agent;
  `uvm_component_utils(axi_sub_agent)

  axi_sub_sequencer sequencer;
  axi_sub_driver    driver;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // The cfg must describe a Subordinate.
  protected virtual function void check_role();
    if (cfg.role != AXI_ROLE_SUBORDINATE)
      `uvm_fatal("AXI_AGENT", {get_full_name(), ": axi_sub_agent needs cfg.role ",
                               "AXI_ROLE_SUBORDINATE, got ", cfg.role.name()})
  endfunction

  // Subordinate coverage: what the Subordinate controls (owner decision A-5)
  protected virtual function axi_coverage create_coverage();
    axi_sub_coverage c = axi_sub_coverage::type_id::create("coverage", this);
    return c;
  endfunction

  // Sequencer and driver, each given the cfg handle
  protected virtual function void build_active();
    sequencer     = axi_sub_sequencer::type_id::create("sequencer", this);
    sequencer.cfg = cfg;
    driver        = axi_sub_driver::type_id::create("driver", this);
    driver.cfg    = cfg;
  endfunction

  // Responses: sequencer -> driver. Requests: driver -> sequencer request FIFO.
  protected virtual function void connect_active();
    driver.seq_item_port.connect(sequencer.seq_item_export);
    driver.request_ap.connect(sequencer.request_fifo.analysis_export);
  endfunction

endclass : axi_sub_agent
