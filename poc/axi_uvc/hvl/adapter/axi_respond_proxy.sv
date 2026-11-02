// -----------------------------------------------------------------------------
// axi_respond_proxy — concrete Subordinate respond adapter for one specialization
//
// Holds a typed virtual handle to axi_subordinate_bfm_if with exactly the
// parameters of the bound instance (ADR-001 decision 2). get_request() turns
// the next complete request of the BFM (plain values) into a new
// axi_transaction; send_response() converts a response item back to the bus
// widths and queues it in the BFM.
//
// Boundary rules (ADR-001 decision 4, AXI_PROTOCOL_CONTRACT section 6):
//   * a null handle, or a bus wider than the transaction maxima, is fatal at
//     construction (CFG-05)
//   * a response that does not fit the bus or breaks a response rule (EXOKAY
//     only for an exclusive access, AXI-R17/R24) is rejected with uvm_error and
//     status AXI_ST_BAD_REQUEST; nothing is truncated and nothing is queued
//
// Built explicitly by the integration code (no factory, ADR-001 decision 5).
// Included by axi_adapter_pkg.
// -----------------------------------------------------------------------------

class axi_respond_proxy #(
  int ADDR_WIDTH      = 32,
  int DATA_WIDTH      = 32,
  int ID_W_WIDTH      = 4,
  int ID_R_WIDTH      = 4,
  int USER_REQ_WIDTH  = 1,
  int USER_DATA_WIDTH = 1,
  int USER_RESP_WIDTH = 1,
  int QUEUE_DEPTH     = 8
) extends axi_respond_proxy_base;

  localparam int STRB_WIDTH   = DATA_WIDTH / 8;
  localparam int ID_MAX_WIDTH = (ID_W_WIDTH > ID_R_WIDTH) ? ID_W_WIDTH : ID_R_WIDTH;

  typedef virtual axi_subordinate_bfm_if #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .ID_W_WIDTH     (ID_W_WIDTH),
    .ID_R_WIDTH     (ID_R_WIDTH),
    .USER_REQ_WIDTH (USER_REQ_WIDTH),
    .USER_DATA_WIDTH(USER_DATA_WIDTH),
    .USER_RESP_WIDTH(USER_RESP_WIDTH),
    .QUEUE_DEPTH    (QUEUE_DEPTH)
  ) vif_t;

  protected vif_t          vif;
  protected axi_features_t features;

  // Bind to exactly one Subordinate-BFM instance (explicit construction, ADR-001
  // decision 5). A null handle or a bus wider than the maxima is fatal (CFG-05).
  function new(string name, vif_t vif);
    super.new(name);
    if (vif == null)
      `uvm_fatal("AXI_PROXY", $sformatf("%s: null Subordinate BFM handle", name))
    if (ADDR_WIDTH > AXI_MAX_AW || DATA_WIDTH > AXI_MAX_DW || ID_W_WIDTH > AXI_MAX_IDW ||
        ID_R_WIDTH > AXI_MAX_IDW)
      `uvm_fatal("AXI_PROXY", $sformatf(
        "%s: bus AW=%0d DW=%0d ID=%0d/%0d exceeds maxima AW=%0d DW=%0d ID=%0d (CFG-05)",
        name, ADDR_WIDTH, DATA_WIDTH, ID_W_WIDTH, ID_R_WIDTH, AXI_MAX_AW, AXI_MAX_DW,
        AXI_MAX_IDW))
    this.vif      = vif;
    this.features = axi_default_features();
  endfunction

  // Physical parameters of the bound bus; axi_agent_cfg compares them (CFG-06).
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
  virtual function void set_enable(bit en);
    vif.set_enable(en);
  endfunction

  virtual function void set_ready_delays(int unsigned aw, int unsigned w, int unsigned ar);
    vif.set_ready_delays(aw, w, ar);
  endfunction

  virtual function void set_fault(axi_fault_e fault);
    vif.set_fault(fault);
  endfunction

  virtual function int unsigned get_request_count();
    return vif.request_count;
  endfunction

  // Block until the BFM holds a complete request, then build a NEW transaction
  // (a response sequence may keep the handle). Fields are zero-extended to the
  // maxima with X/Z kept (DATA-02, LANG-04). len is AxLEN+1; wdata/wstrb hold the
  // write data beats that arrived (beats_done of them); data_delay is sized len
  // with zeros for the response sequence to fill.
  virtual task get_request(output axi_transaction req);
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
    logic [DATA_WIDTH-1:0]   wdata [AXI_MAX_BEATS];
    logic [STRB_WIDTH-1:0]   wstrb [AXI_MAX_BEATS];
    longint unsigned         req_cycle;
    int unsigned             req_epoch;

    vif.get_request(write, id, addr, len, size, burst, lock, cache, prot, qos, region, beats,
                    wdata, wstrb, req_cycle, req_epoch);

    req = axi_transaction::type_id::create("request");
    req.set_bus_context(ADDR_WIDTH, DATA_WIDTH, ID_W_WIDTH, ID_R_WIDTH,
                        features.protocol == AXI4_LITE);
    req.instance_name = get_name();
    req.dir           = write ? AXI_WRITE : AXI_READ;
    req.id            = AXI_MAX_IDW'(id);
    req.addr          = AXI_MAX_AW'(addr);
    req.len           = len;
    req.size          = axi_size_e'(size);
    req.burst         = axi_burst_e'(burst);
    req.lock          = lock;
    req.cache         = cache;
    req.prot          = prot;
    req.qos           = qos;
    req.region        = region;
    req.wdata         = new[beats];
    req.wstrb         = new[beats];
    for (int unsigned i = 0; i < beats; i++) begin
      req.wdata[i] = AXI_MAX_DW'(wdata[i]);
      req.wstrb[i] = AXI_MAX_SW'(wstrb[i]);
    end
    req.data_delay = new[len];
    req.beats_done = beats;
    req.addr_cycle = req_cycle;
    req.req_epoch  = req_epoch;
    req.status     = AXI_ST_OK;
  endtask

  // Convert the response item to the bus widths and queue it for the oldest open
  // request of its direction. Reports and refuses responses that do not fit or
  // break a response rule; the BFM refuses responses that answer no open request.
  virtual task send_response(axi_transaction rsp);
    logic [DATA_WIDTH-1:0] rdata [AXI_MAX_BEATS];
    logic [1:0]            rresp [AXI_MAX_BEATS];
    int unsigned           delay [AXI_MAX_BEATS];
    bit                    lite = (features.protocol == AXI4_LITE);

    rsp.instance_name = get_name();
    if (!response_ok(rsp, lite)) begin
      rsp.status = AXI_ST_BAD_REQUEST;
      return;
    end
    if (rsp.dir == AXI_WRITE) begin
      rsp.status = vif.put_write_response(rsp.req_epoch, ID_W_WIDTH'(rsp.id), rsp.bresp,
                                          rsp.resp_delay);
      report_refusal(rsp);
      return;
    end
    // response_ok() proved the read arrays have len entries that fit the bus
    for (int unsigned i = 0; i < AXI_MAX_BEATS; i++) begin
      rdata[i] = '0;
      rresp[i] = 2'b00;
      delay[i] = 0;
      if (i < rsp.len) begin
        rdata[i] = DATA_WIDTH'(rsp.rdata[i]);
        rresp[i] = rsp.rresp[i];
        delay[i] = rsp.data_delay[i];
      end
    end
    rsp.status = vif.put_read_response(rsp.req_epoch, ID_R_WIDTH'(rsp.id), rsp.len, rdata,
                                       rresp, delay);
    report_refusal(rsp);
  endtask

  // The BFM refuses a response that answers no open request: wrong direction
  // order, ID or length (AXI-R20, POL-05). That is a response-sequence bug.
  protected function void report_refusal(axi_transaction rsp);
    if (rsp.status == AXI_ST_BAD_REQUEST)
      `uvm_error("AXI_RSP", {get_name(), ": BFM refused the response; it answers no open ",
                             "request (ID, length or order): ", rsp.convert2string()})
  endfunction

  // Every reason a response cannot be queued as written; reports each one.
  protected function bit response_ok(axi_transaction rsp, bit lite);
    bit ok = 1'b1;
    if (rsp.dir == AXI_WRITE) begin
      if ($isunknown(rsp.bresp)) begin
        `uvm_error("AXI_RSP", {get_name(), ": X/Z write response: ", rsp.convert2string()})
        return 1'b0;
      end
      if (rsp.bresp == AXI_RESP_EXOKAY && (lite || rsp.lock !== 1'b1)) begin  // AXI-R17/R24
        `uvm_error("AXI_RSP", {get_name(), ": EXOKAY to a non-exclusive write: ",
                               rsp.convert2string()})
        ok = 1'b0;
      end
      return ok;
    end
    if (rsp.len == 0 || rsp.len > AXI_MAX_BEATS || rsp.rdata.size() != rsp.len ||
        rsp.rresp.size() != rsp.len || rsp.data_delay.size() != rsp.len) begin
      `uvm_error("AXI_RSP", $sformatf("%s: rdata/rresp/data_delay sizes %0d/%0d/%0d, len %0d",
                                      get_name(), rsp.rdata.size(), rsp.rresp.size(),
                                      rsp.data_delay.size(), rsp.len))
      return 1'b0;
    end
    foreach (rsp.rdata[i]) begin
      // Lossless rule (DATA-02): no read data bit at or above the bus width
      for (int unsigned b = DATA_WIDTH; b < AXI_MAX_DW; b++)
        if (rsp.rdata[i][b] !== 1'b0) begin
          `uvm_error("AXI_RSP", $sformatf("%s: rdata[%0d] %0h does not fit DW=%0d",
                                          get_name(), i, rsp.rdata[i], DATA_WIDTH))
          ok = 1'b0;
          break;
        end
      if ($isunknown(rsp.rresp[i])) begin
        `uvm_error("AXI_RSP", $sformatf("%s: X/Z RRESP on beat %0d", get_name(), i))
        ok = 1'b0;
      end else if (rsp.rresp[i] == AXI_RESP_EXOKAY && (lite || rsp.lock !== 1'b1)) begin
        `uvm_error("AXI_RSP", $sformatf("%s: EXOKAY on beat %0d of a non-exclusive read",
                                        get_name(), i))
        ok = 1'b0;
      end
    end
    return ok;
  endfunction

endclass : axi_respond_proxy
