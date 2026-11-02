// -----------------------------------------------------------------------------
// axi_negative_tests — configuration and boundary negative tests
//
// axi_cfg_negative_test: axi_agent_cfg::legality_error() must reject every
//   illegal configuration of AXI_PROTOCOL_CONTRACT CFG-01..04, CFG-06 and
//   CFG-07 (including adapters cross-wired to another bus specialization)
//   and accept the legal ones. Uses the fake proxies, so no bus traffic is
//   involved.
// axi_width_negative_test: a write whose data, and one whose ID, does not fit
//   the DW=32 / ID 4 bus must be rejected by the drive adapter (status
//   AXI_ST_BAD_REQUEST) and must never reach the bus — no silent truncation
//   (RISK-003).
// Included by axi_poc_test_pkg.
// -----------------------------------------------------------------------------

class axi_cfg_negative_test extends axi_poc_base_test;
  `uvm_component_utils(axi_cfg_negative_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Each case builds a fresh cfg on fake proxies and checks legality_error(); no
  // fatal is raised, so every case runs and reports.
  virtual task run_phase(uvm_phase phase);
    axi_agent_cfg          c;
    axi_fake_drive_proxy   d;
    axi_fake_respond_proxy r;
    phase.raise_objection(this);

    // Legal configurations of both roles and both POC widths
    c = make_cfg(AXI_ROLE_MANAGER, 32, 32, 4, 4);
    expect_verdict("Manager AXI4 AW32 DW32", c, "");
    c = make_cfg(AXI_ROLE_MANAGER, 40, 64, 6, 5);
    expect_verdict("Manager AXI4 AW40 DW64 ID6/5", c, "");
    c = make_cfg(AXI_ROLE_SUBORDINATE, 32, 32, 4, 4);
    expect_verdict("Subordinate AXI4 AW32 DW32", c, "");

    // CFG-06: an adapter bound to a different bus specialization
    c       = make_cfg(AXI_ROLE_MANAGER, 32, 32, 4, 4);
    d       = new("fake_drive_dw64");
    d.dw    = 64;
    c.drive = d;
    expect_verdict("drive DW=64 on a DW=32 bus", c, "CFG-06");
    c         = make_cfg(AXI_ROLE_SUBORDINATE, 32, 32, 4, 4);
    r         = new("fake_respond_ir5");
    r.ir      = 5;
    c.respond = r;
    expect_verdict("respond ID_R=5 on an ID_R=4 bus", c, "CFG-06");

    // CFG-03 / CFG-04: widths outside the AXI ranges
    c = make_cfg(AXI_ROLE_MANAGER, 65, 32, 4, 4);
    expect_verdict("AW=65", c, "CFG-03");
    c = make_cfg(AXI_ROLE_MANAGER, 32, 24, 4, 4);
    expect_verdict("DW=24", c, "CFG-04");
    c = make_cfg(AXI_ROLE_MANAGER, 32, 2048, 4, 4);
    expect_verdict("DW=2048", c, "CFG-04");

    // CFG-01: AXI4-Lite needs DATA_WIDTH 32 or 64 and has no user signals
    c = make_cfg(AXI_ROLE_MANAGER, 32, 32, 4, 4);
    c.features.protocol = AXI4_LITE;
    expect_verdict("AXI4-Lite DW=32", c, "");
    c = make_cfg(AXI_ROLE_SUBORDINATE, 40, 64, 6, 5);
    c.features.protocol = AXI4_LITE;
    expect_verdict("AXI4-Lite DW=64", c, "");
    c = make_cfg(AXI_ROLE_MANAGER, 32, 128, 4, 4);
    c.features.protocol = AXI4_LITE;
    expect_verdict("AXI4-Lite DW=128", c, "CFG-01");
    c = make_cfg(AXI_ROLE_MANAGER, 32, 32, 4, 4);
    c.features.protocol       = AXI4_LITE;
    c.features.user_req_width = 2;
    expect_verdict("AXI4-Lite with AxUSER", c, "CFG-01");

    // CFG-02: features of later milestones
    c = make_cfg(AXI_ROLE_MANAGER, 32, 32, 4, 4);
    c.features.user_data_width = 8;
    expect_verdict("AXI4 with WUSER/RUSER (M2)", c, "CFG-02");

    // CFG-07 and the observe capability
    c       = make_cfg(AXI_ROLE_MANAGER, 32, 32, 4, 4);
    c.drive = null;
    expect_verdict("active Manager without drive", c, "CFG-07");
    c         = make_cfg(AXI_ROLE_SUBORDINATE, 32, 32, 4, 4);
    c.respond = null;
    expect_verdict("active Subordinate without respond", c, "CFG-07");
    c           = make_cfg(AXI_ROLE_MANAGER, 32, 32, 4, 4);
    c.drive     = null;
    c.is_active = UVM_PASSIVE;
    expect_verdict("passive without drive", c, "");
    c         = make_cfg(AXI_ROLE_MANAGER, 32, 32, 4, 4);
    c.observe = null;
    expect_verdict("no observe proxy", c, "no observe");

    phase.drop_objection(this);
  endtask

  // Fresh cfg (default AXI4 features) for one role whose fake proxies report the
  // given widths: observe always, plus drive (Manager) or respond (Subordinate).
  protected function axi_agent_cfg make_cfg(axi_role_e role, int unsigned aw, int unsigned dw,
                                            int unsigned iw, int unsigned ir);
    axi_agent_cfg          c = axi_agent_cfg::type_id::create("cfg_under_test");
    axi_fake_monitor_proxy m = new("fake_observe");
    axi_fake_drive_proxy   d;
    axi_fake_respond_proxy r;
    m.aw      = aw;
    m.dw      = dw;
    m.iw      = iw;
    m.ir      = ir;
    c.role    = role;
    c.observe = m;
    if (role == AXI_ROLE_MANAGER) begin
      d       = new("fake_drive");
      d.aw    = aw;
      d.dw    = dw;
      d.iw    = iw;
      d.ir    = ir;
      c.drive = d;
    end else begin
      r         = new("fake_respond");
      r.aw      = aw;
      r.dw      = dw;
      r.iw      = iw;
      r.ir      = ir;
      c.respond = r;
    end
    return c;
  endfunction

  // want == "" means legal; otherwise the verdict must start with want
  protected function void expect_verdict(string what, axi_agent_cfg c, string want);
    string got = c.legality_error();
    bit    ok  = (want == "") ? (got == "") : (got.substr(0, want.len() - 1) == want);
    if (ok)
      `uvm_info("AXI_CFG_NEG", $sformatf("ok: %s -> \"%s\"", what, got), UVM_LOW)
    else
      `uvm_error("AXI_CFG_NEG", $sformatf("FAIL: %s -> \"%s\", expected %s", what, got,
                                          want == "" ? "legal" : {"\"", want, "...\""}))
  endfunction

endclass : axi_cfg_negative_test


// Builds the POC env and drives the two unfit writes on instance A (DW=32, ID 4/4).
class axi_width_negative_test extends axi_poc_base_test;
  `uvm_component_utils(axi_width_negative_test)

  axi_poc_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Full POC env: real adapters on the real bus.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axi_poc_env::type_id::create("env", this);
  endfunction

  // Pass if the adapter rejected both writes (AXI_ST_BAD_REQUEST) and no monitor
  // of bus A saw anything: no silent truncation (DATA-02, RISK-003).
  virtual task run_phase(uvm_phase phase);
    axi_unfit_seq seq = axi_unfit_seq::type_id::create("unfit");
    phase.raise_objection(this);
    // The adapter's rejections are the expected outcome (reported through uvm_root)
    uvm_root::get().set_report_severity_id_override(UVM_ERROR, "AXI_REQ", UVM_INFO);
    seq.start(env.mgr_a.sequencer);
    #200ns;
    if (seq.data_result.status != AXI_ST_BAD_REQUEST)
      `uvm_error("AXI_WIDTH_NEG", {"unfit data was not rejected: ",
                                   seq.data_result.convert2string()})
    if (seq.id_result.status != AXI_ST_BAD_REQUEST)
      `uvm_error("AXI_WIDTH_NEG", {"unfit ID was not rejected: ", seq.id_result.convert2string()})
    if (env.mgr_a.cfg.observe.get_transfer_count() != 0 ||
        env.mgr_a.cfg.observe.get_open_count() != 0)
      `uvm_error("AXI_WIDTH_NEG", "an unfit write reached the bus")
    phase.drop_objection(this);
  endtask

endclass : axi_width_negative_test
