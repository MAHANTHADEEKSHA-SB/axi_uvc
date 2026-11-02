// -----------------------------------------------------------------------------
// axi_lite_test — the same UVC image with bus B in AXI4-Lite mode
//
// Owner decision A-2: AXI4-Lite compatibility is a configuration mode, not a
// separate implementation. This test switches both agents of bus B (DW=64,
// legal for AXI4-Lite) to AXI4_LITE before they validate their cfg, then
// runs AXI4 traffic on A and AXI4-Lite traffic on B at the same time: the
// directed axi_poc_lite_seq and random items, which the item constraints
// keep to full-width single beats (AXI-R24). Bus B's monitors, Manager and
// Subordinate BFMs all run in AXI4-Lite mode; nothing is recompiled.
// Included by axi_poc_test_pkg.
// -----------------------------------------------------------------------------

class axi_lite_test extends axi_poc_test;
  `uvm_component_utils(axi_lite_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // The test's build_phase runs before the agents fetch and validate their cfg,
  // so switching the registered cfg objects here takes effect for the whole run.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    to_lite("env.mgr_b");
    to_lite("env.sub_b");
  endfunction

  // Fetch the cfg registered for one agent path and set AXI4-Lite (test code may
  // read the configuration it adjusts; the core never does, UVM-06).
  protected function void to_lite(string path);
    axi_agent_cfg c;
    if (!uvm_config_db#(axi_agent_cfg)::get(this, path, "cfg", c))
      `uvm_fatal("AXI_LITE", {"no axi_agent_cfg registered for ", path})
    c.features.protocol = AXI4_LITE;
  endfunction

  // Bus A keeps the AXI4 traffic; bus B gets the Lite directed sequence, then 40
  // random items with aligned addresses.
  protected virtual task run_traffic(axi_mgr_agent agent);
    axi_poc_lite_seq   lite     = axi_poc_lite_seq::type_id::create("lite");
    axi_mgr_random_seq rand_seq = axi_mgr_random_seq::type_id::create("lite_rand");
    if (agent != env.mgr_b) begin
      super.run_traffic(agent);
      return;
    end
    lite.start(agent.sequencer);
    if (!rand_seq.randomize() with { num_items == 40; })
      `uvm_fatal("AXI_LITE", "cannot randomize axi_mgr_random_seq")
    rand_seq.addr_max        = 'h2FFF;
    rand_seq.allow_unaligned = 1'b0;
    rand_seq.start(agent.sequencer);
  endtask

  // A must show every AXI4 kind; B the kinds an AXI4-Lite bus can carry.
  virtual function void check_phase(uvm_phase phase);
    check_traffic(env.sb_a, 1'b1);
    check_traffic(env.sb_b, 1'b0);
    if (env.mgr_b.cfg.features.protocol != AXI4_LITE)
      `uvm_error("AXI_LITE", "bus B did not run in AXI4-Lite mode")
  endfunction

endclass : axi_lite_test
