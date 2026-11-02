// -----------------------------------------------------------------------------
// axi_poc_base_test / axi_poc_test — POC acceptance test (step 6)
//
// axi_poc_base_test: common timeout and the result line
//   "TEST_RESULT: PASS|FAIL (<n> errors) <test>" from the report server.
// axi_poc_test: the DW=32 and DW=64 instances run concurrently with the same
//   non-parameterized agent classes (ADR-001 gate 1): directed transactions,
//   then constrained-random ones across the OKAY, SLVERR and DECERR windows.
//   Passes when both scoreboards checked traffic with no mismatch, compared
//   every request with the Subordinate agent's view, and saw SLVERR, DECERR,
//   narrow, unaligned, partially strobed and data-before-address writes, and
//   no monitor (including the passive observer P) reported a violation.
// Included by axi_poc_test_pkg.
// -----------------------------------------------------------------------------

class axi_poc_base_test extends uvm_test;
  `uvm_component_utils(axi_poc_base_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Global watchdog: the test fails instead of hanging.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_root::get().set_timeout(3ms, 1);
  endfunction

  // One machine-readable result line from the report server's error and fatal
  // counts; the only $display in UVM code (UVM-09).
  virtual function void report_phase(uvm_phase phase);
    uvm_report_server server = uvm_report_server::get_server();
    int errors = server.get_severity_count(UVM_ERROR) + server.get_severity_count(UVM_FATAL);
    super.report_phase(phase);
    $display("TEST_RESULT: %s (%0d errors) %s", errors == 0 ? "PASS" : "FAIL", errors,
             get_type_name());
  endfunction

endclass : axi_poc_base_test


// The same agent classes drive DW=32 and DW=64 at once (ADR-001 gate 1).
class axi_poc_test extends axi_poc_base_test;
  `uvm_component_utils(axi_poc_test)

  axi_poc_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // The env builds agent_p only if the integration registered a cfg for it.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axi_poc_env::type_id::create("env", this);
  endfunction

  // Both buses run concurrently; the drain time lets each monitor publish the
  // last transaction before the run phase ends.
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    phase.get_objection().set_drain_time(this, 500ns);
    fork
      run_traffic(env.mgr_a);
      run_traffic(env.mgr_b);
    join
    phase.drop_objection(this);
  endtask

  // Directed transactions, then 40 random ones in [0:'h2FFF]: the OKAY window
  // and the SLVERR/DECERR windows above it (axi_poc_env).
  protected virtual task run_traffic(axi_mgr_agent agent);
    axi_poc_directed_seq directed = axi_poc_directed_seq::type_id::create("directed");
    axi_mgr_random_seq   rand_seq = axi_mgr_random_seq::type_id::create("rand_seq");
    directed.start(agent.sequencer);
    if (!rand_seq.randomize() with { num_items == 40; })
      `uvm_fatal("AXI_POC", "cannot randomize axi_mgr_random_seq")
    rand_seq.addr_max = 'h2FFF;
    rand_seq.start(agent.sequencer);
  endtask

  // Every scoreboard must have checked the traffic kinds listed in the header.
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    check_traffic(env.sb_a, 1'b1);
    check_traffic(env.sb_b, 1'b1);
  endfunction

  // Errors, not fatals: every bus is checked and reported. full_axi4 = 0 skips
  // the kinds an AXI4-Lite bus cannot carry (narrow, unaligned, data first).
  protected function void check_traffic(axi_poc_scoreboard sb, bit full_axi4);
    if (sb.num_checked == 0)
      `uvm_error("AXI_POC", {sb.get_full_name(), ": no transactions checked"})
    if (sb.num_requests != sb.num_checked)
      `uvm_error("AXI_POC", $sformatf("%s: %0d requests compared for %0d transactions",
                                      sb.get_full_name(), sb.num_requests, sb.num_checked))
    if (sb.num_slverr == 0 || sb.num_decerr == 0)
      `uvm_error("AXI_POC", {sb.get_full_name(), ": SLVERR or DECERR never observed"})
    if (sb.num_partial_strb == 0)
      `uvm_error("AXI_POC", {sb.get_full_name(), ": no partially strobed write observed"})
    if (!full_axi4) return;
    if (sb.num_narrow == 0 || sb.num_unaligned == 0)
      `uvm_error("AXI_POC", {sb.get_full_name(), ": no narrow or no unaligned transfer"})
    if (sb.num_data_first == 0)
      `uvm_error("AXI_POC", {sb.get_full_name(), ": no write data before its address"})
  endfunction

endclass : axi_poc_test
