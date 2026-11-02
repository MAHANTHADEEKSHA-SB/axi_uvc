// -----------------------------------------------------------------------------
// axi_hvl_top — HVL integration example: bind adapters, register cfg, run
//
// The only place that connects the width-independent UVM core to the
// physical instances in axi_hdl_top (ADR-002 configuration flow):
//   1. construct one width-specialized adapter per capability and agent,
//      each bound to that agent's own BFM (explicit, no factory)
//   2. put them as base-class handles into one axi_agent_cfg per agent
//   3. register each cfg ONCE at the exact agent path
//   4. run_test()
// Per bus: a Manager agent (drive + observe) and a Subordinate agent
// (respond + observe), each with its own monitor BFM. Instance P is passive:
// it gets an observe adapter only, so no drive or respond capability exists
// for it (ADR-002 decision 6). Instance A's Subordinate applies READY
// back-pressure (POL-06), which the fault modes 1 and 2 need; B is
// default-ready. The reset-control helper gives tests a way to pulse an
// instance's reset without hierarchical references in package code (LANG-12).
// Elaborate with both tops: axi_hdl_top and axi_hvl_top.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module axi_hvl_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi_bfm_pkg::*;
  import axi_api_pkg::*;
  import axi_uvc_pkg::*;
  import axi_adapter_pkg::*;
  import axi_poc_test_pkg::*;

  // Adapter specializations; their parameters equal those of the BFM instances in
  // axi_hdl_top (A and P: AW=32 DW=32 ID 4/4; B: AW=40 DW=64 ID 6/5).
  typedef axi_drive_proxy #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) drive_a_t;
  typedef axi_respond_proxy #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) respond_a_t;
  typedef axi_monitor_proxy #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) observe_a_t;
  typedef axi_drive_proxy #(
    .ADDR_WIDTH (40),
    .DATA_WIDTH (64),
    .ID_W_WIDTH (6),
    .ID_R_WIDTH (5)
  ) drive_b_t;
  typedef axi_respond_proxy #(
    .ADDR_WIDTH (40),
    .DATA_WIDTH (64),
    .ID_W_WIDTH (6),
    .ID_R_WIDTH (5)
  ) respond_b_t;
  typedef axi_monitor_proxy #(
    .ADDR_WIDTH (40),
    .DATA_WIDTH (64),
    .ID_W_WIDTH (6),
    .ID_R_WIDTH (5)
  ) observe_b_t;

  // Test helper: pulses the reset generators of axi_hdl_top on request. Lives here
  // because only integration code may use hierarchical references (LANG-12).
  class axi_hvl_reset_ctrl extends axi_poc_reset_ctrl;
    function new(string name = "axi_hvl_reset_ctrl");
      super.new(name);
    endfunction

    // inst "a" or "b"; anything else is a test bug.
    virtual task pulse_reset(string inst, int unsigned cycles);
      case (inst)
        "a":     axi_hdl_top.pulse_reset_a(cycles);
        "b":     axi_hdl_top.pulse_reset_b(cycles);
        default: `uvm_fatal("AXI_RESET", {"no reset generator for instance ", inst})
      endcase
    endtask
  endclass : axi_hvl_reset_ctrl

  // Runs once at time 0, before any UVM phase: the adapters and cfg objects must
  // exist before run_test() builds the agents, which fetch their cfg in build_phase.
  initial begin : bind_and_run
    drive_a_t          drive_a;
    respond_a_t        respond_a;
    observe_a_t        observe_a_mgr;
    observe_a_t        observe_a_sub;
    observe_a_t        observe_p;
    drive_b_t          drive_b;
    respond_b_t        respond_b;
    observe_b_t        observe_b_mgr;
    observe_b_t        observe_b_sub;
    axi_agent_cfg      cfg_a_mgr;
    axi_agent_cfg      cfg_a_sub;
    axi_agent_cfg      cfg_p;
    axi_agent_cfg      cfg_b_mgr;
    axi_agent_cfg      cfg_b_sub;
    axi_hvl_reset_ctrl reset_ctrl;

    // Instance A, Manager agent: AW=32, DW=32
    drive_a           = new("drive_a", axi_hdl_top.mgr_a);
    observe_a_mgr     = new("observe_a_mgr", axi_hdl_top.mon_a_mgr);
    cfg_a_mgr         = axi_agent_cfg::type_id::create("cfg_a_mgr");
    cfg_a_mgr.role    = AXI_ROLE_MANAGER;
    cfg_a_mgr.drive   = drive_a;
    cfg_a_mgr.observe = observe_a_mgr;
    uvm_config_db#(axi_agent_cfg)::set(null, "uvm_test_top.env.mgr_a", "cfg", cfg_a_mgr);

    // Instance A, Subordinate agent, with READY back-pressure on AW, W and AR
    respond_a                = new("respond_a", axi_hdl_top.sub_a);
    observe_a_sub            = new("observe_a_sub", axi_hdl_top.mon_a_sub);
    cfg_a_sub                = axi_agent_cfg::type_id::create("cfg_a_sub");
    cfg_a_sub.role           = AXI_ROLE_SUBORDINATE;
    cfg_a_sub.respond        = respond_a;
    cfg_a_sub.observe        = observe_a_sub;
    cfg_a_sub.aw_ready_delay = 1;
    cfg_a_sub.w_ready_delay  = 1;
    cfg_a_sub.ar_ready_delay = 2;
    uvm_config_db#(axi_agent_cfg)::set(null, "uvm_test_top.env.sub_a", "cfg", cfg_a_sub);

    // Instance P: passive observer of bus A (no drive or respond proxy is built)
    observe_p       = new("observe_p", axi_hdl_top.mon_p);
    cfg_p           = axi_agent_cfg::type_id::create("cfg_p");
    cfg_p.role      = AXI_ROLE_MANAGER;
    cfg_p.is_active = UVM_PASSIVE;
    cfg_p.observe   = observe_p;
    uvm_config_db#(axi_agent_cfg)::set(null, "uvm_test_top.env.agent_p", "cfg", cfg_p);

    // Instance B, Manager agent: AW=40, DW=64, ID 6/5
    drive_b           = new("drive_b", axi_hdl_top.mgr_b);
    observe_b_mgr     = new("observe_b_mgr", axi_hdl_top.mon_b_mgr);
    cfg_b_mgr         = axi_agent_cfg::type_id::create("cfg_b_mgr");
    cfg_b_mgr.role    = AXI_ROLE_MANAGER;
    cfg_b_mgr.drive   = drive_b;
    cfg_b_mgr.observe = observe_b_mgr;
    uvm_config_db#(axi_agent_cfg)::set(null, "uvm_test_top.env.mgr_b", "cfg", cfg_b_mgr);

    // Instance B, Subordinate agent (default-ready)
    respond_b         = new("respond_b", axi_hdl_top.sub_b);
    observe_b_sub     = new("observe_b_sub", axi_hdl_top.mon_b_sub);
    cfg_b_sub         = axi_agent_cfg::type_id::create("cfg_b_sub");
    cfg_b_sub.role    = AXI_ROLE_SUBORDINATE;
    cfg_b_sub.respond = respond_b;
    cfg_b_sub.observe = observe_b_sub;
    uvm_config_db#(axi_agent_cfg)::set(null, "uvm_test_top.env.sub_b", "cfg", cfg_b_sub);

    // Reset control for axi_reset_test (test helper, not part of the UVC)
    reset_ctrl = new("reset_ctrl");
    uvm_config_db#(axi_poc_reset_ctrl)::set(null, "uvm_test_top", "reset_ctrl", reset_ctrl);

    run_test("axi_poc_test");
  end

endmodule : axi_hvl_top
