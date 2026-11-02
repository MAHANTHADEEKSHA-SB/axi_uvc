// -----------------------------------------------------------------------------
// axi_poc_env — POC environment: both roles of the same AXI UVC on two buses
//
// Per bus (A: DW=32, B: DW=64) a Manager agent and a Subordinate agent face
// each other, with one axi_poc_scoreboard that sees the Manager-side monitor
// (transactions, reset events) and the Subordinate driver's requests. The
// Subordinate agents answer with axi_sub_mem_seq, started here in run_phase
// so every test has responders. agent_p (passive observer of bus A) exists
// only when the integration registered a cfg for it; axi_passive_test
// compares it with mgr_a. This env is test code, not a reusable framework
// (it replaces the src/env/axi_env.sv placeholder, owner decision A-5).
// Included by axi_poc_test_pkg.
// -----------------------------------------------------------------------------

class axi_poc_env extends uvm_env;
  `uvm_component_utils(axi_poc_env)

  // Response windows of the responders; the scoreboards model the same ones.
  localparam longint unsigned OKAY_BYTES   = 'h1000;
  localparam longint unsigned SLVERR_BYTES = 'h1000;

  axi_mgr_agent      mgr_a;
  axi_sub_agent      sub_a;
  axi_mgr_agent      mgr_b;
  axi_sub_agent      sub_b;
  axi_mgr_agent      agent_p;      // null unless the integration bound instance P
  axi_poc_scoreboard sb_a;
  axi_poc_scoreboard sb_b;
  axi_sub_mem_seq    responder_a;  // runs on sub_a for the whole run phase
  axi_sub_mem_seq    responder_b;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Both roles on both buses and their scoreboards always; agent_p only when the
  // integration code registered a cfg for it. The responders and scoreboards get
  // the same response windows.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mgr_a = axi_mgr_agent::type_id::create("mgr_a", this);
    sub_a = axi_sub_agent::type_id::create("sub_a", this);
    mgr_b = axi_mgr_agent::type_id::create("mgr_b", this);
    sub_b = axi_sub_agent::type_id::create("sub_b", this);
    sb_a  = axi_poc_scoreboard::type_id::create("sb_a", this);
    sb_b  = axi_poc_scoreboard::type_id::create("sb_b", this);
    if (uvm_config_db#(axi_agent_cfg)::exists(this, "agent_p", "cfg"))
      agent_p = axi_mgr_agent::type_id::create("agent_p", this);
    responder_a = axi_sub_mem_seq::type_id::create("responder_a");
    responder_b = axi_sub_mem_seq::type_id::create("responder_b");
    set_windows(responder_a, sb_a);
    set_windows(responder_b, sb_b);
  endfunction

  // Each Manager-side monitor feeds its bus's scoreboard (transactions and reset
  // events); each Subordinate driver feeds it the requests it received.
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mgr_a.monitor.ap.connect(sb_a.analysis_export);
    mgr_a.monitor.reset_ap.connect(sb_a.reset_export);
    mgr_b.monitor.ap.connect(sb_b.analysis_export);
    mgr_b.monitor.reset_ap.connect(sb_b.reset_export);
    if (sub_a.driver != null) sub_a.driver.request_ap.connect(sb_a.request_export);
    if (sub_b.driver != null) sub_b.driver.request_ap.connect(sb_b.request_export);
  endfunction

  // The responders never end on their own; the run phase ends them.
  virtual task run_phase(uvm_phase phase);
    fork
      if (sub_a.sequencer != null) responder_a.start(sub_a.sequencer);
      if (sub_b.sequencer != null) responder_b.start(sub_b.sequencer);
    join_none
  endtask

  // Give one responder and its scoreboard the same response windows.
  protected function void set_windows(axi_sub_mem_seq r, axi_poc_scoreboard sb);
    r.okay_bytes    = OKAY_BYTES;
    r.slverr_bytes  = SLVERR_BYTES;
    sb.okay_bytes   = OKAY_BYTES;
    sb.slverr_bytes = SLVERR_BYTES;
  endfunction

endclass : axi_poc_env
