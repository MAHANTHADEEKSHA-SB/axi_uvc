// -----------------------------------------------------------------------------
// axi_subordinate_bfm_if — AXI Subordinate (responder) BFM
//
// Owns timed AXI Subordinate behaviour (ADR-002 decision 2, Subordinate role
// of owner decision A-1). Connects to the shared axi_if instance through
// ordinary signal ports wired in the HDL top (ADR-002 decision 7).
//
// Reactive split (AXI_PROTOCOL_CONTRACT section 8):
//   * an always-running per-edge process accepts AW, W and AR transfers under
//     a per-channel READY policy (POL-06), pairs each write address with its
//     write data burst (data may arrive first, AXI-R06), and queues complete
//     requests as plain values (no UVM objects in HDL, ADR-002 section 6);
//   * the HVL respond adapter takes requests with the blocking get_request()
//     and returns responses with put_write_response()/put_read_response();
//   * the same process drives B and R from the response queues, in request
//     order per direction, without interleaving read bursts (POL-05).
// A response can be queued only for the oldest unanswered request of its
// direction with the same ID (and length), so ID ordering holds (AXI-R20).
// Reset drops every queue; responses to requests taken before the reset are
// refused through the epoch number (RST-8).
// User signals exist as ports; BUSER and RUSER are driven 0 until M2.
// Compile after axi_bfm_pkg.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

interface axi_subordinate_bfm_if
  import axi_bfm_pkg::*;
#(
  parameter int ADDR_WIDTH      = 32,
  parameter int DATA_WIDTH      = 32,
  parameter int ID_W_WIDTH      = 4,
  parameter int ID_R_WIDTH      = 4,
  parameter int USER_REQ_WIDTH  = 1,
  parameter int USER_DATA_WIDTH = 1,
  parameter int USER_RESP_WIDTH = 1,
  parameter int QUEUE_DEPTH     = 8   // open transactions per direction (POL-08)
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
  output wire logic                           AWREADY,
  // Write data channel
  input  wire logic [DATA_WIDTH-1:0]          WDATA,
  input  wire logic [DATA_WIDTH/8-1:0]        WSTRB,
  input  wire logic                           WLAST,
  input  wire logic [USER_DATA_WIDTH-1:0]     WUSER,
  input  wire logic                           WVALID,
  output wire logic                           WREADY,
  // Write response channel
  output wire logic [ID_W_WIDTH-1:0]          BID,
  output wire logic [1:0]                     BRESP,
  output wire logic [USER_RESP_WIDTH-1:0]     BUSER,
  output wire logic                           BVALID,
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
  output wire logic                           ARREADY,
  // Read data channel
  output wire logic [ID_R_WIDTH-1:0]          RID,
  output wire logic [DATA_WIDTH-1:0]          RDATA,
  output wire logic [1:0]                     RRESP,
  output wire logic                           RLAST,
  output wire logic [USER_DATA_WIDTH-1:0]     RUSER,
  output wire logic                           RVALID,
  input  wire logic                           RREADY
);

  localparam int         STRB_WIDTH   = DATA_WIDTH / 8;
  localparam int         ID_MAX_WIDTH = (ID_W_WIDTH > ID_R_WIDTH) ? ID_W_WIDTH : ID_R_WIDTH;
  localparam logic [2:0] FULL_SIZE    = 3'($clog2(STRB_WIDTH));  // AxSIZE of a full beat

  // One address transfer (AW or AR) as accepted
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
  } axi_ax_t;

  // One write data burst, up to and including the WLAST beat
  typedef struct {
    int unsigned           beats;
    logic [DATA_WIDTH-1:0] data [AXI_MAX_BEATS];
    logic [STRB_WIDTH-1:0] strb [AXI_MAX_BEATS];
  } axi_wburst_t;

  // One complete request waiting for the HVL side
  typedef struct {
    bit                    write;
    axi_ax_t               ax;
    int unsigned           beats;    // write data beats received (0 for reads)
    logic [DATA_WIDTH-1:0] data [AXI_MAX_BEATS];
    logic [STRB_WIDTH-1:0] strb [AXI_MAX_BEATS];
    longint unsigned       cycle;    // sample at which the request became complete
    int unsigned           epoch;    // reset epoch it belongs to (RST-8)
  } axi_req_t;

  // An unanswered request, oldest first per direction (AXI-R20, POL-05)
  typedef struct packed {
    logic [ID_MAX_WIDTH-1:0] id;
    int unsigned             len;
  } axi_pend_t;

  // A queued write response
  typedef struct packed {
    logic [ID_W_WIDTH-1:0] id;
    logic [1:0]            resp;
    int unsigned           delay;   // edges before BVALID once it is eligible
    longint unsigned       queued;  // cycle counter when it was queued
  } axi_bresp_t;

  // A queued read response (one burst)
  typedef struct {
    logic [ID_R_WIDTH-1:0] id;
    int unsigned           len;
    logic [DATA_WIDTH-1:0] data  [AXI_MAX_BEATS];
    logic [1:0]            resp  [AXI_MAX_BEATS];
    int unsigned           delay [AXI_MAX_BEATS];  // edges before each beat's RVALID
    longint unsigned       queued;
  } axi_rresp_t;

  // Drive state, written with nonblocking assignments (HDL-05)
  logic                  awready_q = 1'b0;
  logic                  wready_q  = 1'b0;
  logic                  arready_q = 1'b0;
  logic                  bvalid_q  = 1'b0;
  logic [ID_W_WIDTH-1:0] bid_q     = '0;
  logic [1:0]            bresp_q   = 2'b00;
  logic                  rvalid_q  = 1'b0;
  logic [ID_R_WIDTH-1:0] rid_q     = '0;
  logic [DATA_WIDTH-1:0] rdata_q   = '0;
  logic [1:0]            rresp_q   = 2'b00;
  logic                  rlast_q   = 1'b0;

  bit              drive_en       = 1'b0;  // 0: every output released to 'z (passive-safe)
  axi_features_t   features       = axi_default_features();
  axi_fault_e      fault          = AXI_FAULT_NONE;
  int unsigned     aw_ready_delay = 0;     // POL-06: 0 = READY HIGH while there is room
  int unsigned     w_ready_delay  = 0;
  int unsigned     ar_ready_delay = 0;
  int unsigned     epoch          = 0;     // moves on at every reset (RST-8)
  longint unsigned cycle          = 0;
  int unsigned     request_count  = 0;     // requests completed since time 0
  int unsigned     response_count = 0;     // B and last-R handshakes since time 0

  // Request side
  axi_ax_t     aw_q[$];                    // write addresses waiting for their data
  axi_wburst_t wb_q[$];                    // write data bursts waiting for an address
  axi_wburst_t wcur;                       // write data burst being received
  bit          wcur_open = 1'b0;
  axi_req_t    req_q[$];                   // complete requests for get_request()
  event        req_ev;                     // triggered when req_q receives entries
  axi_pend_t   wr_pend_q[$];               // complete writes not answered yet
  axi_pend_t   rd_pend_q[$];               // reads not answered yet
  int unsigned aw_seen = 0;                // cycles the current AWVALID waited
  int unsigned w_seen  = 0;
  int unsigned ar_seen = 0;

  // Response side
  axi_bresp_t  b_q[$];
  axi_rresp_t  r_q[$];
  axi_bresp_t  b_cur;                      // response on (or counting down to) B
  bit          b_busy = 1'b0;
  bit          b_on   = 1'b0;              // BVALID HIGH
  int unsigned b_left = 0;
  axi_rresp_t  r_cur;                      // burst on (or counting down to) R
  bit          r_busy = 1'b0;
  bit          r_on   = 1'b0;              // RVALID HIGH for beat r_beat
  int unsigned r_beat = 0;
  int unsigned r_left = 0;

  // Release-capable output stage (AXI_PROTOCOL_CONTRACT section 8)
  assign AWREADY = drive_en ? awready_q : 1'bz;
  assign WREADY  = drive_en ? wready_q  : 1'bz;
  assign ARREADY = drive_en ? arready_q : 1'bz;
  assign BVALID  = drive_en ? bvalid_q  : 1'bz;
  assign BID     = drive_en ? bid_q     : 'z;
  assign BRESP   = drive_en ? bresp_q   : 'z;
  assign RVALID  = drive_en ? rvalid_q  : 1'bz;
  assign RID     = drive_en ? rid_q     : 'z;
  assign RDATA   = drive_en ? rdata_q   : 'z;
  assign RRESP   = drive_en ? rresp_q   : 'z;
  assign RLAST   = drive_en ? rlast_q   : 1'bz;
  // Milestone M2 outputs: absent, driven to 0 while enabled (POL-03)
  assign BUSER   = drive_en ? '0 : 'z;
  assign RUSER   = drive_en ? '0 : 'z;

  // Inputs are sampled 1step before each ACLK rising edge (HDL-05).
  clocking cb @(posedge ACLK);
    default input #1step;
    input ARESETn, AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS,
          AWREGION, AWVALID, WDATA, WSTRB, WLAST, WVALID, BREADY, ARID, ARADDR, ARLEN,
          ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARVALID, RREADY;
  endclocking

  // ---------------------------------------------------------------------------
  // Control API (called through a virtual interface by the HVL respond adapter)
  // ---------------------------------------------------------------------------

  // Accept a per-instance feature set unless it is illegal for its protocol mode
  // (CFG-01) or not implemented yet (CFG-02). Only while no transaction is open.
  function automatic bit configure(axi_features_t f);
    string problem;
    if (!is_idle()) begin
      $error("%m: configure() while transactions are open");
      return 1'b0;
    end
    problem = axi_protocol_problem(f, DATA_WIDTH);
    if (problem == "") problem = axi_milestone_problem(f);
    if (problem != "") begin
      $error("%m: feature set rejected: %s", problem);
      return 1'b0;
    end
    features = f;
    return 1'b1;
  endfunction

  // 1: drive the bus; 0: release every output to 'z and accept nothing
  function automatic void set_enable(bit en);
    if (!is_idle() && !en) $error("%m: Subordinate released while transactions are open");
    drive_en = en;
  endfunction

  // READY policy per channel (POL-06): 0 keeps READY HIGH while there is room;
  // d > 0 raises READY after the VALID has waited d cycles, so every transfer
  // of that channel sees d wait cycles.
  function automatic void set_ready_delays(int unsigned aw, int unsigned w, int unsigned ar);
    aw_ready_delay = aw;
    w_ready_delay  = w;
    ar_ready_delay = ar;
  endfunction

  // Negative tests only (axi_fault_e). AXI_FAULT_RLAST_EARLY applies to every
  // following read burst of two or more beats; Manager faults are ignored here.
  function automatic void set_fault(axi_fault_e f);
    fault = f;
  endfunction

  // Blocks until a complete request is available, then removes it. The queue is
  // checked before waiting, so a request completed earlier in the same time step
  // is never missed. id is zero-extended to the wider of the two ID widths; len
  // is AxLEN+1; beats is the number of write data beats received. Entries at
  // index >= beats are zero.
  task automatic get_request(
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
    output logic [DATA_WIDTH-1:0]   wdata [AXI_MAX_BEATS],
    output logic [STRB_WIDTH-1:0]   wstrb [AXI_MAX_BEATS],
    output longint unsigned         req_cycle,
    output int unsigned             req_epoch
  );
    axi_req_t r;
    while (req_q.size() == 0) @(req_ev);
    r         = req_q.pop_front();
    write     = r.write;
    id        = r.ax.id;
    addr      = r.ax.addr;
    len       = int'(r.ax.len) + 1;
    size      = r.ax.size;
    burst     = r.ax.burst;
    lock      = r.ax.lock;
    cache     = r.ax.cache;
    prot      = r.ax.prot;
    qos       = r.ax.qos;
    region    = r.ax.region;
    beats     = r.beats;
    wdata     = r.data;
    wstrb     = r.strb;
    req_cycle = r.cycle;
    req_epoch = r.epoch;
  endtask

  // Queue the write response for the oldest unanswered write (it must carry the
  // same ID, AXI-R20). BVALID rises `delay` edges after the edge that follows
  // this call. Returns AXI_ST_OK, or why nothing was queued.
  function automatic axi_bfm_status_e put_write_response(
    input int unsigned           req_epoch,
    input logic [ID_W_WIDTH-1:0] id,
    input logic [1:0]            resp,
    input int unsigned           delay
  );
    axi_bresp_t b;
    if (!drive_en)                    return AXI_ST_NOT_ENABLED;
    if (req_epoch != epoch)           return AXI_ST_RESET_ABORTED;  // RST-8
    if (wr_pend_q.size() == 0)        return AXI_ST_BAD_REQUEST;
    if (wr_pend_q[0].id !== ID_MAX_WIDTH'(id) || $isunknown(resp)) return AXI_ST_BAD_REQUEST;
    void'(wr_pend_q.pop_front());
    b.id     = id;
    b.resp   = resp;
    b.delay  = delay;
    b.queued = cycle;
    b_q.push_back(b);
    return AXI_ST_OK;
  endfunction

  // Queue the read data burst for the oldest unanswered read (same ID and length,
  // AXI-R20). Beat i's RVALID rises delay[i] edges after it may start: beat 0
  // after the edge that follows this call, beat i after the handshake of beat i-1.
  function automatic axi_bfm_status_e put_read_response(
    input int unsigned           req_epoch,
    input logic [ID_R_WIDTH-1:0] id,
    input int unsigned           len,
    input logic [DATA_WIDTH-1:0] rdata [AXI_MAX_BEATS],
    input logic [1:0]            rresp [AXI_MAX_BEATS],
    input int unsigned           delay [AXI_MAX_BEATS]
  );
    axi_rresp_t r;
    if (!drive_en)                    return AXI_ST_NOT_ENABLED;
    if (req_epoch != epoch)           return AXI_ST_RESET_ABORTED;  // RST-8
    if (rd_pend_q.size() == 0)        return AXI_ST_BAD_REQUEST;
    if (rd_pend_q[0].id !== ID_MAX_WIDTH'(id) || rd_pend_q[0].len != len)
      return AXI_ST_BAD_REQUEST;
    for (int unsigned i = 0; i < len; i++)
      if ($isunknown(rresp[i])) return AXI_ST_BAD_REQUEST;
    void'(rd_pend_q.pop_front());
    r.id     = id;
    r.len    = len;
    r.data   = rdata;
    r.resp   = rresp;
    r.delay  = delay;
    r.queued = cycle;
    r_q.push_back(r);
    return AXI_ST_OK;
  endfunction

  // 1 when no transaction is open in either direction
  function automatic bit is_idle();
    return aw_q.size() == 0 && wb_q.size() == 0 && !wcur_open && req_q.size() == 0 &&
           wr_pend_q.size() == 0 && rd_pend_q.size() == 0 && b_q.size() == 0 &&
           r_q.size() == 0 && !b_busy && !r_busy;
  endfunction

  // ---------------------------------------------------------------------------
  // Per-edge process
  // ---------------------------------------------------------------------------

  // One sample_cycle() per ACLK edge, independent of the HVL side.
  initial forever begin
    @(cb);
    cycle++;
    sample_cycle();
  end

  // Process one ACLK sample, in this order: responses that completed (B, R),
  // requests that were accepted (AW, W, AR) and write pairing, the next B/R
  // drive step, then the READY values for the next cycle. Consumes no time.
  // Nothing happens in reset (the queues were dropped when it asserted) or while
  // the BFM is released. The live ARESETn is checked as well as the sampled one:
  // a reset that asserts in this very time step, before this process runs, must
  // not be overridden by drive values computed from the pre-reset sample (RST-1).
  task automatic sample_cycle();
    bit lite;
    bit aw_hs;
    bit w_hs;
    bit ar_hs;
    bit r_hs;
    bit pushed;
    if (cb.ARESETn !== 1'b1 || ARESETn !== 1'b1 || !drive_en) return;
    lite   = (features.protocol == AXI4_LITE);
    pushed = 1'b0;

    // Response handshakes: our VALID was HIGH during the cycle that just ended
    // (its register still holds that value) and the Manager's READY was HIGH.
    if (b_on && cb.BREADY === 1'b1) begin
      idle_b();
      b_on   = 1'b0;
      b_busy = 1'b0;
      response_count++;
    end
    r_hs = r_on && (cb.RREADY === 1'b1);
    if (r_hs) begin
      r_beat++;
      r_on = 1'b0;
      if (r_beat == r_cur.len) begin
        idle_r();
        r_busy = 1'b0;
        response_count++;
      end else begin
        r_left = r_cur.delay[r_beat];
        if (r_left == 0) begin
          drive_r_beat(lite);  // RVALID stays HIGH, next beat (AXI-R02)
          r_on = 1'b1;
        end else begin
          idle_r();
        end
      end
    end

    // Request handshakes: our READY was HIGH during the cycle that just ended.
    aw_hs = (awready_q === 1'b1) && (cb.AWVALID === 1'b1);
    w_hs  = (wready_q === 1'b1) && (cb.WVALID === 1'b1);
    ar_hs = (arready_q === 1'b1) && (cb.ARVALID === 1'b1);
    if (aw_hs) aw_q.push_back(sample_aw(lite));
    if (w_hs) take_w_beat(lite);
    // AXI4: write data bursts follow the write address order (AXI-R20).
    while (aw_q.size() != 0 && wb_q.size() != 0) begin
      push_request(1'b1, aw_q.pop_front(), wb_q.pop_front());
      pushed = 1'b1;
    end
    if (ar_hs) begin
      push_request(1'b0, sample_ar(lite), empty_burst());
      pushed = 1'b1;
    end
    if (pushed) -> req_ev;

    // Next drive step of each response channel
    step_b();
    step_r(lite, r_hs);

    // READY for the next cycle (POL-06, POL-08)
    if (aw_hs || cb.AWVALID !== 1'b1) aw_seen = 0; else aw_seen++;
    if (w_hs  || cb.WVALID  !== 1'b1) w_seen  = 0; else w_seen++;
    if (ar_hs || cb.ARVALID !== 1'b1) ar_seen = 0; else ar_seen++;
    awready_q <= next_ready(cb.AWVALID === 1'b1, aw_hs, aw_seen, aw_ready_delay,
                            open_writes() < QUEUE_DEPTH);
    wready_q  <= next_ready(cb.WVALID === 1'b1, w_hs, w_seen, w_ready_delay,
                            wb_q.size() < QUEUE_DEPTH);
    arready_q <= next_ready(cb.ARVALID === 1'b1, ar_hs, ar_seen, ar_ready_delay,
                            open_reads() < QUEUE_DEPTH);
  endtask

  // READY for the next cycle: LOW without room; HIGH while idle when the delay is
  // 0; otherwise HIGH once the VALID has waited `delay` cycles (POL-06). A
  // Subordinate may lower READY before VALID arrives (AXI-R05).
  function automatic bit next_ready(bit valid, bit hs, int unsigned seen, int unsigned delay,
                                    bit room);
    if (!room)      return 1'b0;
    if (delay == 0) return 1'b1;
    return valid && !hs && (seen >= delay);
  endfunction

  // Open write transactions: addresses without data, complete but unanswered,
  // answered but not yet sent.
  function automatic int unsigned open_writes();
    return aw_q.size() + wr_pend_q.size() + b_q.size() + (b_busy ? 1 : 0);
  endfunction

  // Open read transactions: unanswered, answered but not yet sent.
  function automatic int unsigned open_reads();
    return rd_pend_q.size() + r_q.size() + (r_busy ? 1 : 0);
  endfunction

  // Accepted write address. AXI4-Lite has no ID/LEN/SIZE/BURST/LOCK/CACHE/QOS/
  // REGION: one full-width INCR beat with ID 0 (AXI-R24).
  function automatic axi_ax_t sample_aw(bit lite);
    axi_ax_t a;
    a.addr   = cb.AWADDR;
    a.prot   = cb.AWPROT;
    a.id     = lite ? '0 : ID_MAX_WIDTH'(cb.AWID);
    a.len    = lite ? 8'h00 : cb.AWLEN;
    a.size   = lite ? FULL_SIZE : cb.AWSIZE;
    a.burst  = lite ? AXI_BURST_INCR : cb.AWBURST;
    a.lock   = lite ? 1'b0 : cb.AWLOCK;
    a.cache  = lite ? 4'h0 : cb.AWCACHE;
    a.qos    = lite ? 4'h0 : cb.AWQOS;
    a.region = lite ? 4'h0 : cb.AWREGION;
    return a;
  endfunction

  // Accepted read address (same AXI4-Lite rule as sample_aw()).
  function automatic axi_ax_t sample_ar(bit lite);
    axi_ax_t a;
    a.addr   = cb.ARADDR;
    a.prot   = cb.ARPROT;
    a.id     = lite ? '0 : ID_MAX_WIDTH'(cb.ARID);
    a.len    = lite ? 8'h00 : cb.ARLEN;
    a.size   = lite ? FULL_SIZE : cb.ARSIZE;
    a.burst  = lite ? AXI_BURST_INCR : cb.ARBURST;
    a.lock   = lite ? 1'b0 : cb.ARLOCK;
    a.cache  = lite ? 4'h0 : cb.ARCACHE;
    a.qos    = lite ? 4'h0 : cb.ARQOS;
    a.region = lite ? 4'h0 : cb.ARREGION;
    return a;
  endfunction

  // A write data burst with no beats (used for read requests)
  function automatic axi_wburst_t empty_burst();
    axi_wburst_t w;
    w.beats = 0;
    for (int unsigned i = 0; i < AXI_MAX_BEATS; i++) begin
      w.data[i] = '0;
      w.strb[i] = '0;
    end
    return w;
  endfunction

  // Store one accepted write data beat. WLAST closes the burst (AXI-R15); on
  // AXI4-Lite every beat is a burst (AXI-R24). Beats beyond AXI_MAX_BEATS cannot
  // be legal and are dropped; the monitor reports the violation.
  task automatic take_w_beat(bit lite);
    if (!wcur_open) begin
      wcur      = empty_burst();
      wcur_open = 1'b1;
    end
    if (wcur.beats < AXI_MAX_BEATS) begin
      wcur.data[wcur.beats] = cb.WDATA;
      wcur.strb[wcur.beats] = cb.WSTRB;
      wcur.beats++;
    end
    if (lite || cb.WLAST === 1'b1) begin
      wb_q.push_back(wcur);
      wcur_open = 1'b0;
    end
  endtask

  // Queue one complete request for get_request() and record it as unanswered.
  task automatic push_request(bit write, axi_ax_t ax, axi_wburst_t w);
    axi_req_t  r;
    axi_pend_t p;
    r.write = write;
    r.ax    = ax;
    r.beats = w.beats;
    r.data  = w.data;
    r.strb  = w.strb;
    r.cycle = cycle;
    r.epoch = epoch;
    req_q.push_back(r);
    p.id  = ax.id;
    p.len = int'(ax.len) + 1;
    if (write) wr_pend_q.push_back(p);
    else       rd_pend_q.push_back(p);
    request_count++;
  endtask

  // Write response channel step: count down to BVALID, or start the next queued
  // response. A response becomes eligible at the edge after it was queued, so
  // the timing does not depend on process order within a time step (LANG-09).
  task automatic step_b();
    if (b_busy && !b_on) begin
      b_left--;
      if (b_left == 0) begin
        drive_b();
        b_on = 1'b1;
      end
    end else if (!b_busy && b_q.size() != 0 && b_q[0].queued < cycle) begin
      b_cur  = b_q.pop_front();
      b_busy = 1'b1;
      b_left = b_cur.delay;
      if (b_left == 0) begin
        drive_b();
        b_on = 1'b1;
      end
    end
  endtask

  // Read data channel step: count down to the next beat's RVALID, or start the
  // next queued burst (eligible from the edge after it was queued). A gap after a
  // beat starts counting at the edge after that beat's handshake (hs_now).
  task automatic step_r(bit lite, bit hs_now);
    if (r_busy && !r_on) begin
      if (hs_now) return;
      if (r_left != 0) r_left--;
      if (r_left == 0) begin
        drive_r_beat(lite);
        r_on = 1'b1;
      end
    end else if (!r_busy && r_q.size() != 0 && r_q[0].queued < cycle) begin
      r_cur  = r_q.pop_front();
      r_busy = 1'b1;
      r_beat = 0;
      r_left = r_cur.delay[0];
      if (r_left == 0) begin
        drive_r_beat(lite);
        r_on = 1'b1;
      end
    end
  endtask

  // Present the current write response; AXI4-Lite has no BID (AXI-R24).
  task automatic drive_b();
    bvalid_q <= 1'b1;
    bid_q    <= (features.protocol == AXI4_LITE) ? '0 : b_cur.id;
    bresp_q  <= b_cur.resp;
  endtask

  // Present beat r_beat of the current read burst. RLAST marks the last beat
  // (AXI-R15); fault mode 4 also sets it on the second-to-last beat. AXI4-Lite
  // has no RID or RLAST (AXI-R24).
  task automatic drive_r_beat(bit lite);
    bit last;
    last = (r_beat == r_cur.len - 1) ||
           (fault == AXI_FAULT_RLAST_EARLY && r_cur.len >= 2 && r_beat == r_cur.len - 2);
    rvalid_q <= 1'b1;
    rid_q    <= lite ? '0 : r_cur.id;
    rdata_q  <= r_cur.data[r_beat];
    rresp_q  <= r_cur.resp[r_beat];
    rlast_q  <= lite ? 1'b0 : last;
  endtask

  // No write response on the bus: BVALID LOW, payload 0 (POL-03)
  task automatic idle_b();
    bvalid_q <= 1'b0;
    bid_q    <= '0;
    bresp_q  <= 2'b00;
  endtask

  // No read data on the bus: RVALID LOW, payload 0 (POL-03)
  task automatic idle_r();
    rvalid_q <= 1'b0;
    rid_q    <= '0;
    rdata_q  <= '0;
    rresp_q  <= 2'b00;
    rlast_q  <= 1'b0;
  endtask

  // RST-1/RST-8: as soon as reset asserts (or goes X/Z) every VALID and READY goes
  // LOW and every open transaction is dropped. The epoch moves on, so responses
  // to requests handed out before the reset are refused.
  always @(ARESETn)
    if (ARESETn !== 1'b1) begin
      idle_b();
      idle_r();
      awready_q <= 1'b0;
      wready_q  <= 1'b0;
      arready_q <= 1'b0;
      aw_q.delete();
      wb_q.delete();
      req_q.delete();
      wr_pend_q.delete();
      rd_pend_q.delete();
      b_q.delete();
      r_q.delete();
      wcur_open = 1'b0;
      b_busy    = 1'b0;
      b_on      = 1'b0;
      r_busy    = 1'b0;
      r_on      = 1'b0;
      aw_seen   = 0;
      w_seen    = 0;
      ar_seen   = 0;
      epoch++;
    end

  // Elaboration-time checks (widths must match the shared axi_if)
  if (DATA_WIDTH < 8 || DATA_WIDTH % 8 != 0 || STRB_WIDTH > AXI_MAX_LANES)
  begin : g_bad_data_width
    $error("axi_subordinate_bfm_if: DATA_WIDTH=%0d is not 8..1024 whole bytes", DATA_WIDTH);
  end
  if (ADDR_WIDTH < 1 || ADDR_WIDTH > AXI_FN_AW) begin : g_bad_addr_width
    $error("axi_subordinate_bfm_if: ADDR_WIDTH=%0d outside 1..%0d", ADDR_WIDTH, AXI_FN_AW);
  end
  if (QUEUE_DEPTH < 1) begin : g_bad_queue_depth
    $error("axi_subordinate_bfm_if: QUEUE_DEPTH must be >= 1");
  end

endinterface : axi_subordinate_bfm_if
