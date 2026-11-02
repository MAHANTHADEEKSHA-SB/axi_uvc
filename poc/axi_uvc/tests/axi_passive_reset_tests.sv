// -----------------------------------------------------------------------------
// axi_passive_reset_tests — passive-agent and reset tests (the APB-005 gaps,
// covered for AXI from the start as they were for AHB)
//
// axi_passive_test: runs the axi_poc_test traffic and checks the passive
//   observer P on bus A (ADR-002 decisions 6 and 9, RISK-004): P has no
//   driver, sequencer or drive/respond capability; it publishes exactly the
//   transactions mgr_a's monitor publishes, with the same content and cycle
//   stamps; and it reports no protocol error, which also shows that P's
//   never-enabled Manager and Subordinate BFMs stayed released ('z) —
//   contention would read as X.
// axi_reset_test: cuts a 64-beat write on instance A with a reset
//   (RST-1..RST-5, RST-8): the item must end AXI_ST_RESET_ABORTED, the
//   partial write must not be published (RST-4), the monitor must report the
//   reset edges, the scoreboard model must be cleared together with the
//   responder's memory, traffic after the reset must check clean, and
//   instance B must not notice anything.
// Included by axi_poc_test_pkg.
// -----------------------------------------------------------------------------

class axi_passive_test extends axi_poc_test;
  `uvm_component_utils(axi_passive_test)

  uvm_tlm_analysis_fifo #(axi_transaction) fifo_a;  // seen by mgr_a's monitor
  uvm_tlm_analysis_fifo #(axi_transaction) fifo_p;  // seen by the passive agent

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // The env and traffic of axi_poc_test, plus one FIFO per observer.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    fifo_a = new("fifo_a", this);
    fifo_p = new("fifo_p", this);
  endfunction

  // P must exist: the integration (examples/axi_hvl_top.sv) registers cfg_p.
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (env.agent_p == null)
      `uvm_fatal("AXI_PASSIVE", "no passive agent: cfg for env.agent_p not registered")
    env.mgr_a.monitor.ap.connect(fifo_a.analysis_export);
    env.agent_p.monitor.ap.connect(fifo_p.analysis_export);
  endfunction

  // The traffic checks of axi_poc_test, then the passive-agent checks.
  virtual function void check_phase(uvm_phase phase);
    axi_transaction ta;
    axi_transaction tp;
    int unsigned    compared = 0;
    super.check_phase(phase);
    if (env.agent_p.driver != null || env.agent_p.sequencer != null ||
        env.agent_p.cfg.drive != null || env.agent_p.cfg.respond != null)
      `uvm_error("AXI_PASSIVE", "passive agent has a driver, sequencer or active capability")
    while (fifo_a.try_get(ta)) begin
      if (!fifo_p.try_get(tp)) begin
        `uvm_error("AXI_PASSIVE", {"passive agent missed: ", ta.convert2string()})
        break;
      end
      compared++;
      if (!ta.compare(tp) || ta.addr_cycle != tp.addr_cycle || ta.resp_cycle != tp.resp_cycle)
        `uvm_error("AXI_PASSIVE", {"observations differ: ", ta.convert2string(), " | ",
                                   tp.convert2string()})
    end
    if (fifo_p.try_get(tp))
      `uvm_error("AXI_PASSIVE", {"passive agent saw an extra transaction: ",
                                 tp.convert2string()})
    if (compared == 0)
      `uvm_error("AXI_PASSIVE", "no transactions compared")
    else
      `uvm_info("AXI_PASSIVE", $sformatf("%0d transactions identical on mgr_a and agent_p",
                                         compared), UVM_LOW)
  endfunction

endclass : axi_passive_test


// Reset in the middle of a write on instance A only.
class axi_reset_test extends axi_poc_base_test;
  `uvm_component_utils(axi_reset_test)

  axi_poc_env        env;
  axi_poc_reset_ctrl reset_ctrl;
  axi_transaction    aborted;  // the 64-beat write cut by the reset

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // The POC env plus the reset capability registered by the HVL top.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axi_poc_env::type_id::create("env", this);
    if (!uvm_config_db#(axi_poc_reset_ctrl)::get(this, "", "reset_ctrl", reset_ctrl))
      `uvm_fatal("AXI_RESET", "no axi_poc_reset_ctrl registered for uvm_test_top")
  endfunction

  // A: directed traffic, then a 64-beat write (about 130 cycles at 10 ns: every
  // beat waits for WREADY) with a 3-cycle reset pulse 300 ns after it starts, then
  // directed traffic again on the cleared memory. B runs directed traffic
  // meanwhile and must not be affected.
  virtual task run_phase(uvm_phase phase);
    axi_poc_directed_seq before_a  = axi_poc_directed_seq::type_id::create("before_a");
    axi_long_write_seq   long_a    = axi_long_write_seq::type_id::create("long_a");
    axi_poc_directed_seq after_a   = axi_poc_directed_seq::type_id::create("after_a");
    axi_poc_directed_seq traffic_b = axi_poc_directed_seq::type_id::create("traffic_b");
    phase.raise_objection(this);
    phase.get_objection().set_drain_time(this, 500ns);
    fork
      begin
        before_a.start(env.mgr_a.sequencer);
        fork
          long_a.start(env.mgr_a.sequencer);
          begin
            #300ns;
            reset_ctrl.pulse_reset("a", 3);
          end
        join
        aborted = long_a.result;
        after_a.start(env.mgr_a.sequencer);
      end
      traffic_b.start(env.mgr_b.sequencer);
    join
    phase.drop_objection(this);
  endtask

  // RST-3: item abandoned; RST-4: one reset (assert + release events), the partial
  // write never published, the model cleared; isolation: B saw no reset.
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (aborted == null || aborted.status != AXI_ST_RESET_ABORTED)
      `uvm_error("AXI_RESET", "the 64-beat write was not abandoned by the reset")
    if (env.mgr_a.cfg.observe.get_reset_count() != 1 ||
        env.mgr_a.monitor.num_reset_events != 2 || env.sb_a.num_resets != 1)
      `uvm_error("AXI_RESET", $sformatf("reset seen %0d times, %0d events, %0d model clears",
                                        env.mgr_a.cfg.observe.get_reset_count(),
                                        env.mgr_a.monitor.num_reset_events,
                                        env.sb_a.num_resets))
    // Every item reached the bus except the aborted one, which must not be published.
    if (env.mgr_a.cfg.observe.get_transfer_count() != env.mgr_a.driver.num_sent - 1)
      `uvm_error("AXI_RESET", $sformatf("%0d transactions observed for %0d items sent (1 aborted)",
                                        env.mgr_a.cfg.observe.get_transfer_count(),
                                        env.mgr_a.driver.num_sent))
    if (env.mgr_b.cfg.observe.get_reset_count() != 0)
      `uvm_error("AXI_RESET", "instance B saw a reset: reset leaked across instances")
    if (env.sb_a.num_checked == 0 || env.sb_b.num_checked == 0)
      `uvm_error("AXI_RESET", "a scoreboard checked no traffic")
  endfunction

endclass : axi_reset_test
