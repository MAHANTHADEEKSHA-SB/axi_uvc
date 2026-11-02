// -----------------------------------------------------------------------------
// axi_hdl_smoke — HDL-only directed smoke test (AXI-003a acceptance, no UVM)
//
// Runs the same directed transactions concurrently on instance A (DW=32) and
// instance B (DW=64) of axi_hdl_top, each on its own clock and reset, with
// the UVC's two roles facing each other: the runner drives the Manager BFM
// and answers the Subordinate BFM itself. Each instance is reached only
// through typed virtual BFM handles held by a width-parameterized class: the
// access pattern the HVL adapters use (RISK-001).
//
// Two memories keep the check independent of either capture path: the
// responder answers reads from the bytes the Subordinate BFM delivered
// (`held`), while the expected read data comes from the bytes the Manager
// sent (`sent`). Response windows as in the UVM POC: OKAY below 'h1000,
// SLVERR up to 'h2000, DECERR above.
//
// Checks per instance: single beats, INCR4, WRAP4, FIXED, a byte write merged
// into a word, an unaligned INCR, directed strobes, a 32-beat INCR, write data
// before its address, a write and a read in flight together, SLVERR, DECERR
// and an exclusive read. Manager results, read data and every published
// transaction are checked; the monitor must publish exactly the expected
// transactions, keep the channel order (AXI-R06/R07) and report no violation
// or open transaction. Instance B then runs a short AXI4-Lite phase on the
// same image (owner decision A-2). The Subordinate-side monitors and the
// passive observer P must agree (drive release).
//
// Negative control: +AXI_FAULT=<n> (axi_fault_e) injects a fault on instance
// A only. The test then passes only if A's monitors and P's monitor report the
// matching violation and instance B stays error-free (isolation).
//
// Result line: "SMOKE_RESULT: PASS" or "SMOKE_RESULT: FAIL".
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module axi_hdl_smoke;
  import axi_bfm_pkg::*;

  axi_hdl_top u_top ();

  // One runner per instance. It reaches its instance only through typed virtual
  // BFM handles, as the HVL adapters do (RISK-001).
  class smoke_runner #(int AW = 32, int DW = 32, int IW = 4, int IR = 4);
    typedef virtual axi_manager_bfm_if #(
      .ADDR_WIDTH (AW),
      .DATA_WIDTH (DW),
      .ID_W_WIDTH (IW),
      .ID_R_WIDTH (IR)
    ) mgr_vif_t;
    typedef virtual axi_subordinate_bfm_if #(
      .ADDR_WIDTH (AW),
      .DATA_WIDTH (DW),
      .ID_W_WIDTH (IW),
      .ID_R_WIDTH (IR)
    ) sub_vif_t;
    typedef virtual axi_monitor_bfm_if #(
      .ADDR_WIDTH (AW),
      .DATA_WIDTH (DW),
      .ID_W_WIDTH (IW),
      .ID_R_WIDTH (IR)
    ) mon_vif_t;

    localparam int              SW           = DW / 8;
    localparam int              IDM          = (IW > IR) ? IW : IR;
    localparam int unsigned     NB           = AXI_MAX_BEATS;
    localparam longint unsigned OKAY_BYTES   = 'h1000;
    localparam longint unsigned SLVERR_BYTES = 'h1000;
    localparam logic [63:0]     P1           = 64'hA5A5_5A5A_DEAD_BEEF;
    localparam logic [63:0]     P2           = 64'h0123_4567_89AB_CDEF;
    localparam logic [63:0]     P3           = 64'hFEDC_BA98_7654_3210;
    localparam logic [63:0]     P4           = 64'h1357_9BDF_2468_ACE0;

    // One expected monitor observation
    typedef struct {
      logic [AW-1:0]  addr;
      logic [IDM-1:0] id;
      int unsigned    len;
      logic [2:0]     size;
      logic [1:0]     burst;
      logic [DW-1:0]  data [NB];
      logic [SW-1:0]  strb [NB];
      logic [1:0]     resp [NB];  // RRESP per beat of a read; BRESP in resp[0] of a write
    } exp_t;

    string        name;
    mgr_vif_t     mgr;
    sub_vif_t     sub;
    mon_vif_t     mon;
    axi_fault_e   fault;
    int unsigned  aw_ready_delay;
    int unsigned  w_ready_delay;
    int unsigned  ar_ready_delay;
    int unsigned  failures;
    int unsigned  responses;      // responses handed to the Subordinate BFM
    int unsigned  observed;       // monitor observations checked so far
    exp_t         exp_wr_q[$];
    exp_t         exp_rd_q[$];
    byte unsigned sent[longint unsigned];  // bytes the Manager wrote with OKAY
    byte unsigned held[longint unsigned];  // bytes the responder stored from the Subordinate

    function new(string name, mgr_vif_t mgr, sub_vif_t sub, mon_vif_t mon, axi_fault_e fault,
                 int unsigned aw_ready_delay, int unsigned w_ready_delay,
                 int unsigned ar_ready_delay);
      this.name           = name;
      this.mgr            = mgr;
      this.sub            = sub;
      this.mon            = mon;
      this.fault          = fault;
      this.aw_ready_delay = aw_ready_delay;
      this.w_ready_delay  = w_ready_delay;
      this.ar_ready_delay = ar_ready_delay;
    endfunction

    // Record one failed expectation; the run continues so every problem is reported.
    function void check(bit ok, string msg);
      if (!ok) begin
        failures++;
        $display("SMOKE_FAIL [%s] %s", name, msg);
      end
    endfunction

    // AxSIZE for `bytes` bytes per beat; 0 selects the full bus width.
    function logic [2:0] size_code(int unsigned bytes);
      int unsigned b = (bytes == 0) ? SW : bytes;
      for (int unsigned k = 0; k < 8; k++)
        if ((32'd1 << k) == b) return 3'(k);
      return 3'b000;
    endfunction

    // Data word of beat i: pattern p plus i in every byte
    function logic [DW-1:0] pattern(logic [63:0] p, int unsigned i);
      return DW'(p + 64'h0101_0101_0101_0101 * 64'(i));
    endfunction

    // Response window of an address (the fixture policy of this smoke test)
    function logic [1:0] window(logic [AW-1:0] a);
      if (AXI_FN_AW'(a) < OKAY_BYTES)                return AXI_RESP_OKAY;
      if (AXI_FN_AW'(a) < OKAY_BYTES + SLVERR_BYTES) return AXI_RESP_SLVERR;
      return AXI_RESP_DECERR;
    endfunction

    // More severe of two responses (DECERR over SLVERR over OKAY)
    function logic [1:0] worse(logic [1:0] a, logic [1:0] b);
      if (a == AXI_RESP_DECERR || b == AXI_RESP_DECERR) return AXI_RESP_DECERR;
      if (a == AXI_RESP_SLVERR || b == AXI_RESP_SLVERR) return AXI_RESP_SLVERR;
      return AXI_RESP_OKAY;
    endfunction

    // Address of beat i (IHI 0022 "Burst address", shared arithmetic)
    function logic [AW-1:0] beat_addr(logic [AW-1:0] addr, logic [2:0] size, logic [1:0] burst,
                                      int unsigned len, int unsigned i);
      return AW'(axi_beat_addr(AXI_FN_AW'(addr), size, burst, len, i));
    endfunction

    // Active byte lanes of a beat at address a (AXI-R13)
    function logic [SW-1:0] beat_lanes(logic [AW-1:0] a, logic [2:0] size);
      logic [AXI_MAX_LANES-1:0] m;
      m = axi_lane_mask(AXI_FN_AW'(a), size, SW);
      return m[SW-1:0];
    endfunction

    // Store the strobed bytes of one beat at address a into memory model m
    function void store(ref byte unsigned m[longint unsigned], input logic [AW-1:0] a,
                        input logic [DW-1:0] data, input logic [SW-1:0] strb);
      longint unsigned base = AXI_FN_AW'(a) - (AXI_FN_AW'(a) % SW);
      for (int unsigned l = 0; l < SW; l++)
        if (strb[l] === 1'b1) m[base + l] = data[8*l +: 8];
    endfunction

    // Word a read of the beat at a returns from model m: the bytes on the lanes,
    // zero elsewhere and for bytes never written
    function logic [DW-1:0] load(ref byte unsigned m[longint unsigned], input logic [AW-1:0] a,
                                 input logic [SW-1:0] lanes);
      logic [DW-1:0]   w    = '0;
      longint unsigned base = AXI_FN_AW'(a) - (AXI_FN_AW'(a) % SW);
      for (int unsigned l = 0; l < SW; l++)
        if (lanes[l] && m.exists(base + l)) w[8*l +: 8] = m[base + l];
      return w;
    endfunction

    // The Subordinate side: answer every request in order from `held` and the
    // windows. B delays cycle through 0..2 and R beat delays through 0..1, so the
    // timing varies but stays deterministic.
    task automatic respond_forever();
      bit              write;
      logic [IDM-1:0]  id;
      logic [AW-1:0]   addr;
      int unsigned     len;
      logic [2:0]      size;
      logic [1:0]      burst;
      logic            lock;
      logic [3:0]      cache;
      logic [2:0]      prot;
      logic [3:0]      qos;
      logic [3:0]      region;
      int unsigned     beats;
      logic [DW-1:0]   wdata [NB];
      logic [SW-1:0]   wstrb [NB];
      longint unsigned req_cycle;
      int unsigned     req_epoch;
      logic [DW-1:0]   rdata [NB];
      logic [1:0]      rresp [NB];
      int unsigned     delay [NB];
      logic [1:0]      resp;
      logic [AW-1:0]   a;
      axi_bfm_status_e st;
      forever begin
        sub.get_request(write, id, addr, len, size, burst, lock, cache, prot, qos, region, beats,
                        wdata, wstrb, req_cycle, req_epoch);
        if (write) begin
          resp = AXI_RESP_OKAY;
          for (int unsigned i = 0; i < len; i++)
            resp = worse(resp, window(beat_addr(addr, size, burst, len, i)));
          if (resp == AXI_RESP_OKAY)
            for (int unsigned i = 0; i < beats && i < len; i++) begin
              a = beat_addr(addr, size, burst, len, i);
              store(held, a, wdata[i], wstrb[i] & beat_lanes(a, size));
            end
          st = sub.put_write_response(req_epoch, IW'(id), resp, responses % 3);
        end else begin
          for (int unsigned i = 0; i < NB; i++) begin
            rdata[i] = '0;
            rresp[i] = AXI_RESP_OKAY;
            delay[i] = 0;
            if (i < len) begin
              a        = beat_addr(addr, size, burst, len, i);
              rresp[i] = window(a);
              delay[i] = i % 2;
              if (rresp[i] == AXI_RESP_OKAY) rdata[i] = load(held, a, beat_lanes(a, size));
            end
          end
          st = sub.put_read_response(req_epoch, IR'(id), len, rdata, rresp, delay);
        end
        responses++;
        check(st == AXI_ST_OK,
              $sformatf("Subordinate BFM refused response %0d: %s", responses, st.name()));
      end
    endtask

    // One write through the Manager BFM. Beat i > 0 follows i % 2 edges after the
    // previous one; BREADY waits len % 3 cycles. In positive mode: the expected
    // response, the bytes sent (OKAY only), the Manager's result and the
    // observation the monitor must publish.
    task automatic write(logic [AW-1:0] addr, logic [1:0] burst, int unsigned bytes,
                         int unsigned len, logic [63:0] seed, logic [IDM-1:0] id,
                         int unsigned addr_delay = 0, logic [SW-1:0] strb0 = '1);
      logic [DW-1:0]   wdata [NB];
      logic [SW-1:0]   wstrb [NB];
      int unsigned     ddly  [NB];
      int unsigned     dwait [NB];
      logic [IW-1:0]   bid;
      logic [1:0]      bresp;
      int unsigned     done;
      int unsigned     awt;
      int unsigned     bwt;
      axi_bfm_status_e st;
      exp_t            e;
      logic [2:0]      sz;
      logic [1:0]      want;

      sz = size_code(bytes);
      for (int unsigned i = 0; i < NB; i++) begin
        wdata[i] = '0;
        wstrb[i] = '0;
        ddly[i]  = 0;
        if (i < len) begin
          wdata[i] = pattern(seed, i);
          wstrb[i] = beat_lanes(beat_addr(addr, sz, burst, len, i), sz);
          ddly[i]  = (i == 0) ? 0 : i % 2;
        end
      end
      wstrb[0] = wstrb[0] & strb0;
      mgr.do_write(IW'(id), addr, len, sz, burst, 1'b0, 4'h0, 3'b000, 4'h0, 4'h0, wdata, wstrb,
                   addr_delay, ddly, len % 3, 64, bid, bresp, done, awt, dwait, bwt, st);
      if (fault != AXI_FAULT_NONE) return;  // only the monitor verdict matters

      want = AXI_RESP_OKAY;
      for (int unsigned i = 0; i < len; i++)
        want = worse(want, window(beat_addr(addr, sz, burst, len, i)));
      if (want == AXI_RESP_OKAY)
        for (int unsigned i = 0; i < len; i++)
          store(sent, beat_addr(addr, sz, burst, len, i), wdata[i], wstrb[i]);
      check(st == ((want == AXI_RESP_OKAY) ? AXI_ST_OK : AXI_ST_ERROR),
            $sformatf("write @%0h: status %s", addr, st.name()));
      check(bresp === want, $sformatf("write @%0h: BRESP %b, expected %b", addr, bresp, want));
      check(done == len, $sformatf("write @%0h: %0d beats done of %0d", addr, done, len));
      check(bid === IW'(id), $sformatf("write @%0h: BID %0h, expected %0h", addr, bid, id));

      e.addr  = addr;
      e.id    = id;
      e.len   = len;
      e.size  = sz;
      e.burst = burst;
      for (int unsigned i = 0; i < NB; i++) begin
        e.data[i] = wdata[i];
        e.strb[i] = wstrb[i];
        e.resp[i] = 2'b00;
      end
      e.resp[0] = want;
      exp_wr_q.push_back(e);
    endtask

    // One read through the Manager BFM; RREADY waits len % 2 cycles per beat. In
    // positive mode every beat's response and data are checked against the windows
    // and the bytes sent, and the observation is queued for the monitor check.
    task automatic read(logic [AW-1:0] addr, logic [1:0] burst, int unsigned bytes,
                        int unsigned len, logic [IDM-1:0] id, logic lock = 1'b0);
      logic [IR-1:0]   rid;
      logic [DW-1:0]   rdata [NB];
      logic [1:0]      rresp [NB];
      int unsigned     dwait [NB];
      int unsigned     done;
      int unsigned     awt;
      axi_bfm_status_e st;
      exp_t            e;
      logic [2:0]      sz;
      logic [AW-1:0]   a;
      logic [1:0]      want;
      logic [DW-1:0]   data;
      bit              any_error;

      sz = size_code(bytes);
      mgr.do_read(IR'(id), addr, len, sz, burst, lock, 4'h0, 3'b000, 4'h0, 4'h0, 0, len % 2,
                  64, rid, rdata, rresp, done, awt, dwait, st);
      if (fault != AXI_FAULT_NONE) return;

      e.addr    = addr;
      e.id      = id;
      e.len     = len;
      e.size    = sz;
      e.burst   = burst;
      any_error = 1'b0;
      for (int unsigned i = 0; i < NB; i++) begin
        e.data[i] = '0;
        e.strb[i] = '0;
        e.resp[i] = 2'b00;
        if (i < len) begin
          a    = beat_addr(addr, sz, burst, len, i);
          want = window(a);
          data = '0;
          if (want == AXI_RESP_OKAY) data = load(sent, a, beat_lanes(a, sz));
          else                       any_error = 1'b1;
          check(rresp[i] === want,
                $sformatf("read @%0h beat %0d: RRESP %b, expected %b", addr, i, rresp[i], want));
          check(rdata[i] === data,
                $sformatf("read @%0h beat %0d: rdata %0h, expected %0h", addr, i, rdata[i], data));
          e.data[i] = data;
          e.resp[i] = want;
        end
      end
      check(st == (any_error ? AXI_ST_ERROR : AXI_ST_OK),
            $sformatf("read @%0h: status %s", addr, st.name()));
      check(done == len, $sformatf("read @%0h: %0d beats done of %0d", addr, done, len));
      check(rid === IR'(id), $sformatf("read @%0h: RID %0h, expected %0h", addr, rid, id));
      exp_rd_q.push_back(e);
    endtask

    // Configure every BFM of the instance (AXI4 defaults), enable both roles, start
    // the responder, run the directed list, then check the monitor (positive mode)
    // or the injected fault.
    task automatic run();
      axi_features_t f = axi_default_features();
      check(mgr.configure(f), "Manager configure() rejected the default features");
      check(sub.configure(f), "Subordinate configure() rejected the default features");
      check(mon.configure(f), "monitor configure() rejected the default features");
      mon.set_publish(1'b1);
      mgr.set_fault(fault);
      sub.set_fault(fault);
      sub.set_ready_delays(aw_ready_delay, w_ready_delay, ar_ready_delay);
      mgr.set_enable(1'b1);
      sub.set_enable(1'b1);
      fork
        respond_forever();
      join_none
      mgr.wait_for_reset_release(1);

      //    addr     burst            bytes len seed id  addr_delay strobe of beat 0
      write('h000,  AXI_BURST_INCR,  0,    1,  P1,  0);                    // single beat
      read ('h000,  AXI_BURST_INCR,  0,    1,       0);
      write('h040,  AXI_BURST_INCR,  0,    4,  P2,  1);                    // INCR4
      read ('h040,  AXI_BURST_INCR,  0,    4,       1);
      write('h088,  AXI_BURST_WRAP,  0,    4,  P3,  2);                    // WRAP4 wraps
      read ('h088,  AXI_BURST_WRAP,  0,    4,       2);
      write('h0A0,  AXI_BURST_FIXED, 0,    4,  P4,  3);                    // FIXED x4
      read ('h0A0,  AXI_BURST_INCR,  0,    1,       3);                    // last beat stays
      write('h110,  AXI_BURST_INCR,  0,    1,  P1,  0);
      write('h111,  AXI_BURST_INCR,  1,    1,  '1,  0);                    // byte lane 1
      read ('h110,  AXI_BURST_INCR,  0,    1,       0);                    // merged word
      write('h0C2,  AXI_BURST_INCR,  0,    3,  P2,  1);                    // unaligned start
      read ('h0C0,  AXI_BURST_INCR,  0,    3,       1);
      write('h0E0,  AXI_BURST_INCR,  0,    1,  P3,  2,  0, {SW/2{2'b01}}); // every other lane
      read ('h0E0,  AXI_BURST_INCR,  0,    1,       2);
      write('h200,  AXI_BURST_INCR,  0,    32, P4,  3);                    // 32 beats
      read ('h200,  AXI_BURST_INCR,  0,    32,      3);
      write('h300,  AXI_BURST_INCR,  0,    2,  P1,  0,  3);                // data before address
      fork                                                               // both directions at once
        write('h340, AXI_BURST_INCR, 0,    4,  P2,  1);
        read ('h040, AXI_BURST_INCR, 0,    4,       2);
      join
      read ('h1000, AXI_BURST_INCR,  0,    2,       0);                    // SLVERR window
      write('h2000, AXI_BURST_INCR,  0,    2,  P3,  1);                    // DECERR window
      read ('h000,  AXI_BURST_INCR,  0,    1,       2,  1'b1);             // exclusive: OKAY

      if (fault != AXI_FAULT_NONE) check_fault_detected();
      else                         check_monitor();
    endtask

    // Instance B only: the same BFMs reconfigured to AXI4-Lite (owner decision A-2),
    // full-width single beats with strobes, SLVERR and DECERR, then the monitor check.
    task automatic run_lite();
      axi_features_t f = axi_default_features();
      f.protocol = AXI4_LITE;
      check(mgr.configure(f), "Manager configure() rejected AXI4-Lite");
      check(sub.configure(f), "Subordinate configure() rejected AXI4-Lite");
      check(mon.configure(f), "monitor configure() rejected AXI4-Lite");
      //    addr     burst           bytes len seed id  addr_delay strobe of beat 0
      write('h000,  AXI_BURST_INCR, 0,    1,  P2,  0);
      read ('h000,  AXI_BURST_INCR, 0,    1,       0);
      write('h010,  AXI_BURST_INCR, 0,    1,  P3,  0);
      write('h010,  AXI_BURST_INCR, 0,    1,  P4,  0,  0, SW'(8'b0000_0110));  // lanes 1-2
      read ('h010,  AXI_BURST_INCR, 0,    1,       0);
      read ('h1000, AXI_BURST_INCR, 0,    1,       0);                     // SLVERR
      write('h2000, AXI_BURST_INCR, 0,    1,  P1,  0);                     // DECERR
      check_monitor();
    endtask

    // Negative mode: pass only if the violation matching the injected fault was counted.
    task automatic check_fault_detected();
      axi_mon_error_e want = axi_fault_error(fault);
      repeat (4) @(posedge mgr.ACLK);
      check(mon.get_error_count(want) > 0,
            $sformatf("injected %s NOT detected (%s count is 0)", fault.name(), want.name()));
      $display("SMOKE_INFO [%s] fault %s -> monitor %s count=%0d, total errors=%0d",
               name, fault.name(), want.name(), mon.get_error_count(want),
               mon.get_total_errors());
    endtask

    // Positive mode: each expected transaction observed once, per direction in
    // order, with matching address, control, data, strobes and responses, and the
    // channel order of AXI-R06/R07; nothing extra published, nothing left open.
    task automatic check_monitor();
      bit              write;
      logic [IDM-1:0]  id;
      logic [AW-1:0]   addr;
      int unsigned     len;
      logic [2:0]      size;
      logic [1:0]      burst;
      logic            lock;
      logic [3:0]      cache;
      logic [2:0]      prot;
      logic [3:0]      qos;
      logic [3:0]      region;
      int unsigned     beats;
      logic [DW-1:0]   data  [NB];
      logic [SW-1:0]   strb  [NB];
      logic [1:0]      resp  [NB];
      int unsigned     addr_wait;
      int unsigned     dwait [NB];
      int unsigned     resp_wait;
      longint unsigned addr_cycle;
      longint unsigned first_cycle;
      longint unsigned last_cycle;
      longint unsigned resp_cycle;
      exp_t            e;
      int unsigned     pending;

      // Drain the expected observations first: the Manager BFM returns at the
      // handshake edge, possibly before the monitor has sampled that edge.
      pending = exp_wr_q.size() + exp_rd_q.size();
      repeat (pending) begin
        mon.get_txn(write, id, addr, len, size, burst, lock, cache, prot, qos, region, beats,
                    data, strb, resp, addr_wait, dwait, resp_wait, addr_cycle, first_cycle,
                    last_cycle, resp_cycle);
        observed++;
        if ((write && exp_wr_q.size() == 0) || (!write && exp_rd_q.size() == 0)) begin
          check(1'b0, $sformatf("unexpected %s @%0h published", write ? "write" : "read", addr));
          continue;
        end
        if (write) e = exp_wr_q.pop_front();
        else       e = exp_rd_q.pop_front();
        check(addr === e.addr && id === e.id && len == e.len && size === e.size &&
              burst === e.burst,
              $sformatf("%s @%0h id=%0h len=%0d size=%0d burst=%0d, expected @%0h id=%0h len=%0d",
                        write ? "WR" : "RD", addr, id, len, size, burst, e.addr, e.id, e.len));
        check(beats == e.len, $sformatf("@%0h: %0d beats recorded, expected %0d", addr, beats,
                                        e.len));
        for (int unsigned i = 0; i < e.len && i < NB; i++) begin
          check(data[i] === e.data[i], $sformatf("@%0h beat %0d: data %0h, expected %0h", addr,
                                                 i, data[i], e.data[i]));
          if (write)
            check(strb[i] === e.strb[i], $sformatf("@%0h beat %0d: strobe %b, expected %b",
                                                   addr, i, strb[i], e.strb[i]));
          else
            check(resp[i] === e.resp[i], $sformatf("@%0h beat %0d: RRESP %b, expected %b",
                                                   addr, i, resp[i], e.resp[i]));
        end
        if (write) begin
          check(resp[0] === e.resp[0], $sformatf("@%0h: BRESP %b, expected %b", addr, resp[0],
                                                 e.resp[0]));
          // AXI-R06: B after the address and the last data transfer
          check(resp_cycle > addr_cycle && resp_cycle > last_cycle,
                $sformatf("@%0h: B@%0d not after AW@%0d and WLAST@%0d", addr, resp_cycle,
                          addr_cycle, last_cycle));
        end else begin
          // AXI-R07: read data after the address transfer
          check(first_cycle > addr_cycle,
                $sformatf("@%0h: first R@%0d not after AR@%0d", addr, first_cycle, addr_cycle));
        end
      end

      // Nothing extra may be published afterwards, and nothing may stay open
      repeat (4) @(posedge mgr.ACLK);
      check(mon.transfer_count == observed,
            $sformatf("monitor completed %0d transactions, expected %0d", mon.transfer_count,
                      observed));
      check(mon.get_total_errors() == 0,
            $sformatf("monitor reported %0d protocol errors", mon.get_total_errors()));
      check(mon.get_open_count() == 0,
            $sformatf("%0d transactions left open", mon.get_open_count()));
      $display("SMOKE_INFO [%s] %0d transactions checked, monitor errors=%0d",
               name, observed, mon.get_total_errors());
    endtask
  endclass : smoke_runner

  smoke_runner #(32, 32, 4, 4) run_a;
  smoke_runner #(40, 64, 6, 5) run_b;

  // Main: one runner per instance, run concurrently (A with READY back-pressure,
  // B default-ready); then B's AXI4-Lite phase; then the other monitors of each
  // bus (Subordinate side and passive P) and the result line.
  initial begin
    axi_fault_e     fault_a;
    int unsigned    fault_arg;
    axi_mon_error_e want;
    axi_features_t  lite;
    bit             others_ok;
    bit             pass;

    fault_a = AXI_FAULT_NONE;
    if ($value$plusargs("AXI_FAULT=%d", fault_arg)) fault_a = axi_fault_e'(fault_arg);

    run_a = new("A DW=32", u_top.mgr_a, u_top.sub_a, u_top.mon_a_mgr, fault_a, 1, 1, 2);
    run_b = new("B DW=64", u_top.mgr_b, u_top.sub_b, u_top.mon_b_mgr, AXI_FAULT_NONE, 0, 0, 0);

    fork
      run_a.run();
      run_b.run();
    join

    // Same image, bus B in AXI4-Lite mode; its Subordinate-side monitor follows.
    lite          = axi_default_features();
    lite.protocol = AXI4_LITE;
    run_b.check(u_top.mon_b_sub.configure(lite), "mon_b_sub rejected AXI4-Lite");
    run_b.run_lite();

    // The Subordinate-side monitors and P keep their default configuration (P and
    // mon_a_sub AXI4, like bus A) and must agree with the checked monitors.
    if (fault_a == AXI_FAULT_NONE) begin
      others_ok = (u_top.mon_a_sub.transfer_count == u_top.mon_a_mgr.transfer_count) &&
                  (u_top.mon_p.transfer_count == u_top.mon_a_mgr.transfer_count) &&
                  (u_top.mon_a_sub.get_total_errors() == 0) &&
                  (u_top.mon_p.get_total_errors() == 0);
    end else begin
      want      = axi_fault_error(fault_a);
      others_ok = (u_top.mon_a_sub.get_error_count(want) > 0) &&
                  (u_top.mon_p.get_error_count(want) > 0);
    end
    others_ok = others_ok &&
                (u_top.mon_b_sub.transfer_count == u_top.mon_b_mgr.transfer_count) &&
                (u_top.mon_b_sub.get_total_errors() == 0);
    if (!others_ok)
      $display("SMOKE_FAIL [other monitors] A sub=%0d/%0d err, P=%0d/%0d err, B sub=%0d/%0d err",
               u_top.mon_a_sub.transfer_count, u_top.mon_a_sub.get_total_errors(),
               u_top.mon_p.transfer_count, u_top.mon_p.get_total_errors(),
               u_top.mon_b_sub.transfer_count, u_top.mon_b_sub.get_total_errors());

    pass = (run_a.failures == 0) && (run_b.failures == 0) && others_ok;
    $display("SMOKE_SUMMARY mode=%s A.failures=%0d B.failures=%0d B.monitor_errors=%0d",
             fault_a.name(), run_a.failures, run_b.failures, u_top.mon_b_mgr.get_total_errors());
    $display("SMOKE_RESULT: %s", pass ? "PASS" : "FAIL");
    $finish;
  end

  // Watchdog: report a hang as a failure.
  initial begin
    #2ms;
    $display("SMOKE_RESULT: FAIL (watchdog timeout)");
    $finish;
  end

endmodule : axi_hdl_smoke
