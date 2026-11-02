// -----------------------------------------------------------------------------
// axi_monitor_bfm_if — passive AXI observation BFM
//
// Owns passive sampling and transaction reconstruction (ADR-002 decision 3).
// Every port is an input: this BFM can never drive the bus. It connects to the
// same axi_if instance as the Manager and Subordinate BFMs through ordinary
// signal ports.
//
// Reconstruction (AXI_PROTOCOL_CONTRACT section 7) handles any legal AXI4
// traffic, not only what this UVC generates: several open transactions per
// direction, responses out of order across IDs, read data interleaved across
// IDs, and write data before its address (AXI-R06, AXI-R20). Write data bursts
// are paired with write addresses in order (AXI4 has no WID). A transaction is
// published once, when it ends: a write at its B handshake, a read at the
// handshake of its last data beat (counted from ARLEN; RLAST is checked, not
// used for framing).
//
// Transport (RISK-002 — proposal until validated on the target simulator):
//   * an always-running process samples through a clocking block (input
//     #1step), independent of HVL timing;
//   * transactions and reset events (RST-4) go into bounded queues of plain
//     values (no UVM objects in HDL, ADR-002 section 6); the HVL observe
//     adapter calls the blocking tasks get_txn() and get_reset_event().
//
// Protocol violations are counted per axi_mon_error_e code and optionally
// printed; the HVL side turns the counts into UVM reports. User signals are
// accepted as ports but not checked until milestone M2.
// Compile after axi_bfm_pkg.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

interface axi_monitor_bfm_if
  import axi_bfm_pkg::*;
#(
  parameter int ADDR_WIDTH      = 32,
  parameter int DATA_WIDTH      = 32,
  parameter int ID_W_WIDTH      = 4,
  parameter int ID_R_WIDTH      = 4,
  parameter int USER_REQ_WIDTH  = 1,
  parameter int USER_DATA_WIDTH = 1,
  parameter int USER_RESP_WIDTH = 1,
  parameter int QUEUE_DEPTH     = 16,  // completed transactions waiting for the HVL side
  parameter int MAX_OUTSTANDING = 16   // open transactions tracked per direction
) (
  input  wire logic                           ACLK,
  input  wire logic                           ARESETn,
  // Write address channel
  input  wire logic [ID_W_WIDTH-1:0]          AWID,
  input  wire logic [ADDR_WIDTH-1:0]          AWADDR,
  input  wire logic [7:0]                     AWLEN,
  input  wire logic [2:0]                     AWSIZE,
  input  wire logic [1:0]                     AWBURST,
  input  wire logic                           AWLOCK,
  input  wire logic [3:0]                     AWCACHE,
  input  wire logic [2:0]                     AWPROT,
  input  wire logic [3:0]                     AWQOS,
  input  wire logic [3:0]                     AWREGION,
  input  wire logic [USER_REQ_WIDTH-1:0]      AWUSER,
  input  wire logic                           AWVALID,
  input  wire logic                           AWREADY,
  // Write data channel
  input  wire logic [DATA_WIDTH-1:0]          WDATA,
  input  wire logic [DATA_WIDTH/8-1:0]        WSTRB,
  input  wire logic                           WLAST,
  input  wire logic [USER_DATA_WIDTH-1:0]     WUSER,
  input  wire logic                           WVALID,
  input  wire logic                           WREADY,
  // Write response channel
  input  wire logic [ID_W_WIDTH-1:0]          BID,
  input  wire logic [1:0]                     BRESP,
  input  wire logic [USER_RESP_WIDTH-1:0]     BUSER,
  input  wire logic                           BVALID,
  input  wire logic                           BREADY,
  // Read address channel
  input  wire logic [ID_R_WIDTH-1:0]          ARID,
  input  wire logic [ADDR_WIDTH-1:0]          ARADDR,
  input  wire logic [7:0]                     ARLEN,
  input  wire logic [2:0]                     ARSIZE,
  input  wire logic [1:0]                     ARBURST,
  input  wire logic                           ARLOCK,
  input  wire logic [3:0]                     ARCACHE,
  input  wire logic [2:0]                     ARPROT,
  input  wire logic [3:0]                     ARQOS,
  input  wire logic [3:0]                     ARREGION,
  input  wire logic [USER_REQ_WIDTH-1:0]      ARUSER,
  input  wire logic                           ARVALID,
  input  wire logic                           ARREADY,
  // Read data channel
  input  wire logic [ID_R_WIDTH-1:0]          RID,
  input  wire logic [DATA_WIDTH-1:0]          RDATA,
  input  wire logic [1:0]                     RRESP,
  input  wire logic                           RLAST,
  input  wire logic [USER_DATA_WIDTH-1:0]     RUSER,
  input  wire logic                           RVALID,
  input  wire logic                           RREADY
);

  localparam int         STRB_WIDTH   = DATA_WIDTH / 8;
  localparam int         ID_MAX_WIDTH = (ID_W_WIDTH > ID_R_WIDTH) ? ID_W_WIDTH : ID_R_WIDTH;
  localparam logic [2:0] FULL_SIZE    = 3'($clog2(STRB_WIDTH));  // AxSIZE of a full beat

  // Payload of one channel as sampled, compared whole for the stability rule
  // (AXI-R04). Signals absent on AXI4-Lite are sampled as constants (AXI-R24).
  typedef struct packed {
    logic [ID_MAX_WIDTH-1:0] id;
    logic [ADDR_WIDTH-1:0]   addr;
    logic [7:0]              len;    // AxLEN = beats - 1
    logic [2:0]              size;
    logic [1:0]              burst;
    logic                    lock;
    logic [3:0]              cache;
    logic [2:0]              prot;
    logic [3:0]              qos;
    logic [3:0]              region;
  } axi_addr_pl_t;

  typedef struct packed {
    logic [DATA_WIDTH-1:0] data;
    logic [STRB_WIDTH-1:0] strb;
    logic                  last;
  } axi_w_pl_t;

  typedef struct packed {
    logic [ID_W_WIDTH-1:0] id;
    logic [1:0]            resp;
  } axi_b_pl_t;

  typedef struct packed {
    logic [ID_R_WIDTH-1:0] id;
    logic [DATA_WIDTH-1:0] data;
    logic [1:0]            resp;
    logic                  last;
  } axi_r_pl_t;

  // One accepted address transfer with its timing
  typedef struct packed {
    axi_addr_pl_t    pl;
    bit              shape_known;  // payload had no X/Z: the burst checks apply
    int unsigned     wait_cycles;  // cycles the VALID waited for READY
    longint unsigned cycle;        // sample of the handshake
  } axi_ax_t;

  // One data burst: write data with strobes, or read data with responses
  typedef struct {
    int unsigned           beats;
    logic [DATA_WIDTH-1:0] data  [AXI_MAX_BEATS];
    logic [STRB_WIDTH-1:0] strb  [AXI_MAX_BEATS];
    logic [1:0]            resp  [AXI_MAX_BEATS];
    int unsigned           waits [AXI_MAX_BEATS];  // cycles each beat's VALID waited
    longint unsigned       first_cycle;
    longint unsigned       last_cycle;
  } axi_data_t;

  // One open or completed transaction
  typedef struct {
    bit              write;
    axi_ax_t         ax;
    axi_data_t       d;
    logic [1:0]      bresp;
    int unsigned     resp_wait;    // writes: cycles BVALID waited for BREADY
    longint unsigned resp_cycle;   // B handshake, or the last R handshake
  } axi_txn_t;

  // One reset edge reported to the HVL side (RST-4)
  typedef struct packed {
    bit              asserted;
    longint unsigned cycle;
  } axi_rst_t;

  axi_features_t   features           = axi_default_features();
  bit              publish_en         = 1'b0;  // queue only when a consumer exists
  bit              verbose            = 1'b1;  // print each violation
  axi_txn_t        obs_q[$];
  event            obs_ev;                     // triggered on every publish
  axi_rst_t        rst_q[$];
  event            rst_ev;                     // triggered on every reset event
  int unsigned     error_count[AXI_MON_NUM_ERRORS];
  int unsigned     transfer_count     = 0;     // transactions completed
  int unsigned     write_count        = 0;
  int unsigned     read_count         = 0;
  int unsigned     reset_count        = 0;     // resets after the first release
  int unsigned     aborted_count      = 0;     // open transactions dropped by reset
  bit              in_reset           = 1'b1;
  bit              seen_reset_release = 1'b0;
  longint unsigned cycle              = 0;

  // Reconstruction state
  axi_ax_t         aw_q[$];                    // write addresses waiting for their data
  axi_data_t       wb_q[$];                    // write data bursts waiting for an address
  axi_data_t       wcur;                       // write data burst being received
  bit              wcur_open          = 1'b0;
  bit              wcur_over          = 1'b0;  // beats beyond AXI_MAX_BEATS reported
  axi_txn_t        wr_q[$];                    // writes with address and data, before B
  axi_txn_t        rd_q[$];                    // reads collecting their data beats

  // Previous sample per channel (AXI-R03/R04) and the current transfer's wait count
  bit              aw_pend            = 1'b0;  // VALID HIGH without handshake last edge
  bit              w_pend             = 1'b0;
  bit              b_pend             = 1'b0;
  bit              ar_pend            = 1'b0;
  bit              r_pend             = 1'b0;
  axi_addr_pl_t    aw_prev            = '0;
  axi_w_pl_t       w_prev             = '0;
  axi_b_pl_t       b_prev             = '0;
  axi_addr_pl_t    ar_prev            = '0;
  axi_r_pl_t       r_prev             = '0;
  int unsigned     aw_wait            = 0;
  int unsigned     w_wait             = 0;
  int unsigned     b_wait             = 0;
  int unsigned     ar_wait            = 0;
  int unsigned     r_wait             = 0;
  bit              b_flagged          = 1'b0;  // current B transfer reported unexpected
  bit              r_flagged          = 1'b0;  // current R transfer reported unexpected

  // Every input is sampled 1step before the ACLK rising edge: the values that were
  // stable during the cycle, race-free against any driver (HDL-05).
  clocking cb @(posedge ACLK);
    default input #1step;
    input ARESETn,
          AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION,
          AWVALID, AWREADY, WDATA, WSTRB, WLAST, WVALID, WREADY, BID, BRESP, BVALID, BREADY,
          ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION,
          ARVALID, ARREADY, RID, RDATA, RRESP, RLAST, RVALID, RREADY;
  endclocking

  // ---------------------------------------------------------------------------
  // Control / observation API (called by the HVL observe adapter)
  // ---------------------------------------------------------------------------

  // Accept the instance feature set unless it is illegal for its protocol mode
  // (CFG-01). Milestone M2 features are accepted: their pins exist but are not
  // checked yet.
  function automatic bit configure(axi_features_t f);
    string problem = axi_protocol_problem(f, DATA_WIDTH);
    if (problem != "") begin
      $error("%m: feature set rejected: %s", problem);
      return 1'b0;
    end
    features = f;
    return 1'b1;
  endfunction

  // Queue transactions and reset events only once a consumer exists, so an unused
  // monitor cannot overflow. The counters count either way.
  function automatic void set_publish(bit en);
    publish_en = en;
  endfunction

  // Print each violation when it happens; the counters are kept either way.
  function automatic void set_verbose(bit en);
    verbose = en;
  endfunction

  // Violation counters per axi_mon_error_e; axi_monitor reports them in check_phase.
  function automatic int unsigned get_error_count(axi_mon_error_e code);
    return error_count[code];
  endfunction

  function automatic int unsigned get_total_errors();
    int unsigned total = 0;
    foreach (error_count[i]) total += error_count[i];
    return total;
  endfunction

  function automatic void clear_errors();
    foreach (error_count[i]) error_count[i] = 0;
  endfunction

  // Transactions started but not completed (address without its end, or write
  // data without an address); axi_monitor checks it at the end of a test.
  function automatic int unsigned get_open_count();
    return aw_q.size() + wb_q.size() + (wcur_open ? 1 : 0) + wr_q.size() + rd_q.size();
  endfunction

  // Blocks until a completed transaction is available, then removes it. The
  // queue is checked before waiting, so a publish earlier in the same time step
  // is never missed. id is zero-extended to the wider ID width; len is AxLEN+1;
  // beats is the data beats recorded. data/strb hold the write data of a write,
  // data the read data of a read; resp holds RRESP per beat of a read, or BRESP
  // in resp[0] of a write. Entries at index >= beats are zero.
  task automatic get_txn(
    output bit                      write,
    output logic [ID_MAX_WIDTH-1:0] id,
    output logic [ADDR_WIDTH-1:0]   addr,
    output int unsigned             len,
    output logic [2:0]              size,
    output logic [1:0]              burst,
    output logic                    lock,
    output logic [3:0]              cache,
    output logic [2:0]              prot,
    output logic [3:0]              qos,
    output logic [3:0]              region,
    output int unsigned             beats,
    output logic [DATA_WIDTH-1:0]   data      [AXI_MAX_BEATS],
    output logic [STRB_WIDTH-1:0]   strb      [AXI_MAX_BEATS],
    output logic [1:0]              resp      [AXI_MAX_BEATS],
    output int unsigned             addr_wait,
    output int unsigned             data_wait [AXI_MAX_BEATS],
    output int unsigned             resp_wait,
    output longint unsigned         addr_cycle,
    output longint unsigned         first_data_cycle,
    output longint unsigned         last_data_cycle,
    output longint unsigned         resp_cycle
  );
    axi_txn_t t;
    while (obs_q.size() == 0) @(obs_ev);
    t                = obs_q.pop_front();
    write            = t.write;
    id               = t.ax.pl.id;
    addr             = t.ax.pl.addr;
    len              = int'(t.ax.pl.len) + 1;
    size             = t.ax.pl.size;
    burst            = t.ax.pl.burst;
    lock             = t.ax.pl.lock;
    cache            = t.ax.pl.cache;
    prot             = t.ax.pl.prot;
    qos              = t.ax.pl.qos;
    region           = t.ax.pl.region;
    beats            = t.d.beats;
    data             = t.d.data;
    strb             = t.d.strb;
    resp             = t.d.resp;
    if (t.write) resp[0] = t.bresp;
    addr_wait        = t.ax.wait_cycles;
    data_wait        = t.d.waits;
    resp_wait        = t.resp_wait;
    addr_cycle       = t.ax.cycle;
    first_data_cycle = t.d.first_cycle;
    last_data_cycle  = t.d.last_cycle;
    resp_cycle       = t.resp_cycle;
  endtask

  // Blocks until the next reset edge after the first release (RST-4):
  // asserted = 1 when reset asserted, 0 when it was released again.
  task automatic get_reset_event(output bit asserted, output longint unsigned at_cycle);
    axi_rst_t r;
    while (rst_q.size() == 0) @(rst_ev);
    r        = rst_q.pop_front();
    asserted = r.asserted;
    at_cycle = r.cycle;
  endtask

  // ---------------------------------------------------------------------------
  // Sampling process
  // ---------------------------------------------------------------------------

  // Free-running sampler: one sample_cycle() per ACLK edge, independent of the
  // HVL side (AXI_PROTOCOL_CONTRACT section 7).
  initial forever begin
    @(cb);
    cycle++;
    sample_cycle();
  end

  // Count one violation; when verbose, print it with time, instance and cycle.
  task automatic flag(axi_mon_error_e code, string msg);
    error_count[code]++;
    if (verbose)
      $display("%0t AXI_MON_ERROR %m [%s] cycle=%0d: %s", $realtime, code.name(), cycle, msg);
  endtask

  // Count a completed transaction. When publishing, queue it (bounded: an
  // overflow is itself reported) and wake a get_txn() caller.
  task automatic complete(axi_txn_t t);
    transfer_count++;
    if (t.write) write_count++;
    else         read_count++;
    if (!publish_en) return;
    if (obs_q.size() >= QUEUE_DEPTH) begin
      flag(AXI_MON_ERR_QUEUE_OVERFLOW, "observation queue full; transaction dropped");
      return;
    end
    obs_q.push_back(t);
    -> obs_ev;
  endtask

  // Queue one reset edge for get_reset_event() (RST-4), bounded like complete().
  task automatic publish_reset(bit asserted);
    axi_rst_t r;
    if (!publish_en) return;
    if (rst_q.size() >= QUEUE_DEPTH) begin
      flag(AXI_MON_ERR_QUEUE_OVERFLOW, "reset event queue full; event dropped");
      return;
    end
    r.asserted = asserted;
    r.cycle    = cycle;
    rst_q.push_back(r);
    -> rst_ev;
  endtask

  // Forget every open transaction and channel history (reset): nothing of them
  // is ever published (RST-4).
  task automatic resync();
    aw_q.delete();
    wb_q.delete();
    wr_q.delete();
    rd_q.delete();
    wcur_open = 1'b0;
    wcur_over = 1'b0;
    aw_pend   = 1'b0;
    w_pend    = 1'b0;
    b_pend    = 1'b0;
    ar_pend   = 1'b0;
    r_pend    = 1'b0;
    b_flagged = 1'b0;
    r_flagged = 1'b0;
  endtask

  // A data burst with no beats and every field zero
  function automatic axi_data_t empty_data();
    axi_data_t d;
    d.beats       = 0;
    d.first_cycle = 0;
    d.last_cycle  = 0;
    for (int unsigned i = 0; i < AXI_MAX_BEATS; i++) begin
      d.data[i]  = '0;
      d.strb[i]  = '0;
      d.resp[i]  = 2'b00;
      d.waits[i] = 0;
    end
    return d;
  endfunction

  // Channel payloads as sampled this cycle. AXI4-Lite has no ID, LEN, SIZE,
  // BURST, LOCK, CACHE, QOS, REGION or LAST: they read as one full-width INCR
  // beat with ID 0 and LAST set (AXI-R24).
  function automatic axi_addr_pl_t sample_aw(bit lite);
    axi_addr_pl_t p;
    p.addr   = cb.AWADDR;
    p.prot   = cb.AWPROT;
    p.id     = lite ? '0 : ID_MAX_WIDTH'(cb.AWID);
    p.len    = lite ? 8'h00 : cb.AWLEN;
    p.size   = lite ? FULL_SIZE : cb.AWSIZE;
    p.burst  = lite ? AXI_BURST_INCR : cb.AWBURST;
    p.lock   = lite ? 1'b0 : cb.AWLOCK;
    p.cache  = lite ? 4'h0 : cb.AWCACHE;
    p.qos    = lite ? 4'h0 : cb.AWQOS;
    p.region = lite ? 4'h0 : cb.AWREGION;
    return p;
  endfunction

  function automatic axi_addr_pl_t sample_ar(bit lite);
    axi_addr_pl_t p;
    p.addr   = cb.ARADDR;
    p.prot   = cb.ARPROT;
    p.id     = lite ? '0 : ID_MAX_WIDTH'(cb.ARID);
    p.len    = lite ? 8'h00 : cb.ARLEN;
    p.size   = lite ? FULL_SIZE : cb.ARSIZE;
    p.burst  = lite ? AXI_BURST_INCR : cb.ARBURST;
    p.lock   = lite ? 1'b0 : cb.ARLOCK;
    p.cache  = lite ? 4'h0 : cb.ARCACHE;
    p.qos    = lite ? 4'h0 : cb.ARQOS;
    p.region = lite ? 4'h0 : cb.ARREGION;
    return p;
  endfunction

  function automatic axi_w_pl_t sample_w(bit lite);
    axi_w_pl_t p;
    p.data = cb.WDATA;
    p.strb = cb.WSTRB;
    p.last = lite ? 1'b1 : cb.WLAST;
    return p;
  endfunction

  function automatic axi_b_pl_t sample_b(bit lite);
    axi_b_pl_t p;
    p.id   = lite ? '0 : cb.BID;
    p.resp = cb.BRESP;
    return p;
  endfunction

  function automatic axi_r_pl_t sample_r(bit lite);
    axi_r_pl_t p;
    p.id   = lite ? '0 : cb.RID;
    p.data = cb.RDATA;
    p.resp = cb.RRESP;
    p.last = lite ? 1'b1 : cb.RLAST;
    return p;
  endfunction

  // 1 when a strobed byte lane of the write data is X/Z (AXI-R23); lanes without
  // a strobe carry no data and may hold anything.
  function automatic bit wdata_unknown(axi_w_pl_t p);
    for (int unsigned l = 0; l < STRB_WIDTH; l++)
      if (p.strb[l] === 1'b1 && $isunknown(p.data[8*l +: 8])) return 1'b1;
    return 1'b0;
  endfunction

  // 1 when a waited write data transfer changed (AXI-R04): strobes, WLAST, or the
  // data of a strobed lane.
  function automatic bit w_changed(axi_w_pl_t now, axi_w_pl_t prev);
    if (now.strb !== prev.strb || now.last !== prev.last) return 1'b1;
    for (int unsigned l = 0; l < STRB_WIDTH; l++)
      if (prev.strb[l] === 1'b1 && now.data[8*l +: 8] !== prev.data[8*l +: 8]) return 1'b1;
    return 1'b0;
  endfunction

  // First write waiting for its response with this ID (oldest first, AXI-R20)
  function automatic int find_write(logic [ID_W_WIDTH-1:0] id);
    foreach (wr_q[i])
      if (wr_q[i].ax.pl.id === ID_MAX_WIDTH'(id)) return i;
    return -1;
  endfunction

  // First read still collecting data with this ID (oldest first, AXI-R20)
  function automatic int find_read(logic [ID_R_WIDTH-1:0] id);
    foreach (rd_q[i])
      if (rd_q[i].ax.pl.id === ID_MAX_WIDTH'(id)) return i;
    return -1;
  endfunction

  // Burst rules of an accepted address (AXI-R08..R12, R18, R19). AXI4-Lite
  // transfers are single full-width beats with none of these signals.
  task automatic check_address(axi_ax_t ax, string ch, bit lite);
    int unsigned len   = int'(ax.pl.len) + 1;
    string       issue;
    if (lite || !ax.shape_known) return;
    if (ax.pl.burst == AXI_BURST_RSVD) begin
      flag(AXI_MON_ERR_BURST_TYPE, $sformatf("%s burst type 2'b11 is reserved", ch));
      return;
    end
    if (!axi_burst_len_ok(ax.pl.burst, len))
      flag(AXI_MON_ERR_BURST_LEN, $sformatf("%s %0d beats illegal for burst type %0d",
                                            ch, len, ax.pl.burst));
    if (axi_size_bytes(ax.pl.size) > unsigned'(STRB_WIDTH)) begin
      flag(AXI_MON_ERR_SIZE_EXCEEDS_BUS, $sformatf("%s size %0d bytes on a %0d-byte bus", ch,
                                                   axi_size_bytes(ax.pl.size), STRB_WIDTH));
      return;
    end
    if (ax.pl.burst == AXI_BURST_WRAP &&
        (AXI_FN_AW'(ax.pl.addr) & AXI_FN_AW'(axi_size_bytes(ax.pl.size) - 1)) != 0)
      flag(AXI_MON_ERR_WRAP_UNALIGNED, $sformatf("%s WRAP at %0h not aligned to %0d bytes",
                                                 ch, ax.pl.addr, axi_size_bytes(ax.pl.size)));
    if (axi_crosses_4kb(AXI_FN_AW'(ax.pl.addr), ax.pl.size, ax.pl.burst, len))
      flag(AXI_MON_ERR_4KB_CROSS, $sformatf("%s INCR at %0h, %0d x %0d bytes crosses 4KB",
                                            ch, ax.pl.addr, len, axi_size_bytes(ax.pl.size)));
    if (ax.pl.lock === 1'b1) begin
      issue = axi_exclusive_problem(AXI_FN_AW'(ax.pl.addr), ax.pl.size, len);
      if (issue != "") flag(AXI_MON_ERR_EXCLUSIVE, {ch, " ", issue});
    end
    if (!axi_cache_ok(ax.pl.cache))
      flag(AXI_MON_ERR_CACHE, $sformatf("%s cache %b: AxCACHE[1] LOW needs AxCACHE[3:2] LOW",
                                        ch, ax.pl.cache));
  endtask

  // A write address meets its data burst (AXI4 order, AXI-R20): the beat count
  // must be AWLEN+1 with WLAST on the last beat (AXI-R15), and every strobe must
  // lie in its beat's byte lanes (AXI-R14). The write then waits for B.
  task automatic pair_write(axi_ax_t ax, axi_data_t d, bit lite);
    axi_txn_t                 t;
    int unsigned              len = int'(ax.pl.len) + 1;
    logic [AXI_MAX_LANES-1:0] lanes;
    if (!lite && d.beats != len)
      flag(AXI_MON_ERR_WLAST, $sformatf("write at %0h: %0d data beats up to WLAST, AWLEN+1 = %0d",
                                        ax.pl.addr, d.beats, len));
    if (ax.shape_known && axi_size_bytes(ax.pl.size) <= unsigned'(STRB_WIDTH) &&
        axi_burst_len_ok(ax.pl.burst, len))
      for (int unsigned i = 0; i < d.beats && i < len; i++) begin
        lanes = axi_lane_mask(axi_beat_addr(AXI_FN_AW'(ax.pl.addr), ax.pl.size, ax.pl.burst,
                                            len, i), ax.pl.size, STRB_WIDTH);
        if ((d.strb[i] & ~lanes[STRB_WIDTH-1:0]) != '0)
          flag(AXI_MON_ERR_WSTRB, $sformatf("write at %0h beat %0d: WSTRB %b outside lanes %b",
                                            ax.pl.addr, i, d.strb[i], lanes[STRB_WIDTH-1:0]));
      end
    t.write      = 1'b1;
    t.ax         = ax;
    t.d          = d;
    t.bresp      = 2'b00;
    t.resp_wait  = 0;
    t.resp_cycle = 0;
    if (wr_q.size() >= MAX_OUTSTANDING) begin
      flag(AXI_MON_ERR_CAPACITY, "more writes waiting for a response than MAX_OUTSTANDING");
      return;
    end
    wr_q.push_back(t);
  endtask

  // EXOKAY is the answer to a successful exclusive access only (AXI-R17), and
  // AXI4-Lite has no exclusive access at all (AXI-R24).
  task automatic check_exokay(logic [1:0] resp, axi_ax_t ax, string what, bit lite);
    if (resp === AXI_RESP_EXOKAY && (lite || ax.pl.lock !== 1'b1))
      flag(AXI_MON_ERR_EXOKAY, $sformatf("%s at %0h: EXOKAY to a non-exclusive access",
                                         what, ax.pl.addr));
  endtask

  // Process one ACLK sample, in this order: reset (RST-4/6/7, AXI-R21), VALID/
  // READY validity (AXI-R23), the handshake rules against the previous sample
  // (AXI-R03/R04), the responses B and R (checked against what was complete
  // before this edge, AXI-R06/R07), the requests AW, W and AR, write pairing,
  // and the bookkeeping for the next sample. Consumes no time.
  task automatic sample_cycle();
    bit           lite;
    bit           aw_v, aw_r, w_v, w_r, b_v, b_r, ar_v, ar_r, r_v, r_r;
    axi_addr_pl_t aw_pl;
    axi_w_pl_t    w_pl;
    axi_b_pl_t    b_pl;
    axi_addr_pl_t ar_pl;
    axi_r_pl_t    r_pl;
    axi_ax_t      ax;
    axi_txn_t     t;
    int           idx;
    int unsigned  n;
    int unsigned  len;
    bit           last_expected;

    // Reset (RST-4, RST-6, RST-7): VALIDs must be LOW (AXI-R21); open
    // transactions are discarded, never published.
    if (cb.ARESETn !== 1'b1) begin
      if (cb.ARESETn !== 1'b0 && seen_reset_release) flag(AXI_MON_ERR_ARESETN_XZ, "ARESETn is X/Z");
      if (cb.AWVALID === 1'b1 || cb.WVALID === 1'b1 || cb.ARVALID === 1'b1 ||
          cb.BVALID === 1'b1 || cb.RVALID === 1'b1)
        flag(AXI_MON_ERR_VALID_IN_RESET, "a VALID is HIGH while ARESETn is LOW");
      if (!in_reset) begin
        reset_count++;
        aborted_count += aw_q.size() + wr_q.size() + rd_q.size();
        publish_reset(1'b1);
      end
      in_reset = 1'b1;
      resync();
      return;
    end
    if (in_reset) begin
      in_reset = 1'b0;
      if (seen_reset_release) publish_reset(1'b0);
      seen_reset_release = 1'b1;
      // A VALID may first rise at the edge after ARESETn is HIGH (AXI-R21), so
      // none can be HIGH in the cycle that ends at this first sample.
      if (cb.AWVALID === 1'b1 || cb.WVALID === 1'b1 || cb.ARVALID === 1'b1 ||
          cb.BVALID === 1'b1 || cb.RVALID === 1'b1)
        flag(AXI_MON_ERR_VALID_IN_RESET, "a VALID is HIGH at the first edge after reset");
    end

    lite  = (features.protocol == AXI4_LITE);
    aw_pl = sample_aw(lite);
    w_pl  = sample_w(lite);
    b_pl  = sample_b(lite);
    ar_pl = sample_ar(lite);
    r_pl  = sample_r(lite);

    // AXI-R23: VALID and READY are known outside reset (X/Z counts as LOW below)
    if ($isunknown({cb.AWVALID, cb.WVALID, cb.BVALID, cb.ARVALID, cb.RVALID}))
      flag(AXI_MON_ERR_VALID_XZ, "a VALID is X/Z");
    if ($isunknown({cb.AWREADY, cb.WREADY, cb.BREADY, cb.ARREADY, cb.RREADY}))
      flag(AXI_MON_ERR_READY_XZ, "a READY is X/Z");
    aw_v = (cb.AWVALID === 1'b1);
    aw_r = (cb.AWREADY === 1'b1);
    w_v  = (cb.WVALID === 1'b1);
    w_r  = (cb.WREADY === 1'b1);
    b_v  = (cb.BVALID === 1'b1);
    b_r  = (cb.BREADY === 1'b1);
    ar_v = (cb.ARVALID === 1'b1);
    ar_r = (cb.ARREADY === 1'b1);
    r_v  = (cb.RVALID === 1'b1);
    r_r  = (cb.RREADY === 1'b1);

    // AXI-R03/R04: a transfer that waited at the previous edge must still be
    // offered, unchanged.
    if (aw_pend) begin
      if (!aw_v)
        flag(AXI_MON_ERR_VALID_DROPPED, "AWVALID fell before AWREADY");
      else if (aw_pl !== aw_prev)
        flag(AXI_MON_ERR_UNSTABLE, "AW payload changed while AWVALID waited");
    end
    if (w_pend) begin
      if (!w_v)
        flag(AXI_MON_ERR_VALID_DROPPED, "WVALID fell before WREADY");
      else if (w_changed(w_pl, w_prev))
        flag(AXI_MON_ERR_UNSTABLE, "W payload changed while WVALID waited");
    end
    if (b_pend) begin
      if (!b_v)
        flag(AXI_MON_ERR_VALID_DROPPED, "BVALID fell before BREADY");
      else if (b_pl !== b_prev)
        flag(AXI_MON_ERR_UNSTABLE, "B payload changed while BVALID waited");
    end
    if (ar_pend) begin
      if (!ar_v)
        flag(AXI_MON_ERR_VALID_DROPPED, "ARVALID fell before ARREADY");
      else if (ar_pl !== ar_prev)
        flag(AXI_MON_ERR_UNSTABLE, "AR payload changed while ARVALID waited");
    end
    if (r_pend) begin
      if (!r_v)
        flag(AXI_MON_ERR_VALID_DROPPED, "RVALID fell before RREADY");
      else if (r_pl !== r_prev)
        flag(AXI_MON_ERR_UNSTABLE, "R payload changed while RVALID waited");
    end

    // A VALID that did not wait at the previous edge starts a new transfer:
    // check its payload once (AXI-R23) and restart its wait count.
    if (aw_v && !aw_pend) begin
      aw_wait = 0;
      if ($isunknown(aw_pl)) flag(AXI_MON_ERR_PAYLOAD_XZ, "AW payload X/Z with AWVALID HIGH");
    end
    if (w_v && !w_pend) begin
      w_wait = 0;
      if ($isunknown(w_pl.strb) || $isunknown(w_pl.last) || wdata_unknown(w_pl))
        flag(AXI_MON_ERR_PAYLOAD_XZ, "WSTRB/WLAST or strobed WDATA X/Z with WVALID HIGH");
    end
    if (b_v && !b_pend) begin
      b_wait    = 0;
      b_flagged = 1'b0;
      if ($isunknown(b_pl)) flag(AXI_MON_ERR_PAYLOAD_XZ, "BID/BRESP X/Z with BVALID HIGH");
      // AXI-R06: BVALID only after the write's address and last data transfer
      if (find_write(b_pl.id) < 0) begin
        flag(AXI_MON_ERR_B_UNEXPECTED,
             $sformatf("BVALID with BID %0h before a write of that ID completed", b_pl.id));
        b_flagged = 1'b1;
      end
    end
    if (ar_v && !ar_pend) begin
      ar_wait = 0;
      if ($isunknown(ar_pl)) flag(AXI_MON_ERR_PAYLOAD_XZ, "AR payload X/Z with ARVALID HIGH");
    end
    if (r_v && !r_pend) begin
      r_wait    = 0;
      r_flagged = 1'b0;
      if ($isunknown({r_pl.id, r_pl.resp, r_pl.last}))
        flag(AXI_MON_ERR_PAYLOAD_XZ, "RID/RRESP/RLAST X/Z with RVALID HIGH");
      // AXI-R07: RVALID only after the read's address transfer
      if (find_read(r_pl.id) < 0) begin
        flag(AXI_MON_ERR_R_UNEXPECTED,
             $sformatf("RVALID with RID %0h and no open read of that ID", r_pl.id));
        r_flagged = 1'b1;
      end
    end

    // Wait cycles of the current transfers (VALID HIGH, READY LOW)
    if (aw_v && !aw_r) aw_wait++;
    if (w_v  && !w_r)  w_wait++;
    if (b_v  && !b_r)  b_wait++;
    if (ar_v && !ar_r) ar_wait++;
    if (r_v  && !r_r)  r_wait++;

    // B handshake: completes the oldest write of that ID (AXI-R20)
    if (b_v && b_r) begin
      idx = find_write(b_pl.id);
      if (idx < 0) begin
        if (!b_flagged)
          flag(AXI_MON_ERR_B_UNEXPECTED, $sformatf("B handshake with BID %0h and no write",
                                                   b_pl.id));
      end else begin
        t = wr_q[idx];
        wr_q.delete(idx);
        t.bresp      = b_pl.resp;
        t.resp_wait  = b_wait;
        t.resp_cycle = cycle;
        check_exokay(b_pl.resp, t.ax, "write", lite);
        complete(t);
      end
    end

    // R handshake: one beat of the oldest open read of that ID (AXI-R20). The
    // read ends after ARLEN+1 beats; RLAST must mark exactly that beat (AXI-R15).
    if (r_v && r_r) begin
      idx = find_read(r_pl.id);
      if (idx < 0) begin
        if (!r_flagged)
          flag(AXI_MON_ERR_R_UNEXPECTED, $sformatf("R handshake with RID %0h and no open read",
                                                   r_pl.id));
      end else begin
        n             = rd_q[idx].d.beats;
        len           = int'(rd_q[idx].ax.pl.len) + 1;
        last_expected = (n == len - 1);
        if (!lite && ((r_pl.last === 1'b1) != last_expected))
          flag(AXI_MON_ERR_RLAST, $sformatf("read at %0h beat %0d of %0d: RLAST=%b",
                                            rd_q[idx].ax.pl.addr, n, len, r_pl.last));
        check_exokay(r_pl.resp, rd_q[idx].ax, "read", lite);
        if (n == 0) rd_q[idx].d.first_cycle = cycle;
        rd_q[idx].d.data[n]  = r_pl.data;  // 4-state, verbatim
        rd_q[idx].d.resp[n]  = r_pl.resp;
        rd_q[idx].d.waits[n] = r_wait;
        rd_q[idx].d.last_cycle = cycle;
        rd_q[idx].d.beats++;
        if (rd_q[idx].d.beats == len) begin
          t = rd_q[idx];
          rd_q.delete(idx);
          t.resp_cycle = cycle;
          complete(t);
        end
      end
    end

    // AW handshake: the address waits for its data (which may already be here)
    if (aw_v && aw_r) begin
      ax.pl          = aw_pl;
      ax.shape_known = !$isunknown(aw_pl);
      ax.wait_cycles = aw_wait;
      ax.cycle       = cycle;
      check_address(ax, "AW", lite);
      if (aw_q.size() + wr_q.size() >= MAX_OUTSTANDING)
        flag(AXI_MON_ERR_CAPACITY, "more open writes than MAX_OUTSTANDING; address dropped");
      else
        aw_q.push_back(ax);
    end

    // W handshake: collect beats up to WLAST (every beat on AXI4-Lite)
    if (w_v && w_r) begin
      if (!wcur_open) begin
        wcur             = empty_data();
        wcur.first_cycle = cycle;
        wcur_open        = 1'b1;
        wcur_over        = 1'b0;
      end
      if (wcur.beats < AXI_MAX_BEATS) begin
        wcur.data[wcur.beats]  = w_pl.data;
        wcur.strb[wcur.beats]  = w_pl.strb;
        wcur.waits[wcur.beats] = w_wait;
        wcur.beats++;
      end else if (!wcur_over) begin
        flag(AXI_MON_ERR_WLAST, "more than 256 write data beats without WLAST");
        wcur_over = 1'b1;
      end
      wcur.last_cycle = cycle;
      if (w_pl.last === 1'b1) begin
        if (wb_q.size() >= MAX_OUTSTANDING)
          flag(AXI_MON_ERR_CAPACITY, "more write data bursts than MAX_OUTSTANDING; dropped");
        else
          wb_q.push_back(wcur);
        wcur_open = 1'b0;
      end
    end

    // Pair write addresses and data bursts in order (AXI4 has no WID)
    while (aw_q.size() != 0 && wb_q.size() != 0)
      pair_write(aw_q.pop_front(), wb_q.pop_front(), lite);

    // AR handshake: the read collects data from the next edge on (AXI-R07)
    if (ar_v && ar_r) begin
      ax.pl          = ar_pl;
      ax.shape_known = !$isunknown(ar_pl);
      ax.wait_cycles = ar_wait;
      ax.cycle       = cycle;
      check_address(ax, "AR", lite);
      if (rd_q.size() >= MAX_OUTSTANDING) begin
        flag(AXI_MON_ERR_CAPACITY, "more open reads than MAX_OUTSTANDING; address dropped");
      end else begin
        t.write      = 1'b0;
        t.ax         = ax;
        t.d          = empty_data();
        t.bresp      = 2'b00;
        t.resp_wait  = 0;
        t.resp_cycle = 0;
        rd_q.push_back(t);
      end
    end

    // History for the next sample
    aw_pend = aw_v && !aw_r;
    w_pend  = w_v && !w_r;
    b_pend  = b_v && !b_r;
    ar_pend = ar_v && !ar_r;
    r_pend  = r_v && !r_r;
    aw_prev = aw_pl;
    w_prev  = w_pl;
    b_prev  = b_pl;
    ar_prev = ar_pl;
    r_prev  = r_pl;
  endtask

  // Elaboration-time checks (widths must match the shared axi_if)
  if (DATA_WIDTH < 8 || DATA_WIDTH % 8 != 0 || STRB_WIDTH > AXI_MAX_LANES)
  begin : g_bad_data_width
    $error("axi_monitor_bfm_if: DATA_WIDTH=%0d is not 8..1024 whole bytes", DATA_WIDTH);
  end
  if (ADDR_WIDTH < 1 || ADDR_WIDTH > AXI_FN_AW) begin : g_bad_addr_width
    $error("axi_monitor_bfm_if: ADDR_WIDTH=%0d outside 1..%0d", ADDR_WIDTH, AXI_FN_AW);
  end
  if (QUEUE_DEPTH < 1 || MAX_OUTSTANDING < 1) begin : g_bad_depth
    $error("axi_monitor_bfm_if: QUEUE_DEPTH and MAX_OUTSTANDING must be >= 1");
  end

endinterface : axi_monitor_bfm_if
