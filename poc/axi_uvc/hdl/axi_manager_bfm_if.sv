// -----------------------------------------------------------------------------
// axi_manager_bfm_if — AXI Manager drive BFM
//
// Owns timed AXI Manager drive (ADR-002 decision 2). Connects to the shared
// axi_if instance through ordinary signal ports wired in the HDL top
// (ADR-002 decision 7); it has no interface-typed ports, so a virtual handle
// to this interface avoids the IEEE restriction noted in DVCon 2024.
//
// do_write() runs one write transaction (AW, W beats, B) and do_read() one
// read transaction (AR, R beats). The write and the read paths have separate
// state, so one write and one read may be in flight at the same time; more
// than one outstanding transaction per direction is milestone M2 (POL-02).
// Each call is one per-edge state machine over its channels, so AW and W are
// driven independently and neither waits for the other's READY (AXI-R06).
// Contract references: docs/dv-architecture/AXI_PROTOCOL_CONTRACT.md
//   AXI-R02..R07  handshakes, VALID/payload held until the handshake,
//                 channel dependencies
//   AXI-R08..R15  burst shape, strobes, WLAST (the drive adapter checks the
//                 rest of the request before calling these tasks)
//   AXI-R24       AXI4-Lite: absent signals driven to 0 (POL-03)
//   RST-1..RST-3, RST-5  reset behaviour
//   section 8     drive release: outputs are 'z until set_enable(1)
// User signals exist as ports but are driven to 0 until milestone M2.
// Compile after axi_bfm_pkg.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

interface axi_manager_bfm_if
  import axi_bfm_pkg::*;
#(
  parameter int ADDR_WIDTH      = 32,
  parameter int DATA_WIDTH      = 32,
  parameter int ID_W_WIDTH      = 4,
  parameter int ID_R_WIDTH      = 4,
  parameter int USER_REQ_WIDTH  = 1,
  parameter int USER_DATA_WIDTH = 1,
  parameter int USER_RESP_WIDTH = 1
) (
  input  wire logic                           ACLK,
  input  wire logic                           ARESETn,
  // Write address channel
  output wire logic [ID_W_WIDTH-1:0]          AWID,
  output wire logic [ADDR_WIDTH-1:0]          AWADDR,
  output wire logic [7:0]                     AWLEN,
  output wire logic [2:0]                     AWSIZE,
  output wire logic [1:0]                     AWBURST,
  output wire logic                           AWLOCK,
  output wire logic [3:0]                     AWCACHE,
  output wire logic [2:0]                     AWPROT,
  output wire logic [3:0]                     AWQOS,
  output wire logic [3:0]                     AWREGION,
  output wire logic [USER_REQ_WIDTH-1:0]      AWUSER,
  output wire logic                           AWVALID,
  input  wire logic                           AWREADY,
  // Write data channel
  output wire logic [DATA_WIDTH-1:0]          WDATA,
  output wire logic [DATA_WIDTH/8-1:0]        WSTRB,
  output wire logic                           WLAST,
  output wire logic [USER_DATA_WIDTH-1:0]     WUSER,
  output wire logic                           WVALID,
  input  wire logic                           WREADY,
  // Write response channel
  input  wire logic [ID_W_WIDTH-1:0]          BID,
  input  wire logic [1:0]                     BRESP,
  input  wire logic [USER_RESP_WIDTH-1:0]     BUSER,
  input  wire logic                           BVALID,
  output wire logic                           BREADY,
  // Read address channel
  output wire logic [ID_R_WIDTH-1:0]          ARID,
  output wire logic [ADDR_WIDTH-1:0]          ARADDR,
  output wire logic [7:0]                     ARLEN,
  output wire logic [2:0]                     ARSIZE,
  output wire logic [1:0]                     ARBURST,
  output wire logic                           ARLOCK,
  output wire logic [3:0]                     ARCACHE,
  output wire logic [2:0]                     ARPROT,
  output wire logic [3:0]                     ARQOS,
  output wire logic [3:0]                     ARREGION,
  output wire logic [USER_REQ_WIDTH-1:0]      ARUSER,
  output wire logic                           ARVALID,
  input  wire logic                           ARREADY,
  // Read data channel
  input  wire logic [ID_R_WIDTH-1:0]          RID,
  input  wire logic [DATA_WIDTH-1:0]          RDATA,
  input  wire logic [1:0]                     RRESP,
  input  wire logic                           RLAST,
  input  wire logic [USER_DATA_WIDTH-1:0]     RUSER,
  input  wire logic                           RVALID,
  output wire logic                           RREADY
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  // Drive state, written by the tasks below with nonblocking assignments so a
  // Subordinate sampling on the same ACLK edge sees the previous value (HDL-05).
  logic                  awvalid_q  = 1'b0;
  logic [ID_W_WIDTH-1:0] awid_q     = '0;
  logic [ADDR_WIDTH-1:0] awaddr_q   = '0;
  logic [7:0]            awlen_q    = 8'h00;
  logic [2:0]            awsize_q   = 3'b000;
  logic [1:0]            awburst_q  = 2'b00;
  logic                  awlock_q   = 1'b0;
  logic [3:0]            awcache_q  = 4'h0;
  logic [2:0]            awprot_q   = 3'b000;
  logic [3:0]            awqos_q    = 4'h0;
  logic [3:0]            awregion_q = 4'h0;
  logic                  wvalid_q   = 1'b0;
  logic [DATA_WIDTH-1:0] wdata_q    = '0;
  logic [STRB_WIDTH-1:0] wstrb_q    = '0;
  logic                  wlast_q    = 1'b0;
  logic                  bready_q   = 1'b0;
  logic                  arvalid_q  = 1'b0;
  logic [ID_R_WIDTH-1:0] arid_q     = '0;
  logic [ADDR_WIDTH-1:0] araddr_q   = '0;
  logic [7:0]            arlen_q    = 8'h00;
  logic [2:0]            arsize_q   = 3'b000;
  logic [1:0]            arburst_q  = 2'b00;
  logic                  arlock_q   = 1'b0;
  logic [3:0]            arcache_q  = 4'h0;
  logic [2:0]            arprot_q   = 3'b000;
  logic [3:0]            arqos_q    = 4'h0;
  logic [3:0]            arregion_q = 4'h0;
  logic                  rready_q   = 1'b0;

  bit            drive_en     = 1'b0;  // 0: every output released to 'z (passive-safe)
  bit            wr_in_flight = 1'b0;  // a do_write() call owns AW/W/B
  bit            rd_in_flight = 1'b0;  // a do_read() call owns AR/R
  axi_features_t features     = axi_default_features();
  axi_fault_e    fault        = AXI_FAULT_NONE;

  // Release-capable output stage (AXI_PROTOCOL_CONTRACT section 8)
  assign AWID     = drive_en ? awid_q     : 'z;
  assign AWADDR   = drive_en ? awaddr_q   : 'z;
  assign AWLEN    = drive_en ? awlen_q    : 'z;
  assign AWSIZE   = drive_en ? awsize_q   : 'z;
  assign AWBURST  = drive_en ? awburst_q  : 'z;
  assign AWLOCK   = drive_en ? awlock_q   : 1'bz;
  assign AWCACHE  = drive_en ? awcache_q  : 'z;
  assign AWPROT   = drive_en ? awprot_q   : 'z;
  assign AWQOS    = drive_en ? awqos_q    : 'z;
  assign AWREGION = drive_en ? awregion_q : 'z;
  assign AWVALID  = drive_en ? awvalid_q  : 1'bz;
  assign WDATA    = drive_en ? wdata_q    : 'z;
  assign WSTRB    = drive_en ? wstrb_q    : 'z;
  assign WLAST    = drive_en ? wlast_q    : 1'bz;
  assign WVALID   = drive_en ? wvalid_q   : 1'bz;
  assign BREADY   = drive_en ? bready_q   : 1'bz;
  assign ARID     = drive_en ? arid_q     : 'z;
  assign ARADDR   = drive_en ? araddr_q   : 'z;
  assign ARLEN    = drive_en ? arlen_q    : 'z;
  assign ARSIZE   = drive_en ? arsize_q   : 'z;
  assign ARBURST  = drive_en ? arburst_q  : 'z;
  assign ARLOCK   = drive_en ? arlock_q   : 1'bz;
  assign ARCACHE  = drive_en ? arcache_q  : 'z;
  assign ARPROT   = drive_en ? arprot_q   : 'z;
  assign ARQOS    = drive_en ? arqos_q    : 'z;
  assign ARREGION = drive_en ? arregion_q : 'z;
  assign ARVALID  = drive_en ? arvalid_q  : 1'bz;
  assign RREADY   = drive_en ? rready_q   : 1'bz;
  // Milestone M2 outputs: absent, driven to 0 while enabled (POL-03)
  assign AWUSER   = drive_en ? '0 : 'z;
  assign WUSER    = drive_en ? '0 : 'z;
  assign ARUSER   = drive_en ? '0 : 'z;

  // Inputs are sampled 1step before each ACLK rising edge: the values the
  // Subordinate presented during that cycle (HDL-05). Manager outputs are not
  // driven through this block; the tasks below update them with NBAs.
  clocking cb @(posedge ACLK);
    default input #1step;
    input ARESETn, AWREADY, WREADY, BID, BRESP, BVALID, ARREADY, RID, RDATA, RRESP, RVALID;
  endclocking

  // ---------------------------------------------------------------------------
  // Control API (called through a virtual interface by the HVL drive adapter)
  // ---------------------------------------------------------------------------

  // Accept a per-instance feature set; returns 0 and changes nothing when the set
  // is illegal for its protocol mode (CFG-01) or not implemented yet (CFG-02).
  function automatic bit configure(axi_features_t f);
    string problem;
    if (wr_in_flight || rd_in_flight) begin
      $error("%m: configure() while a transaction is in flight");
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

  // 1: drive the bus; 0: release every output to 'z
  function automatic void set_enable(bit en);
    if ((wr_in_flight || rd_in_flight) && !en)
      $error("%m: driver released while a transaction is in flight");
    drive_en = en;
  endfunction

  // Negative tests only: select a deliberate protocol fault (axi_fault_e). It stays
  // active for every following transaction, once per transaction, until set back
  // to AXI_FAULT_NONE. AXI_FAULT_RLAST_EARLY belongs to the Subordinate BFM and is
  // ignored here.
  function automatic void set_fault(axi_fault_e f);
    fault = f;
  endfunction

  // RST-5: return after ARESETn is sampled HIGH, plus idle_cycles more edges
  task automatic wait_for_reset_release(input int unsigned idle_cycles = 1);
    do
      @(cb);
    while (cb.ARESETn !== 1'b1);
    repeat (idle_cycles) @(cb);
  endtask

  // One write transaction of len beats (AXI-R02..R06). AWVALID rises addr_delay
  // edges after the call and WVALID of beat 0 data_delay[0] edges after it; beat
  // i >= 1 follows data_delay[i] edges after the handshake of beat i-1 (0 keeps
  // WVALID HIGH back to back). Neither channel waits for the other. Once the
  // address and the last data beat are accepted, BREADY is HIGH at once when
  // resp_ready_delay is 0, otherwise after BVALID has been seen HIGH for
  // resp_ready_delay cycles. Returns at the edge of the B handshake, after
  // scheduling idle outputs; a following call in the same time step overrides
  // them. Reports the BID/BRESP, the beats accepted and the cycles each VALID
  // waited for its READY (AWVALID, each WVALID, and BVALID waiting for BREADY).
  task automatic do_write(
    input  logic [ID_W_WIDTH-1:0]   id,
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  int unsigned             len,
    input  logic [2:0]              size,
    input  logic [1:0]              burst,
    input  logic                    lock,
    input  logic [3:0]              cache,
    input  logic [2:0]              prot,
    input  logic [3:0]              qos,
    input  logic [3:0]              region,
    input  logic [DATA_WIDTH-1:0]   wdata      [AXI_MAX_BEATS],
    input  logic [STRB_WIDTH-1:0]   wstrb      [AXI_MAX_BEATS],
    input  int unsigned             addr_delay,
    input  int unsigned             data_delay [AXI_MAX_BEATS],
    input  int unsigned             resp_ready_delay,
    input  int unsigned             max_wait_cycles,  // per stall; 0 = no watchdog
    output logic [ID_W_WIDTH-1:0]   bid,
    output logic [1:0]              bresp,
    output int unsigned             beats_done,
    output int unsigned             addr_wait,
    output int unsigned             data_wait  [AXI_MAX_BEATS],
    output int unsigned             resp_wait,
    output axi_bfm_status_e         status
  );
    axi_bfm_status_e st;
    bit              lite;
    bit              aw_on;         // AWVALID HIGH, waiting for AWREADY
    bit              aw_done;       // address handshake completed
    int unsigned     aw_left;       // edges until AWVALID rises
    bit              w_on;          // WVALID HIGH for beat w_idx
    bit              w_done;        // every beat accepted
    bit              w_dropped;     // fault mode 2: WVALID LOW for this one cycle
    int unsigned     w_idx;         // beat on (or next onto) the W channel
    int unsigned     w_left;        // edges until WVALID rises for beat w_idx
    bit              b_phase;       // address and data accepted: waiting for B
    bit              b_rdy;         // BREADY HIGH during the current cycle
    int unsigned     b_seen;        // cycles BVALID was HIGH without a handshake
    bit              progress;      // a handshake happened at this edge
    int unsigned     stall;         // consecutive edges waiting on the Subordinate
    bit              faulted;       // the one-shot fault of this transaction was applied
    logic [STRB_WIDTH-1:0] strb;    // strobe of the beat being presented

    bid        = '0;
    bresp      = 2'b00;
    beats_done = 0;
    addr_wait  = 0;
    resp_wait  = 0;
    foreach (data_wait[i]) data_wait[i] = 0;
    status     = AXI_ST_OK;

    // A request that cannot start leaves the bus untouched; status says why.
    if (!drive_en) begin
      status = AXI_ST_NOT_ENABLED;
      return;
    end
    lite = (features.protocol == AXI4_LITE);
    if (wr_in_flight || !shape_ok(len, size, burst, lite)) begin
      status = AXI_ST_BAD_REQUEST;
      return;
    end
    if (ARESETn !== 1'b1) begin
      status = AXI_ST_RESET_ABORTED;
      return;
    end

    // The BFM owns AW/W/B until the end of the task: configure() is refused and
    // set_enable(0) is reported as an error while in flight.
    wr_in_flight = 1'b1;
    st           = AXI_ST_OK;
    fork begin : guard  // isolates "disable fork" from the caller's processes
      fork
        begin : transfer
          aw_on     = 1'b0;
          aw_done   = 1'b0;
          aw_left   = addr_delay;
          w_on      = 1'b0;
          w_done    = 1'b0;
          w_dropped = 1'b0;
          w_idx     = 0;
          w_left    = data_delay[0];
          b_phase   = 1'b0;
          b_rdy     = 1'b0;
          b_seen    = 0;
          stall     = 0;
          faulted   = 1'b0;
          // A channel without delay starts in this time step (AXI-R05/R06).
          if (aw_left == 0) begin
            drive_aw(id, addr, len, size, burst, lock, cache, prot, qos, region, lite);
            aw_on = 1'b1;
          end
          if (w_left == 0) begin
            strb = beat_strobe(wstrb[0], addr, size, burst, len, 0,
                               fault == AXI_FAULT_WSTRB_OUTSIDE && !faulted);
            if (strb !== wstrb[0]) faulted = 1'b1;
            drive_w(wdata[0], strb, len == 1, lite);
            w_on = 1'b1;
          end
          forever begin
            @(cb);
            progress = 1'b0;

            // Write address channel: AWVALID and the payload stay unchanged until
            // the handshake (AXI-R03/R04).
            if (aw_on) begin
              if (cb.AWREADY === 1'b1) begin
                idle_aw();
                aw_on    = 1'b0;
                aw_done  = 1'b1;
                progress = 1'b1;
              end else begin
                addr_wait++;
                // Fault mode 1: move the waited address once (breaks AXI-R04).
                if (fault == AXI_FAULT_ADDR_UNSTABLE && !faulted) begin
                  awaddr_q <= awaddr_q ^ ADDR_WIDTH'(axi_size_bytes(size));
                  faulted   = 1'b1;
                end
              end
            end else if (!aw_done) begin
              aw_left--;
              if (aw_left == 0) begin
                drive_aw(id, addr, len, size, burst, lock, cache, prot, qos, region, lite);
                aw_on = 1'b1;
              end
            end

            // Write data channel: beat w_idx is held until WREADY (AXI-R03/R04).
            if (w_dropped) begin
              wvalid_q <= 1'b1;  // fault mode 2: the dropped beat comes back unchanged
              w_dropped = 1'b0;
              w_on      = 1'b1;
            end else if (w_on) begin
              if (cb.WREADY === 1'b1) begin
                beats_done++;
                progress = 1'b1;
                w_idx++;
                if (w_idx == len) begin
                  idle_w();
                  w_on   = 1'b0;
                  w_done = 1'b1;
                end else if (data_delay[w_idx] == 0) begin
                  strb = beat_strobe(wstrb[w_idx], addr, size, burst, len, w_idx,
                                     fault == AXI_FAULT_WSTRB_OUTSIDE && !faulted);
                  if (strb !== wstrb[w_idx]) faulted = 1'b1;
                  drive_w(wdata[w_idx], strb, w_idx == len - 1, lite);
                end else begin
                  idle_w();
                  w_on   = 1'b0;
                  w_left = data_delay[w_idx];
                end
              end else begin
                data_wait[w_idx]++;
                // Fault mode 2: drop WVALID for one cycle before its handshake (AXI-R03).
                if (fault == AXI_FAULT_VALID_DROP && !faulted) begin
                  wvalid_q <= 1'b0;
                  w_dropped = 1'b1;
                  w_on      = 1'b0;
                  faulted   = 1'b1;
                end
              end
            end else if (!w_done) begin
              w_left--;
              if (w_left == 0) begin
                strb = beat_strobe(wstrb[w_idx], addr, size, burst, len, w_idx,
                                   fault == AXI_FAULT_WSTRB_OUTSIDE && !faulted);
                if (strb !== wstrb[w_idx]) faulted = 1'b1;
                drive_w(wdata[w_idx], strb, w_idx == len - 1, lite);
                w_on = 1'b1;
              end
            end

            // Write response channel. A Subordinate may assert BVALID only after the
            // address and the last data beat were accepted (AXI-R06), so BREADY is
            // raised from the edge where both are done.
            if (b_phase) begin
              if (cb.BVALID === 1'b1) begin
                if (b_rdy) begin
                  bid       = cb.BID;   // 4-state, verbatim
                  bresp     = cb.BRESP;
                  bready_q <= 1'b0;
                  break;               // B handshake: the transaction is complete
                end
                resp_wait++;
                b_seen++;
                if (b_seen >= resp_ready_delay) begin
                  b_rdy     = 1'b1;
                  bready_q <= 1'b1;
                end
              end
            end else if (aw_done && w_done) begin
              b_phase   = 1'b1;
              b_rdy     = (resp_ready_delay == 0);
              bready_q <= b_rdy;
            end

            // Watchdog (POL-01): edges spent waiting on the Subordinate with no
            // handshake. The Manager's own delays do not count.
            if (progress)                                 stall = 0;
            else if (aw_on || w_on || w_dropped || b_phase) stall++;
            if (max_wait_cycles != 0 && stall >= max_wait_cycles) begin
              st = AXI_ST_TIMEOUT;  // the Subordinate is abandoned
              break;
            end
          end
        end
        begin : reset_watch  // RST-2/RST-3: abandon the transaction at the reset edge
          wait (ARESETn !== 1'b1);
          st = AXI_ST_RESET_ABORTED;
        end
      join_any
      disable fork;
    end join

    idle_write();
    if (st == AXI_ST_OK && axi_resp_is_error(bresp)) st = AXI_ST_ERROR;  // AXI-R16
    status       = st;
    wr_in_flight = 1'b0;
  endtask

  // One read transaction of len beats (AXI-R02..R05, R07). ARVALID rises
  // addr_delay edges after the call. RREADY is HIGH from the call when
  // resp_ready_delay is 0; otherwise it rises after RVALID has been seen HIGH for
  // resp_ready_delay cycles and falls after each beat. The read ends after len
  // beats; RLAST is not used for framing (the monitor checks it, AXI-R15).
  // Returns at the edge of the last R handshake. Per beat: RDATA and RRESP
  // (4-state, verbatim) and the cycles RVALID waited for RREADY.
  task automatic do_read(
    input  logic [ID_R_WIDTH-1:0]   id,
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  int unsigned             len,
    input  logic [2:0]              size,
    input  logic [1:0]              burst,
    input  logic                    lock,
    input  logic [3:0]              cache,
    input  logic [2:0]              prot,
    input  logic [3:0]              qos,
    input  logic [3:0]              region,
    input  int unsigned             addr_delay,
    input  int unsigned             resp_ready_delay,
    input  int unsigned             max_wait_cycles,  // per stall; 0 = no watchdog
    output logic [ID_R_WIDTH-1:0]   rid,
    output logic [DATA_WIDTH-1:0]   rdata      [AXI_MAX_BEATS],
    output logic [1:0]              rresp      [AXI_MAX_BEATS],
    output int unsigned             beats_done,
    output int unsigned             addr_wait,
    output int unsigned             data_wait  [AXI_MAX_BEATS],
    output axi_bfm_status_e         status
  );
    axi_bfm_status_e st;
    bit              lite;
    bit              ar_on;     // ARVALID HIGH, waiting for ARREADY
    bit              ar_done;   // address handshake completed
    int unsigned     ar_left;   // edges until ARVALID rises
    bit              r_rdy;     // RREADY HIGH during the current cycle
    int unsigned     r_seen;    // cycles the current beat's RVALID waited
    bit              progress;  // a handshake happened at this edge
    int unsigned     stall;     // consecutive edges waiting on the Subordinate
    bit              faulted;   // the one-shot fault of this transaction was applied
    bit              any_error;

    rid        = '0;
    beats_done = 0;
    addr_wait  = 0;
    foreach (rdata[i]) begin
      rdata[i]     = '0;
      rresp[i]     = 2'b00;
      data_wait[i] = 0;
    end
    status     = AXI_ST_OK;

    if (!drive_en) begin
      status = AXI_ST_NOT_ENABLED;
      return;
    end
    lite = (features.protocol == AXI4_LITE);
    if (rd_in_flight || !shape_ok(len, size, burst, lite)) begin
      status = AXI_ST_BAD_REQUEST;
      return;
    end
    if (ARESETn !== 1'b1) begin
      status = AXI_ST_RESET_ABORTED;
      return;
    end

    rd_in_flight = 1'b1;
    st           = AXI_ST_OK;
    fork begin : guard  // isolates "disable fork" from the caller's processes
      fork
        begin : transfer
          ar_on     = 1'b0;
          ar_done   = 1'b0;
          ar_left   = addr_delay;
          r_rdy     = (resp_ready_delay == 0);
          r_seen    = 0;
          stall     = 0;
          faulted   = 1'b0;
          rready_q <= r_rdy;  // a Manager may assert RREADY before RVALID (AXI-R05)
          if (ar_left == 0) begin
            drive_ar(id, addr, len, size, burst, lock, cache, prot, qos, region, lite);
            ar_on = 1'b1;
          end
          forever begin
            @(cb);
            progress = 1'b0;

            // Read address channel (AXI-R03/R04)
            if (ar_on) begin
              if (cb.ARREADY === 1'b1) begin
                idle_ar();
                ar_on    = 1'b0;
                ar_done  = 1'b1;
                progress = 1'b1;
              end else begin
                addr_wait++;
                // Fault mode 1: move the waited address once (breaks AXI-R04).
                if (fault == AXI_FAULT_ADDR_UNSTABLE && !faulted) begin
                  araddr_q <= araddr_q ^ ADDR_WIDTH'(axi_size_bytes(size));
                  faulted   = 1'b1;
                end
              end
            end else if (!ar_done) begin
              ar_left--;
              if (ar_left == 0) begin
                drive_ar(id, addr, len, size, burst, lock, cache, prot, qos, region, lite);
                ar_on = 1'b1;
              end
            end

            // Read data channel: a beat transfers at an edge where RVALID is HIGH
            // while RREADY was HIGH (AXI-R02).
            if (cb.RVALID === 1'b1) begin
              if (r_rdy) begin
                if (beats_done == 0) rid = cb.RID;
                rdata[beats_done] = cb.RDATA;  // 4-state, verbatim
                rresp[beats_done] = cb.RRESP;
                beats_done++;
                progress = 1'b1;
                r_seen   = 0;
                if (beats_done == len) break;  // last beat by count
                if (resp_ready_delay != 0) begin
                  r_rdy     = 1'b0;
                  rready_q <= 1'b0;
                end
              end else begin
                data_wait[beats_done]++;
                r_seen++;
                if (r_seen >= resp_ready_delay) begin
                  r_rdy     = 1'b1;
                  rready_q <= 1'b1;
                end
              end
            end

            // Watchdog (POL-01); the Manager's own address delay does not count.
            if (progress)                stall = 0;
            else if (ar_on || ar_done)   stall++;
            if (max_wait_cycles != 0 && stall >= max_wait_cycles) begin
              st = AXI_ST_TIMEOUT;
              break;
            end
          end
        end
        begin : reset_watch  // RST-2/RST-3
          wait (ARESETn !== 1'b1);
          st = AXI_ST_RESET_ABORTED;
        end
      join_any
      disable fork;
    end join

    idle_read();
    any_error = 1'b0;
    for (int unsigned i = 0; i < beats_done; i++)
      if (axi_resp_is_error(rresp[i])) any_error = 1'b1;
    if (st == AXI_ST_OK && any_error) st = AXI_ST_ERROR;  // AXI-R16
    status       = st;
    rd_in_flight = 1'b0;
  endtask

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  // 1 when the burst shape is legal and fits this bus: a known AxBURST with a
  // length legal for it (AXI-R08/R10), AxSIZE no wider than the bus (AXI-R09), and
  // on AXI4-Lite one beat of the full width (AXI-R24). The drive adapter checks the
  // remaining request rules (4KB, WRAP alignment, exclusive, AxCACHE, strobes).
  function automatic bit shape_ok(int unsigned len, logic [2:0] size, logic [1:0] burst,
                                  bit lite);
    if ($isunknown(size) || $isunknown(burst)) return 1'b0;
    if (!axi_burst_len_ok(burst, len)) return 1'b0;
    if (axi_size_bytes(size) > unsigned'(STRB_WIDTH)) return 1'b0;
    if (lite && (len != 1 || axi_size_bytes(size) != unsigned'(STRB_WIDTH))) return 1'b0;
    return 1'b1;
  endfunction

  // Strobe driven for beat i: the requested strobe, plus — when `inject` is set
  // (fault mode 3, once per transaction) — one lane outside the beat's active lanes
  // (breaks AXI-R14). A full beat has no lane outside, so the caller sees an
  // unchanged strobe and keeps the fault for a later narrow or unaligned beat.
  function automatic logic [STRB_WIDTH-1:0] beat_strobe(logic [STRB_WIDTH-1:0] strb,
                                                        logic [ADDR_WIDTH-1:0] addr,
                                                        logic [2:0]            size,
                                                        logic [1:0]            burst,
                                                        int unsigned           len,
                                                        int unsigned           i,
                                                        bit                    inject);
    logic [AXI_MAX_LANES-1:0] lanes;
    if (!inject) return strb;
    lanes = axi_lane_mask(axi_beat_addr(AXI_FN_AW'(addr), size, burst, len, i), size,
                          STRB_WIDTH);
    for (int unsigned l = 0; l < STRB_WIDTH; l++)
      if (lanes[l] == 1'b0) begin
        strb[l] = 1'b1;
        return strb;
      end
    return strb;
  endfunction

  // Schedule one write address with NBAs. AXI4-Lite has no ID, LEN, SIZE, BURST,
  // LOCK, CACHE, QOS or REGION signal: they are driven 0 (AXI-R24, POL-03).
  task automatic drive_aw(
    input logic [ID_W_WIDTH-1:0] id,
    input logic [ADDR_WIDTH-1:0] addr,
    input int unsigned           len,
    input logic [2:0]            size,
    input logic [1:0]            burst,
    input logic                  lock,
    input logic [3:0]            cache,
    input logic [2:0]            prot,
    input logic [3:0]            qos,
    input logic [3:0]            region,
    input bit                    lite
  );
    awvalid_q  <= 1'b1;
    awaddr_q   <= addr;
    awprot_q   <= prot;
    awid_q     <= lite ? '0     : id;
    awlen_q    <= lite ? 8'h00  : 8'(len - 1);  // AxLEN = beats - 1 (AXI-R08)
    awsize_q   <= lite ? 3'b000 : size;
    awburst_q  <= lite ? 2'b00  : burst;
    awlock_q   <= lite ? 1'b0   : lock;
    awcache_q  <= lite ? 4'h0   : cache;
    awqos_q    <= lite ? 4'h0   : qos;
    awregion_q <= lite ? 4'h0   : region;
  endtask

  // Schedule one read address with NBAs (same AXI4-Lite rule as drive_aw()).
  task automatic drive_ar(
    input logic [ID_R_WIDTH-1:0] id,
    input logic [ADDR_WIDTH-1:0] addr,
    input int unsigned           len,
    input logic [2:0]            size,
    input logic [1:0]            burst,
    input logic                  lock,
    input logic [3:0]            cache,
    input logic [2:0]            prot,
    input logic [3:0]            qos,
    input logic [3:0]            region,
    input bit                    lite
  );
    arvalid_q  <= 1'b1;
    araddr_q   <= addr;
    arprot_q   <= prot;
    arid_q     <= lite ? '0     : id;
    arlen_q    <= lite ? 8'h00  : 8'(len - 1);
    arsize_q   <= lite ? 3'b000 : size;
    arburst_q  <= lite ? 2'b00  : burst;
    arlock_q   <= lite ? 1'b0   : lock;
    arcache_q  <= lite ? 4'h0   : cache;
    arqos_q    <= lite ? 4'h0   : qos;
    arregion_q <= lite ? 4'h0   : region;
  endtask

  // Schedule one write data beat with NBAs; AXI4-Lite has no WLAST (AXI-R24).
  task automatic drive_w(
    input logic [DATA_WIDTH-1:0] data,
    input logic [STRB_WIDTH-1:0] strb,
    input bit                    last,
    input bit                    lite
  );
    wvalid_q <= 1'b1;
    wdata_q  <= data;
    wstrb_q  <= strb;
    wlast_q  <= lite ? 1'b0 : last;
  endtask

  // No write address on the bus: AWVALID LOW, payload 0 (POL-03)
  task automatic idle_aw();
    awvalid_q  <= 1'b0;
    awid_q     <= '0;
    awaddr_q   <= '0;
    awlen_q    <= 8'h00;
    awsize_q   <= 3'b000;
    awburst_q  <= 2'b00;
    awlock_q   <= 1'b0;
    awcache_q  <= 4'h0;
    awprot_q   <= 3'b000;
    awqos_q    <= 4'h0;
    awregion_q <= 4'h0;
  endtask

  // No write data on the bus: WVALID LOW, payload 0 (POL-03)
  task automatic idle_w();
    wvalid_q <= 1'b0;
    wdata_q  <= '0;
    wstrb_q  <= '0;
    wlast_q  <= 1'b0;
  endtask

  // No read address on the bus: ARVALID LOW, payload 0 (POL-03)
  task automatic idle_ar();
    arvalid_q  <= 1'b0;
    arid_q     <= '0;
    araddr_q   <= '0;
    arlen_q    <= 8'h00;
    arsize_q   <= 3'b000;
    arburst_q  <= 2'b00;
    arlock_q   <= 1'b0;
    arcache_q  <= 4'h0;
    arprot_q   <= 3'b000;
    arqos_q    <= 4'h0;
    arregion_q <= 4'h0;
  endtask

  // Write path idle (end of do_write, RST-1)
  task automatic idle_write();
    idle_aw();
    idle_w();
    bready_q <= 1'b0;
  endtask

  // Read path idle (end of do_read, RST-1)
  task automatic idle_read();
    idle_ar();
    rready_q <= 1'b0;
  endtask

  // RST-1/RST-2: every VALID and READY LOW as soon as reset asserts (or goes X/Z)
  always @(ARESETn)
    if (ARESETn !== 1'b1) begin
      idle_write();
      idle_read();
    end

  // Elaboration-time checks (widths must match the shared axi_if)
  if (DATA_WIDTH < 8 || DATA_WIDTH % 8 != 0) begin : g_bad_data_width
    $error("axi_manager_bfm_if: DATA_WIDTH=%0d is not a whole number of bytes", DATA_WIDTH);
  end
  if (ADDR_WIDTH < 1 || ADDR_WIDTH > AXI_FN_AW) begin : g_bad_addr_width
    $error("axi_manager_bfm_if: ADDR_WIDTH=%0d outside 1..%0d", ADDR_WIDTH, AXI_FN_AW);
  end
  if (STRB_WIDTH > AXI_MAX_LANES) begin : g_bad_lanes
    $error("axi_manager_bfm_if: DATA_WIDTH=%0d wider than 1024 bits", DATA_WIDTH);
  end

endinterface : axi_manager_bfm_if
