// -----------------------------------------------------------------------------
// axi_monitor_proxy — concrete observe adapter for one bus specialization
//
// Holds a typed virtual handle to axi_monitor_bfm_if with exactly the
// parameters of the bound instance (ADR-001 decision 2). receive() takes the
// next completed transaction from the BFM (plain values, no UVM objects in
// HDL — ADR-002 section 6) and builds a new axi_transaction from it,
// zero-extending every field to the transaction maxima with X/Z preserved.
// wait_reset_event() does the same for reset edges (RST-4).
//
// Built explicitly by the integration code (no factory, ADR-001 decision 5).
// Included by axi_adapter_pkg.
// -----------------------------------------------------------------------------

class axi_monitor_proxy #(
  int ADDR_WIDTH      = 32,
  int DATA_WIDTH      = 32,
  int ID_W_WIDTH      = 4,
  int ID_R_WIDTH      = 4,
  int USER_REQ_WIDTH  = 1,
  int USER_DATA_WIDTH = 1,
  int USER_RESP_WIDTH = 1,
  int QUEUE_DEPTH     = 16,
  int MAX_OUTSTANDING = 16
) extends axi_monitor_proxy_base;

  localparam int STRB_WIDTH   = DATA_WIDTH / 8;
  localparam int ID_MAX_WIDTH = (ID_W_WIDTH > ID_R_WIDTH) ? ID_W_WIDTH : ID_R_WIDTH;

  typedef virtual axi_monitor_bfm_if #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .ID_W_WIDTH     (ID_W_WIDTH),
    .ID_R_WIDTH     (ID_R_WIDTH),
    .USER_REQ_WIDTH (USER_REQ_WIDTH),
    .USER_DATA_WIDTH(USER_DATA_WIDTH),
    .USER_RESP_WIDTH(USER_RESP_WIDTH),
    .QUEUE_DEPTH    (QUEUE_DEPTH),
    .MAX_OUTSTANDING(MAX_OUTSTANDING)
  ) vif_t;

  protected vif_t          vif;
  protected axi_features_t features;

  // Bind to exactly one monitor-BFM instance (explicit construction, ADR-001
  // decision 5). A null handle or a bus wider than the maxima is fatal (CFG-05).
  function new(string name, vif_t vif);
    super.new(name);
    if (vif == null)
      `uvm_fatal("AXI_PROXY", $sformatf("%s: null monitor BFM handle", name))
    if (ADDR_WIDTH > AXI_MAX_AW || DATA_WIDTH > AXI_MAX_DW || ID_W_WIDTH > AXI_MAX_IDW ||
        ID_R_WIDTH > AXI_MAX_IDW)
      `uvm_fatal("AXI_PROXY", $sformatf(
        "%s: bus AW=%0d DW=%0d ID=%0d/%0d exceeds maxima AW=%0d DW=%0d ID=%0d (CFG-05)",
        name, ADDR_WIDTH, DATA_WIDTH, ID_W_WIDTH, ID_R_WIDTH, AXI_MAX_AW, AXI_MAX_DW,
        AXI_MAX_IDW))
    this.vif      = vif;
    this.features = axi_default_features();
  endfunction

  // Physical parameters of the bound bus; axi_agent_cfg compares them (CFG-03/04/06).
  virtual function int unsigned get_addr_width();
    return ADDR_WIDTH;
  endfunction

  virtual function int unsigned get_data_width();
    return DATA_WIDTH;
  endfunction

  virtual function int unsigned get_id_w_width();
    return ID_W_WIDTH;
  endfunction

  virtual function int unsigned get_id_r_width();
    return ID_R_WIDTH;
  endfunction

  // Forward the feature set to the BFM; keep a copy for the bus context of items.
  virtual function bit configure(axi_features_t features);
    if (!vif.configure(features)) return 1'b0;
    this.features = features;
    return 1'b1;
  endfunction

  // Thin forwards to the bound BFM.
  virtual function void set_publish(bit en);
    vif.set_publish(en);
  endfunction

  virtual function void set_verbose(bit en);
    vif.set_verbose(en);
  endfunction

  // Block until the BFM reports a completed transaction, then build a NEW object
  // (subscribers may keep the handle). Fields are zero-extended to the maxima with
  // X/Z kept (DATA-02, LANG-04). len is AxLEN+1 and beats_done the data beats
  // recorded; the Manager's own delays are not part of an observation and stay 0.
  virtual task receive(output axi_transaction observed);
    bit                      write;
    logic [ID_MAX_WIDTH-1:0] id;
    logic [ADDR_WIDTH-1:0]   addr;
    int unsigned             len;
    logic [2:0]              size;
    logic [1:0]              burst;
    logic                    lock;
    logic [3:0]              cache;
    logic [2:0]              prot;
    logic [3:0]              qos;
    logic [3:0]              region;
    int unsigned             beats;
    logic [DATA_WIDTH-1:0]   data  [AXI_MAX_BEATS];
    logic [STRB_WIDTH-1:0]   strb  [AXI_MAX_BEATS];
    logic [1:0]              resp  [AXI_MAX_BEATS];
    int unsigned             addr_wait;
    int unsigned             dwait [AXI_MAX_BEATS];
    int unsigned             resp_wait;
    longint unsigned         addr_cycle;
    longint unsigned         first_data_cycle;
    longint unsigned         last_data_cycle;
    longint unsigned         resp_cycle;
    bit                      error_seen;

    vif.get_txn(write, id, addr, len, size, burst, lock, cache, prot, qos, region, beats, data,
                strb, resp, addr_wait, dwait, resp_wait, addr_cycle, first_data_cycle,
                last_data_cycle, resp_cycle);

    observed = axi_transaction::type_id::create("observed");
    observed.set_bus_context(ADDR_WIDTH, DATA_WIDTH, ID_W_WIDTH, ID_R_WIDTH,
                             features.protocol == AXI4_LITE);
    observed.instance_name    = get_name();
    observed.dir              = write ? AXI_WRITE : AXI_READ;
    observed.id               = AXI_MAX_IDW'(id);
    observed.resp_id          = AXI_MAX_IDW'(id);
    observed.addr             = AXI_MAX_AW'(addr);
    observed.len              = len;
    observed.size             = axi_size_e'(size);
    observed.burst            = axi_burst_e'(burst);
    observed.lock             = lock;
    observed.cache            = cache;
    observed.prot             = prot;
    observed.qos              = qos;
    observed.region           = region;
    observed.beats_done       = beats;
    observed.addr_wait        = addr_wait;
    observed.resp_wait        = resp_wait;
    observed.addr_cycle       = addr_cycle;
    observed.first_data_cycle = first_data_cycle;
    observed.last_data_cycle  = last_data_cycle;
    observed.resp_cycle       = resp_cycle;
    observed.data_delay       = new[beats];  // not observable; stays 0
    observed.data_wait        = new[beats];
    for (int unsigned i = 0; i < beats; i++) observed.data_wait[i] = dwait[i];
    error_seen = 1'b0;
    if (write) begin
      observed.wdata = new[beats];
      observed.wstrb = new[beats];
      for (int unsigned i = 0; i < beats; i++) begin
        observed.wdata[i] = AXI_MAX_DW'(data[i]);
        observed.wstrb[i] = AXI_MAX_SW'(strb[i]);
      end
      observed.bresp = resp[0];
      error_seen     = axi_resp_is_error(resp[0]);
    end else begin
      observed.wdata = new[beats];  // new[] of 4-state elements gives X: zeroed below
      observed.wstrb = new[beats];
      observed.rdata = new[beats];
      observed.rresp = new[beats];
      for (int unsigned i = 0; i < beats; i++) begin
        observed.wdata[i] = '0;     // reads carry no write data
        observed.wstrb[i] = '0;
        observed.rdata[i] = AXI_MAX_DW'(data[i]);
        observed.rresp[i] = resp[i];
        if (axi_resp_is_error(resp[i])) error_seen = 1'b1;
      end
    end
    observed.status = error_seen ? AXI_ST_ERROR : AXI_ST_OK;
  endtask

  // Block until the BFM reports a reset edge (RST-4); a new object per edge.
  virtual task wait_reset_event(output axi_reset_event ev);
    bit              asserted;
    longint unsigned at_cycle;
    vif.get_reset_event(asserted, at_cycle);
    ev               = axi_reset_event::type_id::create("reset_event");
    ev.asserted      = asserted;
    ev.cycle         = at_cycle;
    ev.instance_name = get_name();
  endtask

  // BFM counters, read by axi_monitor in check_phase and report_phase.
  virtual function int unsigned get_error_count(axi_mon_error_e code);
    return vif.get_error_count(code);
  endfunction

  virtual function int unsigned get_total_errors();
    return vif.get_total_errors();
  endfunction

  virtual function void clear_errors();
    vif.clear_errors();
  endfunction

  virtual function int unsigned get_transfer_count();
    return vif.transfer_count;
  endfunction

  virtual function int unsigned get_reset_count();
    return vif.reset_count;
  endfunction

  virtual function int unsigned get_open_count();
    return vif.get_open_count();
  endfunction

endclass : axi_monitor_proxy
