// -----------------------------------------------------------------------------
// axi_drive_proxy — concrete Manager drive adapter for one bus specialization
//
// Holds a typed virtual handle to axi_manager_bfm_if with exactly the
// parameters of the bound instance (ADR-001 decision 2) and converts the
// width-independent axi_transaction into a BFM do_write()/do_read() call.
//
// Boundary rules (ADR-001 decision 4, AXI_PROTOCOL_CONTRACT section 6):
//   * a null handle, or a bus wider than the transaction maxima, is fatal at
//     construction (CFG-05)
//   * a request that cannot be driven losslessly or legally is rejected with
//     uvm_error and status AXI_ST_BAD_REQUEST; nothing is truncated and
//     nothing reaches the bus
//
// Built explicitly by the integration code (no factory, ADR-001 decision 5).
// Included by axi_adapter_pkg.
// -----------------------------------------------------------------------------

class axi_drive_proxy #(
  int ADDR_WIDTH      = 32,
  int DATA_WIDTH      = 32,
  int ID_W_WIDTH      = 4,
  int ID_R_WIDTH      = 4,
  int USER_REQ_WIDTH  = 1,
  int USER_DATA_WIDTH = 1,
  int USER_RESP_WIDTH = 1
) extends axi_drive_proxy_base;

  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  typedef virtual axi_manager_bfm_if #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .ID_W_WIDTH     (ID_W_WIDTH),
    .ID_R_WIDTH     (ID_R_WIDTH),
    .USER_REQ_WIDTH (USER_REQ_WIDTH),
    .USER_DATA_WIDTH(USER_DATA_WIDTH),
    .USER_RESP_WIDTH(USER_RESP_WIDTH)
  ) vif_t;

  protected vif_t          vif;
  protected axi_features_t features;

  // Bind to exactly one Manager-BFM instance (explicit construction, ADR-001
  // decision 5). A null handle or a bus wider than the maxima is fatal (CFG-05).
  function new(string name, vif_t vif);
    super.new(name);
    if (vif == null)
      `uvm_fatal("AXI_PROXY", $sformatf("%s: null Manager BFM handle", name))
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

  // Forward the feature set to the BFM and keep a copy for request_ok(); 0 when
  // the BFM rejects it.
  virtual function bit configure(axi_features_t features);
    if (!vif.configure(features)) return 1'b0;
    this.features = features;
    return 1'b1;
  endfunction

  // Thin forwards to the bound BFM.
  virtual function void set_enable(bit en);
    vif.set_enable(en);
  endfunction

  virtual function void set_fault(axi_fault_e fault);
    vif.set_fault(fault);
  endfunction

  virtual task wait_for_reset_release(int unsigned idle_cycles);
    vif.wait_for_reset_release(idle_cycles);
  endtask

  // Run one transaction for req: stamp the bus context, reject anything that
  // cannot be driven losslessly or legally (AXI_ST_BAD_REQUEST, nothing on the
  // bus), convert to the bus widths, and write the result back into req.
  virtual task send(axi_transaction req);
    logic [DATA_WIDTH-1:0] wdata [AXI_MAX_BEATS];
    logic [STRB_WIDTH-1:0] wstrb [AXI_MAX_BEATS];
    int unsigned           ddly  [AXI_MAX_BEATS];
    logic [DATA_WIDTH-1:0] rdata [AXI_MAX_BEATS];
    logic [1:0]            rresp [AXI_MAX_BEATS];
    int unsigned           dwait [AXI_MAX_BEATS];
    logic [ID_W_WIDTH-1:0] bid;
    logic [ID_R_WIDTH-1:0] rid;
    logic [1:0]            bresp;
    int unsigned           done;
    int unsigned           awt;
    int unsigned           bwt;
    axi_bfm_status_e       st;

    req.instance_name = get_name();
    req.set_bus_context(ADDR_WIDTH, DATA_WIDTH, ID_W_WIDTH, ID_R_WIDTH,
                        features.protocol == AXI4_LITE);
    req.beats_done = 0;
    req.addr_wait  = 0;
    req.resp_wait  = 0;
    req.bresp      = 2'b00;
    req.resp_id    = '0;
    req.rdata.delete();
    req.rresp.delete();
    req.data_wait.delete();
    if (!request_ok(req)) begin
      req.status = AXI_ST_BAD_REQUEST;
      return;
    end

    // Narrow each beat to the bus; request_ok() proved the upper bits are 0.
    for (int unsigned i = 0; i < AXI_MAX_BEATS; i++) begin
      wdata[i] = '0;
      wstrb[i] = '0;
      ddly[i]  = 0;
      if (i < req.len) begin
        if (req.dir == AXI_WRITE) begin
          wdata[i] = DATA_WIDTH'(req.wdata[i]);
          wstrb[i] = STRB_WIDTH'(req.wstrb[i]);
        end
        ddly[i] = req.data_delay[i];
      end
    end

    if (req.dir == AXI_WRITE) begin
      vif.do_write(ID_W_WIDTH'(req.id), ADDR_WIDTH'(req.addr), req.len, req.size, req.burst,
                   req.lock, req.cache, req.prot, req.qos, req.region, wdata, wstrb,
                   req.addr_delay, ddly, req.resp_ready_delay, max_wait_cycles,
                   bid, bresp, done, awt, dwait, bwt, st);
      req.resp_id   = AXI_MAX_IDW'(bid);
      req.bresp     = bresp;
      req.resp_wait = bwt;
    end else begin
      vif.do_read(ID_R_WIDTH'(req.id), ADDR_WIDTH'(req.addr), req.len, req.size, req.burst,
                  req.lock, req.cache, req.prot, req.qos, req.region, req.addr_delay,
                  req.resp_ready_delay, max_wait_cycles, rid, rdata, rresp, done, awt, dwait,
                  st);
      req.resp_id = AXI_MAX_IDW'(rid);
      req.rdata   = new[req.len];
      req.rresp   = new[req.len];
      for (int unsigned i = 0; i < req.len; i++) begin
        req.rdata[i] = AXI_MAX_DW'(rdata[i]);  // zero-extended, 4-state preserved
        req.rresp[i] = rresp[i];
      end
    end
    req.data_wait = new[req.len];
    for (int unsigned i = 0; i < req.len; i++) req.data_wait[i] = dwait[i];
    req.addr_wait  = awt;
    req.beats_done = done;
    req.status     = st;
  endtask

  // Every reason a request cannot be driven as written; reports each one.
  protected function bit request_ok(axi_transaction req);
    bit                    ok = 1'b1;
    bit                    lite = (features.protocol == AXI4_LITE);
    logic [AXI_MAX_SW-1:0] lanes;
    string                 issue;

    if ($isunknown({req.id, req.addr, req.lock, req.cache, req.prot, req.qos, req.region})) begin
      `uvm_error("AXI_REQ", {get_name(), ": X/Z in id/addr/lock/cache/prot/qos/region: ",
                             req.convert2string()})
      return 1'b0;  // the checks below need known values
    end
    if (!axi_burst_len_ok(req.burst, req.len)) begin                        // AXI-R08/R10
      `uvm_error("AXI_REQ", $sformatf("%s: %s with %0d beats is illegal", get_name(),
                                      req.burst.name(), req.len))
      return 1'b0;  // the array checks below need a legal length
    end
    if (req.wdata.size() != req.len || req.wstrb.size() != req.len ||
        req.data_delay.size() != req.len) begin
      `uvm_error("AXI_REQ", $sformatf("%s: wdata/wstrb/data_delay sizes %0d/%0d/%0d, len %0d",
                                      get_name(), req.wdata.size(), req.wstrb.size(),
                                      req.data_delay.size(), req.len))
      return 1'b0;
    end
    if (req.beat_bytes() > DATA_WIDTH / 8) begin                            // AXI-R09
      `uvm_error("AXI_REQ", $sformatf("%s: AxSIZE %s is wider than DW=%0d", get_name(),
                                      req.size.name(), DATA_WIDTH))
      return 1'b0;  // the lane and page checks assume a legal size
    end
    if (lite && (req.len != 1 || req.beat_bytes() != DATA_WIDTH / 8 ||
                 req.burst != AXI_BURST_INCR || req.id != 0 || req.lock != 1'b0 ||
                 req.cache != 4'h0 || req.qos != 4'h0 || req.region != 4'h0)) begin  // R24
      `uvm_error("AXI_REQ", {get_name(), ": AXI4-Lite takes one full-width beat with no ID, ",
                             "LOCK, CACHE, QOS or REGION: ", req.convert2string()})
      ok = 1'b0;
    end
    if (req.burst == AXI_BURST_WRAP && (req.addr % req.beat_bytes()) != 0) begin  // AXI-R11
      `uvm_error("AXI_REQ", $sformatf("%s: WRAP at %0h not aligned to %0d bytes", get_name(),
                                      req.addr, req.beat_bytes()))
      ok = 1'b0;
    end
    if (axi_crosses_4kb(AXI_FN_AW'(req.addr), req.size, req.burst, req.len)) begin  // R12
      `uvm_error("AXI_REQ", $sformatf("%s: INCR at %0h of %0d x %0dB crosses 4KB", get_name(),
                                      req.addr, req.len, req.beat_bytes()))
      ok = 1'b0;
    end
    if (req.lock == 1'b1) begin                                             // AXI-R18
      issue = axi_exclusive_problem(AXI_FN_AW'(req.addr), req.size, req.len);
      if (issue != "") begin
        `uvm_error("AXI_REQ", {get_name(), ": ", issue})
        ok = 1'b0;
      end
    end
    if (!axi_cache_ok(req.cache)) begin                                     // AXI-R19
      `uvm_error("AXI_REQ", $sformatf("%s: AxCACHE %b is not a legal memory type", get_name(),
                                      req.cache))
      ok = 1'b0;
    end
    // Lossless rule (DATA-02): every bit at or above a bus width must be a known 0.
    if (!upper_zero(AXI_MAX_FW'(req.addr), ADDR_WIDTH, AXI_MAX_AW)) begin
      `uvm_error("AXI_REQ", $sformatf("%s: addr %0h does not fit AW=%0d", get_name(),
                                      req.addr, ADDR_WIDTH))
      ok = 1'b0;
    end
    if (!upper_zero(AXI_MAX_FW'(req.id), (req.dir == AXI_WRITE) ? ID_W_WIDTH : ID_R_WIDTH,
                    AXI_MAX_IDW)) begin
      `uvm_error("AXI_REQ", $sformatf("%s: id %0h does not fit ID width %0d/%0d", get_name(),
                                      req.id, ID_W_WIDTH, ID_R_WIDTH))
      ok = 1'b0;
    end
    if (req.dir == AXI_WRITE) begin
      foreach (req.wdata[i]) begin
        lanes = req.lanes_of(i);
        if (!upper_zero(AXI_MAX_FW'(req.wdata[i]), DATA_WIDTH, AXI_MAX_DW) ||
            !upper_zero(AXI_MAX_FW'(req.wstrb[i]), DATA_WIDTH / 8, AXI_MAX_SW)) begin
          `uvm_error("AXI_REQ", $sformatf("%s: beat %0d data %0h / strobe %0h does not fit DW=%0d",
                                          get_name(), i, req.wdata[i], req.wstrb[i],
                                          DATA_WIDTH))
          ok = 1'b0;
        end
        if ($isunknown(req.wstrb[i]) || (req.wstrb[i] & ~lanes) != '0) begin  // AXI-R14
          `uvm_error("AXI_REQ", $sformatf("%s: beat %0d strobe %b outside its lanes %b",
                                          get_name(), i, req.wstrb[i], lanes))
          ok = 1'b0;
        end
        if (!allow_x_wdata && strobed_unknown(req.wdata[i], req.wstrb[i])) begin
          `uvm_error("AXI_REQ", $sformatf("%s: X/Z in strobed write data of beat %0d",
                                          get_name(), i))
          ok = 1'b0;
        end
      end
    end
    return ok;
  endfunction

  // 1 when every bit of value at index >= width (up to max) is a known 0. The
  // argument is as wide as the widest field (AXI_MAX_FW), so nothing is cut off
  // before the check. Written as a loop rather than `value >> width`, which would
  // shift by the full operand width when the bus is as wide as the maxima (LANG-05).
  protected function bit upper_zero(logic [AXI_MAX_FW-1:0] value, int unsigned width,
                                    int unsigned max);
    for (int unsigned i = width; i < max; i++)
      if (value[i] !== 1'b0) return 1'b0;
    return 1'b1;
  endfunction

  // 1 when a strobed byte lane of the write data is X/Z
  protected function bit strobed_unknown(logic [AXI_MAX_DW-1:0] data,
                                         logic [AXI_MAX_SW-1:0] strb);
    for (int unsigned l = 0; l < DATA_WIDTH / 8; l++)
      if (strb[l] === 1'b1 && $isunknown(data[8*l +: 8])) return 1'b1;
    return 1'b0;
  endfunction

endclass : axi_drive_proxy
