# AXI protocol contract — AXI-001 (single AXI UVC POC)

**Status:** PROPOSED — written with the M1 sources on 2026-11-01; every open choice is listed in §12 (Q1–Q7) for owner review. The sources elaborate with slang (approved T1/T3, 0 diagnostics in the AXI sources); nothing has been simulated (§11).
**Date:** 2026-11-01
**Task:** AXI-001 (`WORK_STATUS.md`)
**Normative source:** Arm *AMBA AXI Protocol Specification*, ARM IHI 0022, referred to below as **[IHI]**. Manager/Subordinate terminology is used since Issue H.b (January 2021); Issue K (September 2023) and Issue L (August 2025) are the latest issues the authoring session found. The PDF is Arm copyright and is not stored in this repository.

**Citation note (RISK-013):** the PDF was not available to the authoring session and `documentation-service.arm.com` was blocked by its network policy. Rules are therefore cited by **section title**, which may differ between issues. Facts marked ✓ were confirmed through secondary sources during the session (Arm community answers, the AMD PG101 and Intel AXI4 protocol-checker documentation that restate the Arm assertions); no section number is given. A reviewer with the PDF must confirm every title, add the numbers and correct any rule whose wording differs.

## How to read this document

Every rule carries one of three tags. Only **[IHI …]** rules are protocol requirements.

| Tag | Meaning |
|---|---|
| **[IHI "title"]** | Requirement or definition taken from the named section of IHI 0022 |
| **[ASSUMPTION]** | Our proposed default where the specification is silent, or where its wording was not verified; must be approved, may change |
| **[DECISION]** | Project decision already taken by the repository owner (`DECISION_LOG.md`) |

---

## 1. Protocol strategy

- **[DECISION D-001]** The AXI UVC follows the APB/AHB UVC architecture and rules; protocol-specific choices of APB and AHB do not carry over.
- **[DECISION A-1]** Both sides of the bus are UVC roles: a **Manager** agent and a **Subordinate** agent, plus passive observation.
- **[DECISION A-2]** **AXI4** (full) is the protocol; **AXI4-Lite** stays supported as a **configuration mode** of the same UVC, not as a separate implementation.
- **[ASSUMPTION, Q1]** AXI3 (4-bit AxLEN, WID, locked transactions), AXI5 interface properties (atomics, poison, wake-up, untranslated transactions, MTE, MPAM, MEC, data check, trace, loopback, unique ID …), ACE and the low-power interface are **out of scope** until the owner asks for them.

### Mechanism (implemented)

1. `axi_if` declares the **AXI4 pin superset** of the five channels (§2.1), which contains the AXI4-Lite signals. Widths remain SV parameters, so this is not the "maximum-footprint interface" rejected by ADR-001; only optional signals are a superset.
2. **The protocol mode is per-instance runtime configuration** in `axi_agent_cfg.features` (`axi_bfm_pkg::axi_features_t`: protocol + user widths), validated against §2.3 before the run phase. The same compiled image can drive an AXI4 and an AXI4-Lite bus (`axi_lite_test`, smoke phase on bus B).
3. The feature set is pushed to every BFM through the proxies (`configure()` at start of simulation), so the HDL drive/sample code knows which signals are live.
4. Absent outputs (the AXI4-Lite subset, M2 user signals) are driven to 0; absent inputs are ignored (POL-03).

---

## 2. Signal / property legality matrix

### 2.1 Interface signals [IHI "Signal descriptions"]

Source: M = Manager output, S = Subordinate output. The monitor BFM sees every signal.

| Channel | Signal | Width | Src | AXI4 | AXI4-Lite | Milestone |
|---|---|---|---|---|---|---|
| global | `ACLK`, `ARESETn` | 1 | — | Y | Y | M1 |
| AW | `AWID` | `ID_W_WIDTH` | M | Y | N | M1 |
| AW | `AWADDR` | `ADDR_WIDTH` | M | Y | Y | M1 |
| AW | `AWLEN`, `AWSIZE`, `AWBURST` | 8, 3, 2 | M | Y | N | M1 |
| AW | `AWLOCK` | 1 | M | Y (exclusive) | N | M1 |
| AW | `AWCACHE`, `AWPROT`, `AWQOS`, `AWREGION` | 4, 3, 4, 4 | M | Y | only `AWPROT` | M1 |
| AW | `AWUSER` | `USER_REQ_WIDTH` | M | optional | N | M2 |
| AW | `AWVALID` / `AWREADY` | 1 | M / S | Y | Y | M1 |
| W | `WDATA`, `WSTRB` | `DATA_WIDTH`, `DATA_WIDTH/8` | M | Y | Y | M1 |
| W | `WLAST` | 1 | M | Y | N | M1 |
| W | `WUSER` | `USER_DATA_WIDTH` | M | optional | N | M2 |
| W | `WVALID` / `WREADY` | 1 | M / S | Y | Y | M1 |
| B | `BID` | `ID_W_WIDTH` | S | Y | N | M1 |
| B | `BRESP` | 2 | S | Y | Y | M1 |
| B | `BUSER` | `USER_RESP_WIDTH` | S | optional | N | M2 |
| B | `BVALID` / `BREADY` | 1 | S / M | Y | Y | M1 |
| AR | as AW, with `ARID` of `ID_R_WIDTH` and `ARUSER` | | M | Y | `ARADDR`, `ARPROT` | M1 (user M2) |
| AR | `ARVALID` / `ARREADY` | 1 | M / S | Y | Y | M1 |
| R | `RID` | `ID_R_WIDTH` | S | Y | N | M1 |
| R | `RDATA`, `RRESP` | `DATA_WIDTH`, 2 | S | Y | Y | M1 |
| R | `RLAST` | 1 | S | Y | N | M1 |
| R | `RUSER` | `USER_DATA_WIDTH` | S | optional | N | M2 |
| R | `RVALID` / `RREADY` | 1 | S / M | Y | Y | M1 |

The ID and user signals exist physically with a width of at least 1 (an SV vector cannot be empty); their absence is configuration.

### 2.2 Optional and later properties

User signals are milestone M2: the pins exist, enabled BFMs drive them 0, and `axi_agent_cfg` rejects user widths other than 0 (CFG-02). AXI5 properties are not declared (Q1).

### 2.3 Configuration legality checks (`axi_agent_cfg::legality_error()` / `validate()`)

`validate()` fails with `uvm_fatal` when any of these is true; `legality_error()` returns the same verdict as text (prefix = the ID) for `axi_cfg_negative_test`.

| ID | Illegal configuration | Source |
|---|---|---|
| CFG-01 | AXI4-Lite with `DATA_WIDTH` other than 32 or 64, or with user signals | [IHI "AXI4-Lite"] |
| CFG-02 | User signals before milestone M2 | project milestone limit |
| CFG-03 | `ADDR_WIDTH` outside 1..64 | [ASSUMPTION] UVC limit (64-bit address arithmetic, `AXI_FN_AW`) |
| CFG-04 | `DATA_WIDTH` not in {8, 16, 32, 64, 128, 256, 512, 1024} | [IHI "Data read and write structure"] |
| CFG-05 | Bus wider than the transaction maxima (`AXI_MAX_*`, including the ID widths) | physical consistency; `uvm_fatal` in the adapter constructors |
| CFG-06 | Drive or respond adapter bound to another specialization than the observe adapter (AW, DW, ID_W, ID_R: cross-wiring) | ADR-001 §4 |
| CFG-07 | Active Manager agent without a drive proxy, or active Subordinate agent without a respond proxy | ADR-002 decision 6 |

---

## 3. Parameters and widths

| Parameter (HDL) | Legal range | Source |
|---|---|---|
| `ADDR_WIDTH` | 1..64 | CFG-03; POC: 32 (A) and 40 (B) |
| `DATA_WIDTH` | 8, 16, 32, 64, 128, 256, 512, 1024 | CFG-04; POC pair 32 + 64 (ADR-001) |
| `ID_W_WIDTH`, `ID_R_WIDTH` | ≥ 1 physical | [IHI "Transaction ID"]: implementation defined; POC: 4/4 (A), 6/5 (B) |
| `USER_REQ_WIDTH`, `USER_DATA_WIDTH`, `USER_RESP_WIDTH` | ≥ 1 physical (presence via cfg; 0 = absent) | [IHI "User signaling"]; M2 |
| `QUEUE_DEPTH` | ≥ 1: Subordinate BFM default 8 (POL-08), monitor BFM default 16 | UVC capacity |
| `MAX_OUTSTANDING` (monitor BFM) | ≥ 1, default 16 | UVC capacity (POL-04) |

---

## 4. Rules for the BFMs and the monitor checks

These IDs are the traceability keys for checks, coverage and tests.

| ID | Rule | Source |
|---|---|---|
| AXI-R01 | All signals are sampled at the rising edge of `ACLK` | [IHI "Clock"] |
| AXI-R02 | A transfer happens at a rising `ACLK` edge where `VALID` and `READY` are both HIGH | [IHI "Handshake process"] ✓ |
| AXI-R03 | Once a source asserts `VALID`, it keeps it asserted until the handshake | [IHI "Handshake process"] ✓ |
| AXI-R04 | While `VALID` is HIGH and `READY` is LOW, the information on the channel stays stable | [IHI "Handshake process"] |
| AXI-R05 | A source must not wait for `READY` before asserting `VALID`. A destination may wait for `VALID` before asserting `READY`, may assert `READY` before `VALID`, and may deassert `READY` before `VALID` is asserted | [IHI "Handshake process", "Dependencies between channel handshake signals"] ✓ |
| AXI-R06 | Write dependencies: the Manager does not wait for `AWREADY` or `WREADY` before asserting `AWVALID` or `WVALID`, so write data may come before the address. The Subordinate asserts `BVALID` only after the address handshake and the handshake of the last write data transfer | [IHI "Dependencies between channel handshake signals"] ✓ |
| AXI-R07 | Read dependency: the Subordinate asserts `RVALID` only after the `ARVALID`/`ARREADY` handshake | [IHI "Dependencies between channel handshake signals"] ✓ |
| AXI-R08 | A burst has `AxLEN+1` beats: INCR 1..256, FIXED 1..16, WRAP 2, 4, 8 or 16 | [IHI "Burst length"] |
| AXI-R09 | The bytes per beat, 2^`AxSIZE`, do not exceed the data bus width | [IHI "Burst size"] |
| AXI-R10 | `AxBURST` FIXED 0b00, INCR 0b01, WRAP 0b10; 0b11 is reserved | [IHI "Burst type"] |
| AXI-R11 | A WRAP burst starts at an address aligned to the beat size and wraps at a boundary of len × size bytes | [IHI "Burst type", "Burst address"] |
| AXI-R12 | A burst must not cross a 4KB address boundary | [IHI "Address structure"] |
| AXI-R13 | Beat addresses and byte lanes follow the burst-address equations: beat 0 at the start address (possibly unaligned), later INCR/WRAP beats at the aligned address plus n × size (wrapped for WRAP), every FIXED beat at the start address; the lanes of a beat run from its address modulo the bus bytes to the end of its size-aligned block (`axi_beat_addr()`, `axi_lane_mask()`) | [IHI "Burst address", "Narrow transfers", "Unaligned transfers"] |
| AXI-R14 | A Manager asserts write strobes only for byte lanes that hold valid data: never outside the beat's lanes | [IHI "Write strobes"] |
| AXI-R15 | `WLAST` marks the last write data transfer of a burst and `RLAST` the last read data transfer | [IHI write/read data channel signal descriptions] |
| AXI-R16 | Responses OKAY 0b00, EXOKAY 0b01, SLVERR 0b10, DECERR 0b11; one `BRESP` per write burst, one `RRESP` per read beat | [IHI "Read and write response structure"] |
| AXI-R17 | EXOKAY answers an exclusive access only | [IHI "Read and write response structure", "Exclusive accesses"] ✓ |
| AXI-R18 | Exclusive access: the total bytes (len × size) are a power of two up to 128, at most 16 beats, the address aligned to the total | [IHI "Exclusive access restrictions"] ✓ |
| AXI-R19 | When `AxCACHE[1]` (Modifiable) is LOW, `AxCACHE[3:2]` are LOW | [IHI "Memory types"] ✓ |
| AXI-R20 | Responses to transactions with the same ID return in issue order; transactions with different IDs may complete out of order, and read data of different IDs may interleave. AXI4 write data follows the write address order (no WID) | [IHI "Transaction ID", "Transaction ordering"] |
| AXI-R21 | During reset the Manager drives `ARVALID`, `AWVALID`, `WVALID` LOW and the Subordinate `RVALID`, `BVALID` LOW; a `VALID` may first be driven HIGH at a rising `ACLK` edge after `ARESETn` is HIGH | [IHI "Reset"] ✓ |
| AXI-R22 | `ARESETn` is active LOW; it may assert asynchronously and deasserts synchronously with `ACLK` | [IHI "Reset"] ✓ |
| AXI-R23 | Outside reset `VALID` and `READY` are not X/Z; control and response signals are not X/Z while `VALID` is HIGH; write data may be X/Z only on lanes without a strobe | [ASSUMPTION], by analogy with the APB/AHB rules and Arm protocol-checker practice |
| AXI-R24 | AXI4-Lite: every transaction is one beat of the full data width; `DATA_WIDTH` 32 or 64; no ID, LEN, SIZE, BURST, LOCK, CACHE, QOS, REGION, LAST or user signal; no exclusive access, so no EXOKAY | [IHI "AXI4-Lite"] |
| AXI-R25 | `DATA_WIDTH` 8..1024 in powers of two | [IHI "Data read and write structure"] |
| AXI-R26 | `AxQOS` and `AxREGION` are 4 bits; 0 when not used | [IHI "QoS signaling", "Multiple region signaling"] |
| AXI-R27 | `AxPROT[0]` privileged, `[1]` non-secure, `[2]` instruction | [IHI "Access permissions"] |

### UVC policies built on top of the rules [ASSUMPTION]

| ID | Policy | Default |
|---|---|---|
| POL-01 | Watchdog: `cfg.max_wait_cycles` consecutive edges spent waiting on the other side without a handshake end a Manager transaction with status `TIMEOUT` and `uvm_error`; 0 disables. The Manager's own delays do not count | 1024 |
| POL-02 | The Manager BFM has one write and one read in flight at a time; the UVM Manager driver runs one item at a time. Several outstanding transactions per direction are milestone M2 (RISK-014) | — |
| POL-03 | Outputs that carry nothing — payload while `VALID` is LOW, the signals absent on AXI4-Lite, the M2 user signals — are driven to 0 | zero |
| POL-04 | One item is one transaction of 1..256 beats (`AXI_MAX_BEATS`). The monitor tracks up to `MAX_OUTSTANDING` open transactions per direction and reports more as `AXI_MON_ERR_CAPACITY` | 256 / 16 |
| POL-05 | The Subordinate answers in request order per direction and does not interleave read bursts; a queued response becomes eligible at the edge after it was queued, so timing does not depend on process order (LANG-09). Reordering across IDs and interleaving are M2 | in order |
| POL-06 | READY policies: the Subordinate's `AWREADY`/`WREADY`/`ARREADY` per instance (`cfg.aw/w/ar_ready_delay`: 0 = HIGH while there is room, d = HIGH once the `VALID` waited d cycles); the Manager's `BREADY`/`RREADY` per item (`resp_ready_delay`, the same rule) | 0 |
| POL-07 | AXI4-Lite addresses are generated aligned to the bus width; the monitor does not check AXI4-Lite alignment (no such rule verified) | aligned |
| POL-08 | The Subordinate BFM holds up to `QUEUE_DEPTH` open transactions per direction and keeps `READY` LOW while full (legal back-pressure, AXI-R05) | 8 |

---

## 5. Reset semantics

The specification requires the `VALID` signals LOW during reset and the first `VALID` no earlier than the edge after the release (AXI-R21/R22). **Everything below is [ASSUMPTION] for review**, aligned with the APB and AHB contracts' RST rules.

| ID | Behaviour |
|---|---|
| RST-1 | While `ARESETn`=0 the Manager BFM drives every `VALID`, `BREADY`, `RREADY` and payload to 0, and the Subordinate BFM every `VALID`, `READY` and payload to 0 — from the moment reset asserts, even on an `ACLK` edge |
| RST-2 | Reset assertion is recognised immediately (asynchronously); deassertion at the first `ACLK` rising edge that samples `ARESETn`=1 |
| RST-3 | A Manager transaction in flight when reset asserts is abandoned. The item completes with status `RESET_ABORTED` and is not retried |
| RST-4 | The monitor discards every open transaction: nothing of it is published. Reset assertion and release after the first release are reported as separate observe-API events (`axi_reset_event`, `axi_monitor.reset_ap`) |
| RST-5 | The Manager's first `VALID` after reset is no earlier than `cfg.post_reset_idle_cycles` (default 1) edges after the release (AXI-R21 needs 0) |
| RST-6 | Protocol and X/Z checks are inactive while `ARESETn`=0, except that a `VALID` HIGH in reset, or at the first edge after it, is reported (AXI-R21) |
| RST-7 | X/Z on `ARESETn` after the first reset deassertion is an error |
| RST-8 | The Subordinate BFM drops every open request and queued response when reset asserts, and its epoch number moves on: a response to a request handed out before the reset is refused with `RESET_ABORTED`. `axi_sub_mem_seq` clears its memory at the first request of a new epoch |

---

## 6. Transaction representation (HVL, not width-parameterized)

`axi_transaction` extends `uvm_sequence_item`. One object is **one transaction**; one class serves every instance width, both roles and the monitor (owner decision A-3).

| Field | Type | Notes |
|---|---|---|
| `dir` | `axi_dir_e` {`AXI_READ`, `AXI_WRITE`} | write or read |
| `id` | `logic [AXI_MAX_IDW-1:0]` | `AWID` / `ARID` |
| `addr` | `logic [AXI_MAX_AW-1:0]` | start address; INCR/FIXED may be unaligned (`c_aligned` off) |
| `burst`, `size`, `len` | `axi_burst_e`, `axi_size_e`, `int unsigned` | `AxBURST`, `AxSIZE`, beats = `AxLEN+1` |
| `lock`, `cache`, `prot`, `qos`, `region` | `logic` vectors | `AxLOCK` … `AxREGION` |
| `wdata[]`, `wstrb[]` | per beat | whole bus words with lanes as on `WDATA`; `post_randomize()` sets every active lane (or a random subset) |
| `addr_delay`, `data_delay[]`, `resp_ready_delay`, `resp_delay` | `int unsigned` | Manager: edges before `AxVALID`, before each W beat, `BREADY`/`RREADY` wait. Subordinate response: `resp_delay` before `BVALID`, `data_delay[]` before each R beat |
| `bresp`, `rdata[]`, `rresp[]`, `resp_id` | 4-state | responses, zero-extended read data, `BID`/`RID` |
| `beats_done`, `status` | `int unsigned`, `axi_bfm_status_e` | one encoding shared with the BFMs: `OK`, `ERROR` (a SLVERR or DECERR), `RESET_ABORTED`, `TIMEOUT`, `NOT_ENABLED`, `BAD_REQUEST`, `FAULT_INJECTED` (reserved) |
| `addr_wait`, `data_wait[]`, `resp_wait` | `int unsigned` | cycles each `VALID` waited for its `READY` |
| `addr_cycle`, `first_data_cycle`, `last_data_cycle`, `resp_cycle` | `longint unsigned` | monitor samples of the handshakes (`addr_cycle` also on Subordinate requests) |
| `req_epoch` | `int unsigned` | Subordinate requests: BFM reset epoch (RST-8) |
| bus context | widths, `bus_max_size`, `bus_lite`, over-width masks | set by `axi_base_seq::new_item()` before randomization and by the adapters; constraints keep values legal for that bus |
| `instance_name` | `string` | adapter that drove, received or observed the item |

### Lossless and 4-state rules

- **No silent narrowing.** The drive adapter checks that every bit at or above the bound bus widths (`addr`, `id`, every `wdata` and `wstrb` beat) is 0, and that length, size, WRAP alignment, 4KB page, exclusive restrictions, `AxCACHE` and the AXI4-Lite subset are legal, and that strobes stay inside their lanes; otherwise `uvm_error`, status `BAD_REQUEST`, nothing on the bus. The respond adapter does the same for read data and EXOKAY.
- **No sign extension.** Payload fields are unsigned `logic` vectors; the observe and respond adapters zero-extend.
- **4-state preserved.** The monitor and the Manager capture X/Z verbatim; nothing is converted to `bit`.
- **Driver input check.** X/Z in `id`, `addr` or the attributes is an error; X/Z in strobed write data only with `cfg.allow_x_wdata` (fault injection).
- The maxima (`AXI_MAX_ADDR_WIDTH` 64, `AXI_MAX_DATA_WIDTH` 64, `AXI_MAX_ID_WIDTH` 8 by default) are one compile-time choice per simulation image (`hvl/types/axi_defines.svh`).

---

## 7. Monitor transport and reconstruction (RISK-002) [ASSUMPTION; implemented in `axi_monitor_bfm_if`]

- The monitor BFM samples through a clocking block (`@(posedge ACLK)`, input skew `#1step`) and reconstructs transactions in an always-running HDL process, independent of HVL timing.
- At each sample it handles, in order: reset; `VALID`/`READY` validity; the handshake rules against the previous sample (AXI-R03/R04); the responses B and R, matched against what was complete **before** this edge (so a response at the edge of its own request handshake is flagged, AXI-R06/R07); the requests AW, W, AR; write pairing.
- **Any legal AXI4 traffic** is reconstructed, not only what this UVC generates: up to `MAX_OUTSTANDING` open transactions per direction; responses matched to the oldest open transaction with the same ID (AXI-R20), so responses out of order across IDs and read data interleaved across IDs are handled; write data bursts (framed by `WLAST`) paired with write addresses in order, also when the data comes first.
- A read ends after `ARLEN+1` beats (`RLAST` is checked on every beat, not used for framing); a write ends at its B handshake. Each transaction is **published once**, then, into a bounded HDL queue of plain values (no UVM objects, ADR-002 §6); overflow is reported. Reset edges after the first release go into a second bounded queue (RST-4).
- The HVL observe adapter calls the blocking tasks `get_txn(…)` and `get_reset_event(…)`; `axi_monitor` runs one loop for each and publishes on `ap` and `reset_ap`.
- **Wake-up rule:** a publish pushes the entry and triggers a named event (`obs_ev`, `rst_ev`); the getters run `while (queue empty) @(event);`, so a publish earlier in the same time step is never missed.
- The monitor works whether or not a Manager or Subordinate BFM is enabled, because it only reads pins (instance P).
- 22 counted checks (`axi_mon_error_e`): VALID/READY/payload/ARESETn X/Z, VALID in reset, VALID dropped, payload unstable, reserved burst, burst length, size, WRAP alignment, 4KB, exclusive restrictions, AxCACHE, strobes outside lanes, WLAST, RLAST, B and R without a matching transaction, EXOKAY to a normal access, and two capacity limits.
- Elaborated by slang without a diagnostic; not simulated, so none of the checks has fired yet (§11).

## 8. Driver and responder behaviour [ASSUMPTION; implemented in the BFMs]

**Manager (`axi_manager_bfm_if`):**
- `do_write()` and `do_read()` each run one transaction as **one per-edge state machine** over their channels (race-free: no forked per-channel processes sharing state, LANG-09). AW and W progress independently: neither waits for the other's `READY` (AXI-R06), so the data may cross before the address.
- Every `VALID` and its payload are driven with NBAs and held until the handshake (AXI-R03/R04). `BREADY` rises only once the address and the last data beat are accepted (legal, AXI-R05) — immediately with `resp_ready_delay` 0, otherwise after `BVALID` waited that many cycles; `RREADY` follows the same rule per beat.
- A read ends after `len` beats; a write at its B handshake. One write and one read may be in flight at once (separate state; POL-02).
- **Drive release:** when not enabled every output is `'z` and `axi_if` uses resolved nets, so a passive instance cannot contend (instance P exists to prove it). Unverified until a 4-state simulator run (RISK-009).
- **Reset during a transaction:** the state machine and a reset watcher run under `fork…join_any` inside an outer `fork…join` (LANG-08); the transaction is abandoned with `RESET_ABORTED` (RST-2/RST-3), and an `always @(ARESETn)` block idles the outputs as soon as reset asserts (RST-1).
- **Fault modes** (negative tests): `AxADDR` moved while the address waits (`AXI_FAULT_ADDR_UNSTABLE` → `AXI_MON_ERR_UNSTABLE`), `WVALID` dropped for a cycle before its handshake (`AXI_FAULT_VALID_DROP` → `AXI_MON_ERR_VALID_DROPPED`), a strobe outside the lanes of a narrow or unaligned beat (`AXI_FAULT_WSTRB_OUTSIDE` → `AXI_MON_ERR_WSTRB`).

**Subordinate (`axi_subordinate_bfm_if`):**
- An always-running per-edge process accepts AW, W and AR under the READY policy (POL-06, POL-08), pairs addresses with write data bursts (data first allowed), queues complete requests, and drives B and R from the response queues.
- `get_request()` (blocking) hands requests to the HVL side; `put_write_response()` / `put_read_response()` accept a response only for the oldest open request of that direction with the same ID (and length): ID ordering holds by construction (AXI-R20, POL-05). B is possible only after pairing, R only after the address (AXI-R06/R07).
- Reset: RST-1, RST-8. The live `ARESETn` is checked as well as the sampled one, so a reset asserting on an `ACLK` edge leaves the outputs idle whatever the process order.
- **Fault mode:** `RLAST` also on the second-to-last beat (`AXI_FAULT_RLAST_EARLY` → `AXI_MON_ERR_RLAST`).

---

## 9. Package and compile dependencies

```text
HDL compilation units (no UVM):
  hdl/axi_bfm_pkg.sv   types + pure functions: protocol mode, AxBURST/AxSIZE/xRESP, features,
                       status, fault and monitor-error enums, burst address and byte-lane
                       arithmetic, 4KB / exclusive / AxCACHE legality
    └─> hdl/axi_if.sv   hdl/axi_manager_bfm_if.sv   hdl/axi_subordinate_bfm_if.sv
        hdl/axi_monitor_bfm_if.sv
        ^ ordinary signal ports wired in examples/axi_hdl_top.sv (ADR-002 §7)

HVL packages:
  uvm_pkg, axi_bfm_pkg
    └─> axi_api_pkg       (hvl/types, hvl/api: transaction, reset event, three proxy bases)
          ├─> axi_uvc_pkg      (hvl/config, hvl/agent, hvl/sequences, hvl/coverage)
          └─> axi_adapter_pkg  (hvl/adapter: width-specialized proxies; names the
                                BFM interface types via virtual interface handles)

Integration (examples/):
  axi_hdl_top  : per bus (A, B) axi_if + Manager BFM + Subordinate BFM + a monitor BFM per
                 agent; passive set P on bus A
  axi_hvl_top  : imports uvm_pkg, axi_api_pkg, axi_uvc_pkg, axi_adapter_pkg, axi_poc_test_pkg;
                 constructs adapters, fills one axi_agent_cfg per agent,
                 uvm_config_db::set once each, registers the test reset helper, run_test()
```

Compile order: `axi_bfm_pkg` → HDL interfaces → `uvm_pkg` → `axi_api_pkg` → `axi_uvc_pkg` → `axi_adapter_pkg` → examples/tests. `axi_uvc_pkg` must not import `axi_adapter_pkg`; nothing in the core imports example or test code.

## 10. File manifest and milestone split

| Step (`CLAUDE_GENERATION_PROMPT.md`) | Files | Status |
|---|---|---|
| 2 HDL | `hdl/axi_bfm_pkg.sv`, `hdl/axi_if.sv`, `hdl/axi_manager_bfm_if.sv`, `hdl/axi_subordinate_bfm_if.sv`, `hdl/axi_monitor_bfm_if.sv`, `examples/axi_hdl_top.sv`, `tests/axi_hdl_smoke.sv`, `filelists/axi_hdl.f`, `filelists/axi_hdl_smoke.f`, `scripts/{slang_elab.py,make_eda_bundle.py}`, `README.md` | **written; compile NOT RUN** |
| 3 HVL API | `hvl/types/axi_defines.svh`, `hvl/types/axi_transaction.sv`, `hvl/types/axi_reset_event.sv`, `hvl/api/axi_drive_proxy_base.sv`, `hvl/api/axi_respond_proxy_base.sv`, `hvl/api/axi_monitor_proxy_base.sv`, `hvl/pkg/axi_api_pkg.sv` | **written; compile NOT RUN** |
| 4 HVL concrete | `hvl/adapter/axi_drive_proxy.sv`, `hvl/adapter/axi_respond_proxy.sv`, `hvl/adapter/axi_monitor_proxy.sv`, `hvl/pkg/axi_adapter_pkg.sv` | **written; compile NOT RUN** |
| 5 UVM | `hvl/config/axi_agent_cfg.sv`, `hvl/agent/{axi_base_sequencer,axi_mgr_sequencer,axi_sub_sequencer,axi_mgr_driver,axi_sub_driver,axi_monitor,axi_base_agent,axi_mgr_agent,axi_sub_agent}.sv`, `hvl/coverage/{axi_coverage,axi_mgr_coverage,axi_sub_coverage}.sv`, `hvl/sequences/{axi_base_seq,axi_mgr_base_seq,axi_mgr_random_seq,axi_sub_base_seq,axi_sub_mem_seq}.sv`, `hvl/pkg/axi_uvc_pkg.sv`, `filelists/{axi_hvl,axi_poc}.f`, `examples/axi_hvl_top.sv` | **written; compile NOT RUN** |
| 6 Tests | `tests/axi_poc_test_pkg.sv` with `axi_poc_scoreboard.sv`, `axi_poc_env.sv`, `axi_poc_seqs.sv`, `axi_fake_proxies.sv`, `axi_poc_reset_ctrl.sv`, `axi_poc_test.sv`, `axi_fault_injection_test.sv`, `axi_negative_tests.sv`, `axi_passive_reset_tests.sv`, `axi_lite_test.sv` | **written; NOT RUN** |
| later M2 | same files | several outstanding Manager transactions and a pipelined driver (RISK-014), Subordinate reordering across IDs and read interleaving, an exclusive monitor in the responder, user signals |
| later M3 | on request (Q1) | AXI5 properties, AXI3 |

`hdl/axi_bfm_pkg.sv` holds the enums and the burst arithmetic because they must be shared by the HDL BFMs **and** the HVL classes (`axi_transaction`, scoreboard, smoke test); it is a types-and-pure-functions package with no UVM, no classes and no timing.

## 11. Smallest runnable task and acceptance test

**AXI-003a (step 2):** the HDL files of the step 2 row, with instances A, B and P in `axi_hdl_top`, exercised by `tests/axi_hdl_smoke.sv`.

Acceptance (item 1 **PASS**, items 2–3 **NOT RUN**; tools approved for elaboration only, D-011):
1. Elaboration of `axi_hdl_smoke` (A, B, P): **0 errors** (log stored with SHA). **PASS** with slang 12.1.0 at `1757553`: errors=0, warnings=0 (`evidence/AXI-003/`).
2. HDL-only directed smoke on a simulator: per instance the directed list of `axi_hdl_smoke.sv` (single beats, INCR4, WRAP4, FIXED, narrow byte merge, unaligned INCR, directed strobes, 32-beat INCR, data before address, a write and a read in flight together, SLVERR, DECERR, exclusive read) and on B a short AXI4-Lite phase. Manager results, read data and every published transaction must match, the counts must be exact, nothing may stay open, and A, B, P and the Subordinate-side monitors must report no protocol error.
3. Negative controls: `+AXI_FAULT=1|2|3|4` must each be detected on A (and P) with the matching error code (`axi_fault_error()`), with B clean.

Then **AXI-004:** elaborate `filelists/axi_poc.f` with a UVM library (done with UVM 1.2 at `1757553`: 0 diagnostics in the AXI sources, one error inside UVM 1.2, RISK-012; `evidence/AXI-004/`), then run the seven UVM tests of `WORK_STATUS.md` *Tests available* (NOT RUN).

---

## 12. Open questions (need owner decision)

| ID | Question | Recommendation (implemented as default) |
|---|---|---|
| Q1 | Protocol scope beyond AXI4 + AXI4-Lite (AXI3, AXI5 properties, ACE)? | AXI4 + AXI4-Lite only (owner decision A-2); add AXI5 properties as later milestones on request |
| Q2 | Default instance | AXI4 without user signals |
| Q3 | Width set of the POC | A: AW=32, DW=32, ID 4/4; B: AW=40, DW=64, ID 6/5 (address, data and ID widths all differ) |
| Q4 | Milestone split | M1 as implemented; M2 several outstanding Manager transactions, Subordinate reordering/interleaving, exclusive monitor, user signals; M3 on request |
| Q5 | Approve the reset assumptions RST-1..8 and policies POL-01..08 | — |
| Q6 | Item granularity: one transaction per item, one write and one read in flight per Manager (POL-02) | Keep for M1; several outstanding transactions need early `item_done` with response events or `put_response` (M2 candidate, RISK-014) |
| Q7 | Tool approval for this repository (T1/T3/T4/T5 in `WORK_STATUS.md`) | Approve T1 (slang elaboration) and T3 (UVM 1.2) as for APB, then the owner runs T4 on EDA Playground |
