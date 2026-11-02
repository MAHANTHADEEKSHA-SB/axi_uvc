// -----------------------------------------------------------------------------
// axi_fault_injection_test — negative test: injected faults must be detected
//
// Runs the axi_poc_test traffic with a fault on instance A only
// (+AXI_FAULT=<n>, axi_fault_e; default 1 = AxADDR changed while waiting).
// Modes 1..3 are injected by A's Manager BFM, mode 4 by A's Subordinate BFM;
// the fault is given to both and each ignores the other role's modes. The
// monitor errors of A's agents and of the passive observer P (ID
// "AXI_PROTOCOL") are expected, so they are demoted to info and A's
// scoreboard is disabled. The test passes only if
//   * every monitor on bus A counted the violation that matches the fault
//     (axi_fault_error()), and
//   * instance B stayed clean (isolation): its monitors and scoreboard report
//     nothing and it still exercised every traffic kind.
// Instance A's Subordinate holds READY back-pressure (axi_hvl_top), which
// modes 1 and 2 need; the directed traffic has narrow beats (mode 3) and
// multi-beat reads (mode 4).
// Included by axi_poc_test_pkg.
// -----------------------------------------------------------------------------

class axi_fault_injection_test extends axi_poc_test;
  `uvm_component_utils(axi_fault_injection_test)

  axi_fault_e fault = AXI_FAULT_ADDR_UNSTABLE;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // start_of_simulation runs bottom-up, so A's drivers have already configured and
  // enabled their BFMs; the fault applies from the first transaction. A's (and
  // P's) expected AXI_PROTOCOL errors are demoted and A's scoreboard disabled; B
  // keeps every check.
  virtual function void start_of_simulation_phase(uvm_phase phase);
    int unsigned arg;
    super.start_of_simulation_phase(phase);
    if ($value$plusargs("AXI_FAULT=%d", arg)) fault = axi_fault_e'(arg);
    if (fault == AXI_FAULT_NONE)
      `uvm_fatal("AXI_FAULT", "+AXI_FAULT=0 selects no fault")
    env.mgr_a.cfg.drive.set_fault(fault);
    env.sub_a.cfg.respond.set_fault(fault);
    env.mgr_a.monitor.set_report_severity_id_override(UVM_ERROR, "AXI_PROTOCOL", UVM_INFO);
    env.sub_a.monitor.set_report_severity_id_override(UVM_ERROR, "AXI_PROTOCOL", UVM_INFO);
    if (env.agent_p != null)
      env.agent_p.monitor.set_report_severity_id_override(UVM_ERROR, "AXI_PROTOCOL", UVM_INFO);
    env.sb_a.enabled = 1'b0;
    `uvm_info("AXI_FAULT", $sformatf("injecting %s on bus A", fault.name()), UVM_LOW)
  endfunction

  // Replaces axi_poc_test::check_phase: instance A is expected to misbehave.
  virtual function void check_phase(uvm_phase phase);
    axi_mon_error_e want = axi_fault_error(fault);
    expect_detected(env.mgr_a, want);
    expect_detected(env.sub_a, want);
    if (env.agent_p != null) expect_detected(env.agent_p, want);
    if (env.mgr_b.cfg.observe.get_total_errors() != 0 ||
        env.sub_b.cfg.observe.get_total_errors() != 0)
      `uvm_error("AXI_FAULT", "instance B reported protocol errors: fault leaked across instances")
    check_traffic(env.sb_b, 1'b1);
  endfunction

  // The agent's monitor must have counted the violation of the injected fault.
  protected function void expect_detected(axi_base_agent agent, axi_mon_error_e want);
    int unsigned n = agent.cfg.observe.get_error_count(want);
    if (n == 0)
      `uvm_error("AXI_FAULT", $sformatf("%s: injected %s was NOT detected (%s count is 0)",
                                        agent.get_full_name(), fault.name(), want.name()))
    else
      `uvm_info("AXI_FAULT", $sformatf("%s: detected %0d x %s", agent.get_full_name(), n,
                                       want.name()), UVM_LOW)
  endfunction

endclass : axi_fault_injection_test
