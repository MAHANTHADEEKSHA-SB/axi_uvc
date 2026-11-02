// -----------------------------------------------------------------------------
// axi_transaction — one AXI transaction, independent of the bus widths
//
// The same class serves every instance, both roles and the monitor (ADR-001
// decision 1; owner decision A-3: one shared transaction, no per-role
// subclass). One item is one transaction: a write (address, len beats of
// data with strobes, one response) or a read (address, len beats of data with
// a response each). Payload fields use the compile-time maxima AXI_MAX_*;
// bits at or above the bound bus widths must be zero, and the adapters
// reject any other value instead of truncating it (AXI_PROTOCOL_CONTRACT
// section 6). wdata/rdata hold whole bus words with the byte lanes as they
// appear on WDATA/RDATA; lanes_of() names the active lanes of a beat.
//
// Who fills what:
//   Manager item   request fields + addr_delay, data_delay (W beats),
//                  resp_ready_delay; the driver fills the response fields
//   Subordinate    the respond adapter fills the request fields; a response
//                  sequence sets bresp or rdata/rresp, resp_delay and
//                  data_delay (R beats) on its response item
//   Monitor        every bus-visible field plus the wait counts and cycles
// All payload and response fields are 4-state `logic`: observed X/Z values
// are kept. The bus context (widths, protocol mode) is copied from the agent
// configuration before randomization, so constraints keep generated values
// legal for the instance the item will run on.
// Included by axi_api_pkg.
// -----------------------------------------------------------------------------

typedef enum bit {
  AXI_READ  = 1'b0,
  AXI_WRITE = 1'b1
} axi_dir_e;

// Request fields are randomized by sequences; everything else is filled in place.
class axi_transaction extends uvm_sequence_item;
  `uvm_object_utils(axi_transaction)

  // ---- Request ----------------------------------------------------------------
  rand axi_dir_e               dir;
  rand logic [AXI_MAX_IDW-1:0] id;      // AWID / ARID
  rand logic [AXI_MAX_AW-1:0]  addr;    // AxADDR: start address (INCR/FIXED may be unaligned)
  rand axi_burst_e             burst;   // AxBURST
  rand axi_size_e              size;    // AxSIZE
  rand int unsigned            len;     // beats = AxLEN + 1
  rand logic                   lock;    // AxLOCK: exclusive access
  rand logic [3:0]             cache;   // AxCACHE
  rand logic [2:0]             prot;    // AxPROT
  rand logic [3:0]             qos;     // AxQOS
  rand logic [3:0]             region;  // AxREGION
  rand logic [AXI_MAX_DW-1:0]  wdata[]; // one bus word per beat (writes)
       logic [AXI_MAX_SW-1:0]  wstrb[]; // per beat; post_randomize() sets the active lanes

  // ---- Timing -------------------------------------------------------------------
  rand int unsigned addr_delay;        // Manager: edges before AxVALID
  rand int unsigned data_delay[];      // data source: edges before each beat's VALID
                                       // (W beats by the Manager, R beats by the Subordinate)
  rand int unsigned resp_ready_delay;  // Manager: cycles BREADY/RREADY wait after VALID
  rand int unsigned resp_delay;        // Subordinate: edges before BVALID

  // Knobs for randomization
  int unsigned max_addr_delay  = 2;
  int unsigned max_data_delay  = 1;
  int unsigned max_ready_delay = 2;
  int unsigned max_resp_delay  = 2;
  bit          random_wstrb    = 1'b0;  // post_randomize(): random subset of the active lanes

  // ---- Bus context (not randomized) --------------------------------------------
  int unsigned            bus_addr_width = AXI_MAX_AW;
  int unsigned            bus_data_width = AXI_MAX_DW;
  int unsigned            bus_id_w_width = AXI_MAX_IDW;
  int unsigned            bus_id_r_width = AXI_MAX_IDW;
  int unsigned            bus_max_size   = 0;     // log2(bus_data_width / 8)
  bit                     bus_lite       = 1'b0;  // AXI4-Lite instance
  logic [AXI_MAX_AW-1:0]  addr_over_mask = '0;    // bits at or above bus_addr_width
  logic [AXI_MAX_DW-1:0]  data_over_mask = '0;    // bits at or above bus_data_width
  logic [AXI_MAX_SW-1:0]  strb_over_mask = '0;    // lanes at or above bus_data_width / 8
  logic [AXI_MAX_IDW-1:0] idw_over_mask  = '0;    // bits at or above bus_id_w_width
  logic [AXI_MAX_IDW-1:0] idr_over_mask  = '0;    // bits at or above bus_id_r_width

  // ---- Response / observation ---------------------------------------------------
  logic [1:0]             bresp;             // BRESP (writes)
  logic [AXI_MAX_DW-1:0]  rdata[];           // RDATA per beat, zero-extended (reads)
  logic [1:0]             rresp[];           // RRESP per beat (reads)
  logic [AXI_MAX_IDW-1:0] resp_id;           // BID / RID as the Manager saw it
  int unsigned            beats_done;        // data beats transferred or recorded
  axi_bfm_status_e        status;            // Manager/Subordinate result; monitor: OK/ERROR
  int unsigned            addr_wait;         // cycles AxVALID waited for AxREADY
  int unsigned            data_wait[];       // per beat: cycles VALID waited for READY
  int unsigned            resp_wait;         // writes: cycles BVALID waited for BREADY
  longint unsigned        addr_cycle;        // monitor/Subordinate: address handshake sample
  longint unsigned        first_data_cycle;  // monitor: first data handshake sample
  longint unsigned        last_data_cycle;   // monitor: last data handshake sample
  longint unsigned        resp_cycle;        // monitor: B or last R handshake sample
  int unsigned            req_epoch;         // Subordinate requests: BFM reset epoch (RST-8)
  string                  instance_name;

  // ---- Constraints ----------------------------------------------------------------
  // Beat count per burst type (AXI-R08); bursts are short by default.
  constraint c_len {
    (burst == AXI_BURST_FIXED) -> len inside {[1:16]};
    (burst == AXI_BURST_INCR)  -> len inside {[1:AXI_MAX_BEATS]};
    (burst == AXI_BURST_WRAP)  -> len inside {2, 4, 8, 16};
    if (burst == AXI_BURST_INCR)  soft len inside {[1:8]};
    if (burst == AXI_BURST_FIXED) soft len inside {[1:4]};
  }

  // Never the reserved AxBURST encoding (AXI-R10)
  constraint c_burst {
    burst != AXI_BURST_RSVD;
  }

  // One array entry per beat
  constraint c_arrays {
    wdata.size()      == len;
    data_delay.size() == len;
  }

  // Values must fit the bound bus (lossless rule, DATA-02)
  constraint c_fit_bus {
    (addr & addr_over_mask) == 0;
    (dir == AXI_WRITE) -> ((id & idw_over_mask) == 0);
    (dir == AXI_READ)  -> ((id & idr_over_mask) == 0);
    foreach (wdata[i]) (wdata[i] & data_over_mask) == 0;
  }

  // AxSIZE no wider than the bus (AXI-R09)
  constraint c_size {
    size <= bus_max_size;
  }

  // A WRAP burst starts at an address aligned to its beat size (AXI-R11)
  constraint c_wrap_aligned {
    (burst == AXI_BURST_WRAP) -> ((addr & ((64'd1 << size) - 64'd1)) == 0);
  }

  // Aligned start by default; a sequence switches this off for unaligned
  // INCR/FIXED bursts (IHI 0022 "Unaligned transfers").
  constraint c_aligned {
    (addr & ((64'd1 << size) - 64'd1)) == 0;
  }

  // An INCR burst stays inside one 4KB page (AXI-R12); WRAP and FIXED cannot cross.
  constraint c_4kb {
    (burst == AXI_BURST_INCR) ->
      (((addr & 64'hFFF) & ~((64'd1 << size) - 64'd1)) + (64'(len) << size) <= 64'd4096);
  }

  // Reads carry no write data
  constraint c_read_data {
    foreach (wdata[i]) (dir == AXI_READ) -> wdata[i] == 0;
  }

  // AXI4-Lite: one full-width beat; no ID, LOCK, CACHE, QOS or REGION (AXI-R24)
  constraint c_lite {
    bus_lite -> (len == 1 && size == bus_max_size && burst == AXI_BURST_INCR && id == 0 &&
                 lock == 1'b0 && cache == 4'h0 && qos == 4'h0 && region == 4'h0);
  }

  // Exclusive access restrictions (AXI-R18): a power of two of bytes up to 128,
  // at most 16 beats, address aligned to the total.
  constraint c_exclusive {
    (lock == 1'b1) -> ((64'(len) << size) inside {1, 2, 4, 8, 16, 32, 64, 128} &&
                       len <= 16 && (addr & ((64'(len) << size) - 64'd1)) == 0);
  }

  // Non-modifiable accesses have AxCACHE[3:2] LOW (AXI-R19)
  constraint c_cache {
    (cache[1] == 1'b0) -> (cache[3:2] == 2'b00);
  }

  // Defaults: normal (non-exclusive) Device Non-bufferable access, unprivileged
  // secure data, QoS and region 0. A sequence switches this off to randomize them.
  constraint c_attr_default {
    soft lock   == 1'b0;
    soft cache  == 4'h0;
    soft prot   == 3'b000;
    soft qos    == 4'h0;
    soft region == 4'h0;
  }

  // Small IDs by default, so same-ID ordering is exercised
  constraint c_id_default {
    soft id inside {[0:3]};
  }

  // Delays within the knobs
  constraint c_delays {
    addr_delay       <= max_addr_delay;
    resp_ready_delay <= max_ready_delay;
    resp_delay       <= max_resp_delay;
    foreach (data_delay[i]) data_delay[i] <= max_data_delay;
  }

  // status starts OK; the response fields are filled later.
  function new(string name = "axi_transaction");
    super.new(name);
    status = AXI_ST_OK;
    bresp  = 2'b00;
  endfunction

  // Strobes follow the randomized shape: every active lane of each write beat
  // (or a random subset with random_wstrb), none for a read.
  function void post_randomize();
    super.post_randomize();
    fill_strobes(random_wstrb);
  endfunction

  // Copy the bound instance's widths and protocol mode (call before randomize).
  // The masks are built bit by bit, so no shift by the full operand width (LANG-05).
  function void set_bus_context(int unsigned addr_width, int unsigned data_width,
                                int unsigned id_w_width, int unsigned id_r_width, bit lite);
    bus_addr_width = addr_width;
    bus_data_width = data_width;
    bus_id_w_width = id_w_width;
    bus_id_r_width = id_r_width;
    bus_lite       = lite;
    addr_over_mask = '0;
    data_over_mask = '0;
    strb_over_mask = '0;
    idw_over_mask  = '0;
    idr_over_mask  = '0;
    for (int unsigned i = addr_width; i < AXI_MAX_AW; i++)     addr_over_mask[i] = 1'b1;
    for (int unsigned i = data_width; i < AXI_MAX_DW; i++)     data_over_mask[i] = 1'b1;
    for (int unsigned i = data_width / 8; i < AXI_MAX_SW; i++) strb_over_mask[i] = 1'b1;
    for (int unsigned i = id_w_width; i < AXI_MAX_IDW; i++)    idw_over_mask[i]  = 1'b1;
    for (int unsigned i = id_r_width; i < AXI_MAX_IDW; i++)    idr_over_mask[i]  = 1'b1;
    bus_max_size = 0;
    while ((32'd1 << (bus_max_size + 1)) <= data_width / 8) bus_max_size++;
  endfunction

  // Bytes moved by one beat
  function int unsigned beat_bytes();
    return axi_size_bytes(size);
  endfunction

  // Address of beat i (IHI 0022 "Burst address", AXI-R13)
  function logic [AXI_MAX_AW-1:0] beat_addr(int unsigned i);
    return AXI_MAX_AW'(axi_beat_addr(AXI_FN_AW'(addr), size, burst, len, i));
  endfunction

  // Active byte lanes of beat i on the bound bus (AXI-R13/R14): narrow and
  // unaligned beats use only part of the bus.
  function logic [AXI_MAX_SW-1:0] lanes_of(int unsigned i);
    logic [AXI_MAX_LANES-1:0] lanes;
    lanes = axi_lane_mask(axi_beat_addr(AXI_FN_AW'(addr), size, burst, len, i), size,
                          bus_data_width / 8);
    return lanes[AXI_MAX_SW-1:0];
  endfunction

  // Size wstrb to len: the active lanes of each write beat (a random subset of
  // them with rand_subset), zero for a read. Sequences call it again after
  // placing a directed address or size.
  function void fill_strobes(bit rand_subset = 1'b0);
    logic [AXI_MAX_SW-1:0] lanes;
    wstrb = new[len];
    for (int unsigned i = 0; i < len; i++) begin
      lanes = lanes_of(i);
      if (dir == AXI_READ)  wstrb[i] = '0;
      else if (rand_subset) wstrb[i] = lanes & AXI_MAX_SW'({$urandom, $urandom, $urandom,
                                                            $urandom});
      else                  wstrb[i] = lanes;
    end
  endfunction

  // 1 when any response of the transaction is SLVERR or DECERR (AXI-R16)
  function bit has_error_response();
    if (dir == AXI_WRITE) return axi_resp_is_error(bresp);
    foreach (rresp[i]) if (axi_resp_is_error(rresp[i])) return 1'b1;
    return 1'b0;
  endfunction

  // Deep copy of every field, including bus context and observation stamps (UVM-03).
  virtual function void do_copy(uvm_object rhs);
    axi_transaction rhs_;
    super.do_copy(rhs);
    if (!$cast(rhs_, rhs)) begin
      `uvm_fatal("AXI_TXN", "do_copy: argument is not an axi_transaction")
      return;
    end
    dir              = rhs_.dir;
    id               = rhs_.id;
    addr             = rhs_.addr;
    burst            = rhs_.burst;
    size             = rhs_.size;
    len              = rhs_.len;
    lock             = rhs_.lock;
    cache            = rhs_.cache;
    prot             = rhs_.prot;
    qos              = rhs_.qos;
    region           = rhs_.region;
    wdata            = rhs_.wdata;
    wstrb            = rhs_.wstrb;
    addr_delay       = rhs_.addr_delay;
    data_delay       = rhs_.data_delay;
    resp_ready_delay = rhs_.resp_ready_delay;
    resp_delay       = rhs_.resp_delay;
    max_addr_delay   = rhs_.max_addr_delay;
    max_data_delay   = rhs_.max_data_delay;
    max_ready_delay  = rhs_.max_ready_delay;
    max_resp_delay   = rhs_.max_resp_delay;
    random_wstrb     = rhs_.random_wstrb;
    bus_addr_width   = rhs_.bus_addr_width;
    bus_data_width   = rhs_.bus_data_width;
    bus_id_w_width   = rhs_.bus_id_w_width;
    bus_id_r_width   = rhs_.bus_id_r_width;
    bus_max_size     = rhs_.bus_max_size;
    bus_lite         = rhs_.bus_lite;
    addr_over_mask   = rhs_.addr_over_mask;
    data_over_mask   = rhs_.data_over_mask;
    strb_over_mask   = rhs_.strb_over_mask;
    idw_over_mask    = rhs_.idw_over_mask;
    idr_over_mask    = rhs_.idr_over_mask;
    bresp            = rhs_.bresp;
    rdata            = rhs_.rdata;
    rresp            = rhs_.rresp;
    resp_id          = rhs_.resp_id;
    beats_done       = rhs_.beats_done;
    status           = rhs_.status;
    addr_wait        = rhs_.addr_wait;
    data_wait        = rhs_.data_wait;
    resp_wait        = rhs_.resp_wait;
    addr_cycle       = rhs_.addr_cycle;
    first_data_cycle = rhs_.first_data_cycle;
    last_data_cycle  = rhs_.last_data_cycle;
    resp_cycle       = rhs_.resp_cycle;
    req_epoch        = rhs_.req_epoch;
    instance_name    = rhs_.instance_name;
  endfunction

  // Compares the bus-visible content with 4-state equality: address and control,
  // then per completed beat the data of the direction (writes with strobes) and
  // the responses.
  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    axi_transaction rhs_;
    if (!$cast(rhs_, rhs)) return 1'b0;
    if (!super.do_compare(rhs, comparer)) return 1'b0;
    if (dir != rhs_.dir || id !== rhs_.id || addr !== rhs_.addr || burst != rhs_.burst ||
        size != rhs_.size || len != rhs_.len || lock !== rhs_.lock || cache !== rhs_.cache ||
        prot !== rhs_.prot || qos !== rhs_.qos || region !== rhs_.region ||
        beats_done != rhs_.beats_done)
      return 1'b0;
    if (dir == AXI_WRITE) begin
      if (bresp !== rhs_.bresp) return 1'b0;
      for (int unsigned i = 0; i < beats_done; i++) begin
        if (i >= wdata.size() || i >= rhs_.wdata.size() || i >= wstrb.size() ||
            i >= rhs_.wstrb.size())
          return 1'b0;
        if (wdata[i] !== rhs_.wdata[i] || wstrb[i] !== rhs_.wstrb[i]) return 1'b0;
      end
    end else begin
      for (int unsigned i = 0; i < beats_done; i++) begin
        if (i >= rdata.size() || i >= rhs_.rdata.size() || i >= rresp.size() ||
            i >= rhs_.rresp.size())
          return 1'b0;
        if (rdata[i] !== rhs_.rdata[i] || rresp[i] !== rhs_.rresp[i]) return 1'b0;
      end
    end
    return 1'b1;
  endfunction

  // One line for logs: control, then up to eight beats of data (wdata/wstrb for
  // writes, rdata with its response letter for reads), then the outcome.
  virtual function string convert2string();
    string s;
    s = $sformatf("%s %s id=%0h %s size=%0dB addr=%0h len=%0d lock=%b cache=%b prot=%b",
                  instance_name, dir == AXI_WRITE ? "WR" : "RD", id, burst.name(),
                  beat_bytes(), addr, len, lock, cache, prot);
    for (int unsigned i = 0; i < beats_done && i < 8; i++) begin
      if (dir == AXI_WRITE && i < wdata.size() && i < wstrb.size())
        s = {s, $sformatf(" [%0d]%0h/%0h", i, wdata[i], wstrb[i])};
      if (dir == AXI_READ && i < rdata.size() && i < rresp.size())
        s = {s, $sformatf(" [%0d]%0h%s", i, rdata[i], resp_letter(rresp[i]))};
    end
    if (beats_done > 8) s = {s, " ..."};
    if (dir == AXI_WRITE) s = {s, " bresp=", resp_name(bresp)};
    return {s, $sformatf(" -> %s done=%0d", status.name(), beats_done)};
  endfunction

  // Name of a response; X/Z is shown as such, never cast to a 2-state value
  protected function string resp_name(logic [1:0] r);
    if ($isunknown(r)) return "X/Z";
    case (r)
      AXI_RESP_OKAY:   return "OKAY";
      AXI_RESP_EXOKAY: return "EXOKAY";
      AXI_RESP_SLVERR: return "SLVERR";
      default:         return "DECERR";
    endcase
  endfunction

  // Short tag after a read beat: "" OKAY, "X" EXOKAY, "S" SLVERR, "D" DECERR, "?" X/Z
  protected function string resp_letter(logic [1:0] r);
    if ($isunknown(r)) return "?";
    case (r)
      AXI_RESP_OKAY:   return "";
      AXI_RESP_EXOKAY: return "X";
      AXI_RESP_SLVERR: return "S";
      default:         return "D";
    endcase
  endfunction

endclass : axi_transaction
