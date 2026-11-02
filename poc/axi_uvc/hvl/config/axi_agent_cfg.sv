// -----------------------------------------------------------------------------
// axi_agent_cfg — configuration of ONE AXI UVC agent instance (ADR-002 decision 6)
//
// Carries the role, the capability handles, the active/passive policy, the
// protocol mode and the UVC policies. The integration code fills one object
// per agent instance and registers it once with
//   uvm_config_db#(axi_agent_cfg)::set(null, "<exact agent path>", "cfg", cfg)
// The agent retrieves it once and hands it to its children (UVM-06; this
// settles the open item of docs/ARCHITECTURE_DECISIONS.md, decision A-7).
// Never share an object between instances.
//
// validate() enforces AXI_PROTOCOL_CONTRACT section 2.3 (CFG-01..04, CFG-06,
// CFG-07) and the milestone M1 limits; legality_error() returns the same
// verdict as text so negative tests can check it without a fatal.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

// Role an agent plays on its bus (owner decision A-1: Manager and Subordinate)
typedef enum int unsigned {
  AXI_ROLE_MANAGER     = 0,
  AXI_ROLE_SUBORDINATE = 1
} axi_role_e;

class axi_agent_cfg extends uvm_object;
  `uvm_object_utils(axi_agent_cfg)

  // Role and capability handles. An active Manager needs drive, an active
  // Subordinate needs respond; observe is always needed.
  axi_role_e              role      = AXI_ROLE_MANAGER;
  axi_drive_proxy_base    drive;
  axi_respond_proxy_base  respond;
  axi_monitor_proxy_base  observe;

  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // Protocol mode (owner decision A-2: AXI4, or AXI4-Lite by configuration)
  axi_features_t          features;

  // Policies (AXI_PROTOCOL_CONTRACT sections 4-6)
  int unsigned            max_wait_cycles        = 1024;  // POL-01; 0 = no watchdog
  int unsigned            post_reset_idle_cycles = 1;     // RST-5 (Manager)
  bit                     allow_x_wdata          = 1'b0;  // section 6 (Manager)
  int unsigned            aw_ready_delay         = 0;     // POL-06 (Subordinate)
  int unsigned            w_ready_delay          = 0;
  int unsigned            ar_ready_delay         = 0;
  bit                     enable_coverage        = 1'b1;
  bit                     monitor_verbose        = 1'b1;  // BFM prints each violation
  bit                     check_open_at_end      = 1'b1;  // transactions left open = error

  // Default protocol mode (AXI_PROTOCOL_CONTRACT Q2, proposed).
  function new(string name = "axi_agent_cfg");
    super.new(name);
    features = axi_default_features();
  endfunction

  // Physical bus parameters, taken from the observe adapter
  function int unsigned addr_width();
    return (observe == null) ? 0 : observe.get_addr_width();
  endfunction

  function int unsigned data_width();
    return (observe == null) ? 0 : observe.get_data_width();
  endfunction

  function int unsigned id_w_width();
    return (observe == null) ? 0 : observe.get_id_w_width();
  endfunction

  function int unsigned id_r_width();
    return (observe == null) ? 0 : observe.get_id_r_width();
  endfunction

  // "" when the configuration is legal, otherwise the first problem found
  function string legality_error();
    int unsigned aw;
    int unsigned dw;
    int unsigned iw;
    int unsigned ir;
    string       problem;

    if (observe == null)
      return "no observe (monitor) proxy bound";
    // CFG-07: an active agent needs the capability of its role
    if (is_active == UVM_ACTIVE && role == AXI_ROLE_MANAGER && drive == null)
      return "CFG-07: active Manager agent without a drive proxy";
    if (is_active == UVM_ACTIVE && role == AXI_ROLE_SUBORDINATE && respond == null)
      return "CFG-07: active Subordinate agent without a respond proxy";

    aw = observe.get_addr_width();
    dw = observe.get_data_width();
    iw = observe.get_id_w_width();
    ir = observe.get_id_r_width();

    // CFG-06: every adapter must be bound to the same bus specialization
    if (drive != null && (drive.get_addr_width() != aw || drive.get_data_width() != dw ||
                          drive.get_id_w_width() != iw || drive.get_id_r_width() != ir))
      return $sformatf("CFG-06: drive proxy AW=%0d DW=%0d ID=%0d/%0d, observe AW=%0d DW=%0d %s",
                       drive.get_addr_width(), drive.get_data_width(), drive.get_id_w_width(),
                       drive.get_id_r_width(), aw, dw, $sformatf("ID=%0d/%0d", iw, ir));
    if (respond != null && (respond.get_addr_width() != aw || respond.get_data_width() != dw ||
                            respond.get_id_w_width() != iw || respond.get_id_r_width() != ir))
      return $sformatf("CFG-06: respond proxy AW=%0d DW=%0d ID=%0d/%0d, observe AW=%0d %s",
                       respond.get_addr_width(), respond.get_data_width(),
                       respond.get_id_w_width(), respond.get_id_r_width(), aw,
                       $sformatf("DW=%0d ID=%0d/%0d", dw, iw, ir));
    // CFG-03: address width
    if (aw < 1 || aw > 64)
      return $sformatf("CFG-03: ADDR_WIDTH=%0d outside 1..64", aw);
    // CFG-04: IHI 0022 data bus widths
    if (!(dw inside {8, 16, 32, 64, 128, 256, 512, 1024}))
      return $sformatf("CFG-04: DATA_WIDTH=%0d not in {8,16,...,1024}", dw);
    // CFG-01: protocol mode (AXI4-Lite: DATA_WIDTH 32 or 64, no user signals)
    problem = axi_protocol_problem(features, dw);
    if (problem != "") return {"CFG-01: ", problem};
    // CFG-02: features of later milestones
    problem = axi_milestone_problem(features);
    if (problem != "") return {"CFG-02: ", problem};
    return "";
  endfunction

  // Fatal on any legality_error() (UVM-08). Warnings only for capabilities the
  // agent will not use.
  function void validate();
    string problem = legality_error();
    if (problem != "")
      `uvm_fatal("AXI_CFG", {get_name(), ": ", problem})
    if (is_active == UVM_PASSIVE && (drive != null || respond != null))
      `uvm_warning("AXI_CFG", {get_name(), ": passive agent has a drive/respond proxy; ",
                               "it will not be used"})
    if (role == AXI_ROLE_MANAGER && respond != null)
      `uvm_warning("AXI_CFG", {get_name(), ": Manager agent has a respond proxy; unused"})
    if (role == AXI_ROLE_SUBORDINATE && drive != null)
      `uvm_warning("AXI_CFG", {get_name(), ": Subordinate agent has a drive proxy; unused"})
  endfunction

  // One-line summary, printed by the agent at build time.
  virtual function string convert2string();
    return $sformatf("%s: %s %s %s AW=%0d DW=%0d ID=%0d/%0d max_wait=%0d ready_delay=%0d/%0d/%0d",
                     get_name(), role.name(), is_active.name(), features.protocol.name(),
                     addr_width(), data_width(), id_w_width(), id_r_width(), max_wait_cycles,
                     aw_ready_delay, w_ready_delay, ar_ready_delay);
  endfunction

endclass : axi_agent_cfg
