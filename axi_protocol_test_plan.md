# AXI Protocol Test Plan

| Field | Value |
|---|---|
| Document | AXI Protocol Verification Test Plan |
| Protocol | AMBA AXI4 (with AXI4-Lite and AXI4-Stream sections) |
| Version | 0.1 (Draft) |
| Date | 2026-11-01 |
| Status | Draft for review |

---

## 1. Introduction

### 1.1 Purpose
This document defines the strategy, scope, test cases, coverage goals, and exit criteria for verifying a design that implements the AMBA AXI protocol. It applies to AXI masters, AXI slaves, and AXI interconnect/bridge components.

### 1.2 Objectives
- Confirm protocol compliance against the AMBA AXI specification (ARM IHI 0022).
- Confirm functional correctness of data movement (writes land where expected, reads return what was written).
- Confirm robustness under backpressure, errors, resets, and random stress.
- Reach the functional coverage and code coverage targets in Section 9.

### 1.3 References
| Ref | Document |
|---|---|
| [1] | ARM IHI 0022 – AMBA AXI and ACE Protocol Specification |
| [2] | ARM IHI 0051 – AMBA 4 AXI4-Stream Protocol Specification |
| [3] | DUT micro-architecture / design specification |
| [4] | DUT register map and memory map |

---

## 2. Scope

### 2.1 In Scope
- All five AXI channels: AW, W, B, AR, R.
- Burst types: FIXED, INCR, WRAP.
- Narrow transfers, unaligned addresses, byte strobes.
- Transaction IDs, outstanding transactions, ordering rules.
- Response codes: OKAY, EXOKAY, SLVERR, DECERR.
- Exclusive accesses.
- Optional signals: AxCACHE, AxPROT, AxQOS, AxREGION, AxUSER, xUSER (as supported by the DUT).
- Reset behavior.
- AXI4-Lite subset.
- AXI4-Stream (if the DUT includes stream interfaces).
- Interconnect features (if applicable): address decode, arbitration, width/clock conversion.

### 2.2 Out of Scope
- ACE / ACE-Lite coherency extensions.
- Physical implementation, timing closure, and power analysis.
- Software/driver-level verification.
- AXI3-only features (write interleaving, locked transfers) unless the DUT claims AXI3 support.

---

## 3. DUT Configuration Parameters

The plan must be run across the relevant parameter space. Fill in the supported values for the DUT.

| Parameter | Typical values to cover | Notes |
|---|---|---|
| `DATA_WIDTH` | 32, 64, 128, 256, 512 | Cover min, max, and at least one middle value |
| `ADDR_WIDTH` | 32, 40, 48, 64 | Include addresses near the top of the range |
| `ID_WIDTH` | 0, 1, 4, 8 | Include single-ID and many-ID configurations |
| `USER_WIDTH` (per channel) | 0, 1, 8 | If USER signals are supported |
| Max outstanding reads/writes | 1, 2, 8, 16, max | Include depth boundary tests |
| Exclusive access support | on / off | |
| Out-of-order support | on / off | |
| Clock ratio (if CDC present) | 1:1, 2:1, 1:3, async | |
| Low-power interface | on / off | |

---

## 4. Verification Strategy

### 4.1 Methodology
- Constrained-random UVM (SystemVerilog) testbench plus directed tests for corner cases.
- Protocol compliance monitoring via SystemVerilog Assertions (SVA) bound to the interface.
- Reference-model scoreboard for data integrity.
- Functional coverage collected from monitors.
- Formal verification (optional) for handshake rules and deadlock freedom.

### 4.2 Testbench Architecture

```
            +-----------------------------------------------+
            |                  UVM Test                     |
            +-----------------------------------------------+
                  |                                  |
          +---------------+                  +---------------+
          | AXI Master    |                  | AXI Slave     |
          | Agent (VIP)   |                  | Agent (VIP)   |
          +---------------+                  +---------------+
                  |                                  |
                  |        +---------------+         |
                  +------->|      DUT      |<--------+
                           +---------------+
                  |                |                 |
          +-------------------------------------------------+
          | Protocol Checker (SVA) | Monitors | Coverage    |
          +-------------------------------------------------+
                                   |
                           +---------------+
                           |  Scoreboard   |
                           | (memory model)|
                           +---------------+
```

Testbench topology depends on the DUT type:

| DUT type | Active agents | Passive agents |
|---|---|---|
| AXI master | Slave agent (responder) | Monitor on master port |
| AXI slave | Master agent (driver) | Monitor on slave port |
| Interconnect | Master agents on all slave-facing ports, slave agents on all master-facing ports | Monitors on all ports |

### 4.3 Components
| Component | Responsibility |
|---|---|
| Master agent | Generates AW/W/AR transactions with configurable delays, burst attributes, and IDs |
| Slave agent | Responds with configurable latency, backpressure, and response codes; backed by a memory model |
| Protocol checker | SVA assertions listed in Section 8 |
| Scoreboard | Predicts expected data, response, ordering, and attributes; compares against observed |
| Coverage collector | Samples transactions and signal-level events |
| Sequence library | Directed, random, and stress sequences |

### 4.4 Test Types
- **Directed** – deterministic corner cases and spec-rule checks.
- **Constrained random** – broad exploration of burst/ID/delay space.
- **Error / negative** – deliberate protocol violations (only when the checker is expected to flag them) and error responses.
- **Stress** – sustained high-throughput and long-duration runs.
- **Performance** – throughput and latency measurements.

---

## 5. Features to Be Verified

| ID | Feature |
|---|---|
| F-01 | Reset behavior |
| F-02 | VALID/READY handshake rules |
| F-03 | Write address, write data, write response channels |
| F-04 | Read address and read data channels |
| F-05 | Burst types and lengths (FIXED, INCR, WRAP) |
| F-06 | Transfer size, narrow transfers, unaligned access, strobes |
| F-07 | 4KB boundary rule |
| F-08 | Transaction IDs and ordering |
| F-09 | Outstanding transactions |
| F-10 | Response codes |
| F-11 | Exclusive access |
| F-12 | Attribute signals (CACHE, PROT, QOS, REGION, USER) |
| F-13 | Backpressure and latency tolerance |
| F-14 | Channel dependencies (write data before address, etc.) |
| F-15 | AXI4-Lite subset |
| F-16 | AXI4-Stream |
| F-17 | Interconnect: decode, arbitration, conversion |
| F-18 | Error handling and recovery |
| F-19 | Performance |
| F-20 | Low-power interface (if present) |

---

## 6. Test Cases

Priority: **P0** = must pass for sign-off, **P1** = important, **P2** = nice to have.

### 6.1 Reset (F-01)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-RST-001 | Power-on reset values | Apply ARESETn low from time zero | Master drives AWVALID/WVALID/ARVALID low; slave drives BVALID/RVALID low during and at first clock edge after reset release | P0 |
| TC-RST-002 | Reset during idle | Assert reset with no traffic, then release and run traffic | Normal operation resumes; no spurious transactions | P0 |
| TC-RST-003 | Reset during write burst | Assert reset mid-burst on W channel | All VALID signals deasserted; no BVALID after reset; DUT state cleared | P0 |
| TC-RST-004 | Reset during read burst | Assert reset mid-burst on R channel | RVALID deasserted; no stale data after reset | P0 |
| TC-RST-005 | Reset with outstanding transactions | Issue max outstanding, then reset | Outstanding counters/FIFOs cleared; no late responses | P0 |
| TC-RST-006 | Reset pulse width | Apply minimum and long reset pulses | DUT recovers in each case | P1 |
| TC-RST-007 | Repeated reset | Apply reset multiple times back-to-back with traffic between | No hangs, no state leakage | P1 |
| TC-RST-008 | Register / memory state after reset | Write data, reset, read back | Registers return reset values; memory behavior matches spec | P1 |

### 6.2 Handshake (F-02)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-HS-001 | READY before VALID | Hold READY high, then assert VALID | Transfer occurs on the first cycle VALID is high | P0 |
| TC-HS-002 | VALID before READY | Assert VALID, delay READY by N cycles (N = 1…32) | Transfer occurs when READY rises; payload held stable | P0 |
| TC-HS-003 | VALID and READY same cycle | Assert both simultaneously | Single transfer completes | P0 |
| TC-HS-004 | VALID stability | Hold READY low for a long time after VALID | VALID stays high; payload signals do not change | P0 |
| TC-HS-005 | READY toggling | Randomly toggle READY while VALID is low and high | No lost or duplicated transfers | P0 |
| TC-HS-006 | No combinational dependency | Stall READY indefinitely until VALID seen (slave) and vice versa (master) | No deadlock; VALID never waits on READY | P0 |
| TC-HS-007 | Back-to-back transfers | Continuous VALID with READY always high | Full throughput, one transfer per cycle, per channel | P1 |
| TC-HS-008 | Per-channel independent delays | Randomize delay on each of the five channels independently | All transactions complete correctly | P0 |

### 6.3 Write Transactions (F-03, F-14)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-WR-001 | Single-beat write | AWLEN=0, full-width, aligned | Data stored; BRESP=OKAY | P0 |
| TC-WR-002 | Multi-beat INCR write | AWLEN = 1, 3, 7, 15, 255 | All beats stored at incrementing addresses; one BRESP | P0 |
| TC-WR-003 | WLAST correctness | Check WLAST on the final beat only | DUT accepts; slave detects burst end correctly | P0 |
| TC-WR-004 | Write data before address | Send W beats before AW | Data held/accepted per DUT capability; final result correct | P0 |
| TC-WR-005 | Write address before data | Send AW several cycles before W | Correct write | P0 |
| TC-WR-006 | Address and data same cycle | AW and W simultaneously | Correct write | P0 |
| TC-WR-007 | BRESP timing | Observe BVALID | BVALID asserted only after AW and last W beat have both been accepted | P0 |
| TC-WR-008 | BREADY delay | Hold BREADY low for N cycles | BVALID/BRESP/BID held stable until BREADY | P0 |
| TC-WR-009 | BREADY before BVALID | BREADY high before response | Response accepted immediately | P1 |
| TC-WR-010 | Back-to-back writes | Issue writes with no idle cycles | All complete in order per ID | P0 |
| TC-WR-011 | Write then read same address | Write, wait for BRESP, read | Read returns written data | P0 |
| TC-WR-012 | Write strobes — all enabled | WSTRB all ones | Full word written | P0 |
| TC-WR-013 | Write strobes — sparse | WSTRB patterns: single byte, alternating, all zeros | Only strobed bytes change; zero strobe writes nothing | P0 |
| TC-WR-014 | Strobe on narrow transfers | AWSIZE < bus width with correct byte lane strobes | Correct byte lanes updated | P0 |
| TC-WR-015 | Overlapping writes | Write same address with different IDs / back-to-back | Last write wins per ordering rules | P1 |

### 6.4 Read Transactions (F-04)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-RD-001 | Single-beat read | ARLEN=0 | RDATA correct; RRESP=OKAY; RLAST=1 | P0 |
| TC-RD-002 | Multi-beat INCR read | ARLEN = 1, 3, 7, 15, 255 | Correct data per beat; RLAST only on final beat | P0 |
| TC-RD-003 | RREADY delay | Hold RREADY low for N cycles | RVALID/RDATA/RID/RRESP/RLAST held stable | P0 |
| TC-RD-004 | RREADY toggling mid-burst | Random RREADY | No beats lost or duplicated | P0 |
| TC-RD-005 | Read data latency | Slave delay 0…N cycles before first beat and between beats | Master tolerates all latencies | P0 |
| TC-RD-006 | RVALID timing | Observe RVALID | Asserted only after ARVALID and ARREADY handshake | P0 |
| TC-RD-007 | Back-to-back reads | Issue ARs with no idle cycles | All complete correctly | P0 |
| TC-RD-008 | Read of unwritten memory | Read uninitialized location | Returns defined/default value per DUT spec | P1 |
| TC-RD-009 | Per-beat response | Slave returns different RRESP per beat | Master handles per-beat RRESP | P1 |

### 6.5 Burst Types, Size, and Alignment (F-05, F-06, F-07)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-BST-001 | FIXED burst write/read | AxBURST=FIXED, lengths 1…16 | Same address every beat; correct data order | P0 |
| TC-BST-002 | INCR burst, all sizes | AxSIZE = 1, 2, 4, … up to bus width bytes | Address increments by transfer size | P0 |
| TC-BST-003 | WRAP burst, all valid lengths | AxLEN = 1, 3, 7, 15 (2, 4, 8, 16 beats) | Address wraps at the correct boundary | P0 |
| TC-BST-004 | WRAP start at each position | Start address at every beat offset in the wrap window | Correct wrap sequence | P0 |
| TC-BST-005 | WRAP with narrow size | WRAP with AxSIZE < bus width | Correct wrap boundary calculation | P1 |
| TC-BST-006 | INCR max length | AxLEN=255 (256 beats) | Completes; addresses correct | P0 |
| TC-BST-007 | 4KB boundary — burst ending exactly at boundary | INCR burst whose last byte is the last byte of a 4KB page | Legal; completes correctly | P0 |
| TC-BST-008 | 4KB boundary — master compliance | Check the master never issues a burst crossing 4KB | No crossing observed (assertion) | P0 |
| TC-BST-009 | 4KB boundary — splitting | Master/bridge asked to move data crossing 4KB | Properly split into legal bursts | P1 |
| TC-BST-010 | Narrow transfer — each size vs bus width | AxSIZE from 1 byte up to bus width | Correct active byte lanes per beat | P0 |
| TC-BST-011 | Unaligned start — INCR | Start address not aligned to size | First beat uses partial lanes; subsequent beats aligned | P0 |
| TC-BST-012 | Unaligned start — FIXED | Unaligned address with FIXED | Handled per spec (same lanes each beat) | P1 |
| TC-BST-013 | Address range extremes | Lowest address, highest address, address near boundaries of decode regions | Correct behavior or correct error | P1 |
| TC-BST-014 | Full-width aligned burst | AxSIZE = bus width, aligned | Maximum-throughput behavior | P1 |
| TC-BST-015 | Random burst mix | Randomize len/size/type/address legally | No scoreboard mismatches | P0 |

### 6.6 IDs, Ordering, and Outstanding Transactions (F-08, F-09)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-ID-001 | Single ID, multiple outstanding reads | Same ARID, N outstanding | Responses return in issue order | P0 |
| TC-ID-002 | Single ID, multiple outstanding writes | Same AWID, N outstanding | BRESPs return in issue order | P0 |
| TC-ID-003 | Multiple IDs, reads | Different ARIDs outstanding | Responses may reorder across IDs, never within an ID | P0 |
| TC-ID-004 | Multiple IDs, writes | Different AWIDs outstanding | BRESPs correct per ID | P0 |
| TC-ID-005 | RID/BID match | Check IDs on every response | RID/BID equal the originating ARID/AWID | P0 |
| TC-ID-006 | Read data interleaving | Slave interleaves beats from different IDs | Master reassembles each burst correctly | P1 |
| TC-ID-007 | Out-of-order completion | Slave completes younger ID first | Master/interconnect handles it; same-ID order preserved | P0 |
| TC-ID-008 | Maximum outstanding | Fill the outstanding limit | Master/DUT stalls correctly at the limit; no overflow | P0 |
| TC-ID-009 | Outstanding limit + 1 | Attempt one more than the limit | Backpressure applied; no lost transaction | P0 |
| TC-ID-010 | Write order vs W data order | Multiple outstanding AWs, W data in AW order | Data matched to correct addresses | P0 |
| TC-ID-011 | ID reuse after completion | Reuse an ID immediately after its response | Works without confusion with prior transaction | P0 |
| TC-ID-012 | All IDs in use | Use every ID value in ID_WIDTH | No aliasing | P1 |
| TC-ID-013 | Read/write ordering to same address | Overlapping read and write in flight | Ordering matches DUT spec / no corruption | P1 |
| TC-ID-014 | Zero ID_WIDTH | Configuration with no ID signals | Operates with implicit single ID | P2 |

### 6.7 Responses and Errors (F-10, F-18)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-RSP-001 | OKAY response | Normal access | BRESP/RRESP = OKAY | P0 |
| TC-RSP-002 | SLVERR on write | Slave returns SLVERR | Master observes BRESP=SLVERR; handles per design (error flag/interrupt) | P0 |
| TC-RSP-003 | SLVERR on read | Slave returns SLVERR | Master observes RRESP=SLVERR on the affected beat(s) | P0 |
| TC-RSP-004 | DECERR from interconnect | Access to unmapped address | DECERR returned; burst completes properly (all beats returned for reads) | P0 |
| TC-RSP-005 | Error burst completes | SLVERR in the middle of a read burst | Remaining beats still delivered; RLAST still asserted | P0 |
| TC-RSP-006 | Error on write with data consumed | Write to error region | All W beats consumed; single BRESP error | P0 |
| TC-RSP-007 | Error does not corrupt other traffic | Interleave error and good transactions | Good transactions unaffected | P0 |
| TC-RSP-008 | Read-only region write | Write to read-only target | Error response; no data change | P1 |
| TC-RSP-009 | Access to reserved / unmapped register | Read/write reserved registers | Behavior per register spec | P1 |
| TC-RSP-010 | Recovery after error | Error followed by normal traffic | Normal operation resumes | P0 |
| TC-RSP-011 | Zero WSTRB write | All strobes low | No memory change; OKAY response | P1 |
| TC-RSP-012 | Slave timeout / no response (if DUT has watchdog) | Slave never responds | DUT timeout behavior per spec | P2 |

### 6.8 Exclusive Access (F-11)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-EX-001 | Successful exclusive pair | Exclusive read, then exclusive write to same address/ID with no intervening write | RRESP=EXOKAY, BRESP=EXOKAY; memory updated | P0 |
| TC-EX-002 | Failed exclusive write | Another master writes between exclusive read and exclusive write | BRESP=OKAY; memory not updated | P0 |
| TC-EX-003 | Exclusive write without prior read | Exclusive write with no monitor entry | BRESP=OKAY; memory not updated | P0 |
| TC-EX-004 | Exclusive read size/alignment | Bytes = 1, 2, 4, … 128 (power of two), aligned to total bytes | Accepted per spec | P0 |
| TC-EX-005 | Exclusive length limit | Burst up to 16 beats | Accepted | P1 |
| TC-EX-006 | Slave without exclusive support | Exclusive access to non-supporting slave | Returns OKAY, never EXOKAY | P0 |
| TC-EX-007 | Multiple masters / IDs | Parallel exclusive sequences with different IDs | Each tracked independently | P1 |
| TC-EX-008 | Exclusive monitor capacity | Exceed number of monitor entries | Oldest entry dropped; behavior per spec | P2 |
| TC-EX-009 | Exclusive across interconnect | Exclusive through interconnect to supporting slave | EXOKAY propagated correctly | P1 |

### 6.9 Attributes and Sideband Signals (F-12)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-ATTR-001 | AxCACHE values | All 16 encodings | Passed through unchanged by interconnect; slave behavior per spec | P1 |
| TC-ATTR-002 | AxPROT values | All 8 combinations | Passed through; access control honored if implemented | P0 |
| TC-ATTR-003 | Secure/non-secure access | Non-secure access to secure region | Error response if the DUT enforces it | P1 |
| TC-ATTR-004 | AxQOS values | 0…15 | Passed through; arbitration respects QoS if implemented | P1 |
| TC-ATTR-005 | AxREGION values | 0…15 | Passed through; decode matches region map | P2 |
| TC-ATTR-006 | AxUSER / WUSER / RUSER / BUSER | Random user data | Propagated unchanged where specified | P1 |
| TC-ATTR-007 | AxLOCK | Normal and exclusive values | Per spec (AXI4: 1 bit) | P1 |
| TC-ATTR-008 | Attribute stability across burst | Check attributes constant for a burst | Assertions clean | P0 |

### 6.10 Backpressure, Latency, and Throughput (F-13, F-19)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-BP-001 | Zero-delay slave | All READY/VALID with no delays | Max throughput; no data errors | P0 |
| TC-BP-002 | Random slave delays | Random 0–N cycle delays per channel | Correct data; no hangs | P0 |
| TC-BP-003 | Long stall | Hold a channel blocked for thousands of cycles | No timeout inside the DUT; resumes cleanly | P1 |
| TC-BP-004 | Alternating fast/slow phases | Switch delay profiles during traffic | Correct operation across transitions | P1 |
| TC-BP-005 | FIFO full condition | Fill internal buffers (reads and writes) | Backpressure asserted; no overflow or drop | P0 |
| TC-BP-006 | FIFO empty/underrun | Starve data channel | No spurious data; no underflow | P0 |
| TC-BP-007 | Throughput measurement | Sustained max-rate traffic | Measured throughput meets spec target | P1 |
| TC-BP-008 | Latency measurement | Isolated transactions | Latency within spec | P1 |
| TC-BP-009 | Simultaneous read and write | Saturate both directions | Neither direction starved; correct data | P0 |

### 6.11 AXI4-Lite (F-15)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-LITE-001 | Single read/write | Basic register access | Correct data and OKAY | P0 |
| TC-LITE-002 | No burst | Verify AxLEN is not used (single beat only) | Every access is one transfer | P0 |
| TC-LITE-003 | Full-width accesses only | Check access size equals data bus width | Compliant | P0 |
| TC-LITE-004 | WSTRB on 32-bit registers | Byte-wise writes | Only strobed bytes updated | P0 |
| TC-LITE-005 | Independent AW and W | Send W before/after AW | Correct write regardless of order | P0 |
| TC-LITE-006 | Back-to-back register access | Continuous accesses | No corruption | P1 |
| TC-LITE-007 | Error response | Access invalid address | SLVERR or DECERR per design | P0 |
| TC-LITE-008 | Write-read ordering | Write then immediate read | Read returns new value | P0 |
| TC-LITE-009 | Register map sweep | Walk all registers: reset value, R/W, RO, WO, W1C behavior | Matches register spec | P0 |

### 6.12 AXI4-Stream (F-16, if applicable)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-STR-001 | Basic packet | TDATA with TLAST | Packet delivered intact | P0 |
| TC-STR-002 | TVALID stability | TREADY low after TVALID | TVALID and payload held | P0 |
| TC-STR-003 | TKEEP / TSTRB | Null, position, and data bytes | Handled per spec | P1 |
| TC-STR-004 | TLAST variations | Length-1 packets, long packets | Correct packet boundaries | P0 |
| TC-STR-005 | TID / TDEST routing | Multiple IDs/destinations | Routed correctly | P1 |
| TC-STR-006 | TUSER propagation | Random TUSER | Unchanged | P2 |
| TC-STR-007 | Backpressure | Random TREADY | No data loss | P0 |
| TC-STR-008 | Continuous streaming | Full-rate traffic | Full throughput | P1 |

### 6.13 Interconnect and Bridge Features (F-17, if applicable)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-IC-001 | Address decode — each slave | Access every slave's address range (first, middle, last address) | Routed to correct slave | P0 |
| TC-IC-002 | Address decode — gaps | Access unmapped holes | DECERR | P0 |
| TC-IC-003 | Arbitration — fairness | Multiple masters contend for one slave | No starvation | P0 |
| TC-IC-004 | Arbitration — QoS / priority | Mixed priorities | Priority honored per config | P1 |
| TC-IC-005 | ID widening/remap | Multiple masters with identical IDs | Responses routed back to correct master | P0 |
| TC-IC-006 | Data width upsizing | Narrow master to wide slave | Data/strobes aligned correctly | P0 |
| TC-IC-007 | Data width downsizing | Wide master to narrow slave | Bursts split correctly; response merged | P0 |
| TC-IC-008 | Clock domain crossing | Run with asynchronous clocks | No data loss or duplication | P0 |
| TC-IC-009 | Protocol conversion (e.g., AXI to AXI-Lite, AXI to APB) | Mixed traffic | Correct conversion | P1 |
| TC-IC-010 | Concurrent traffic to different slaves | Parallel masters, different targets | Full parallelism | P1 |
| TC-IC-011 | Read/write hazards across masters | Conflicting accesses | No deadlock | P0 |
| TC-IC-012 | Deadlock scenarios | Cyclic dependencies between masters and slaves | No deadlock | P0 |
| TC-IC-013 | Slave error propagation | SLVERR from one slave among many | Delivered to the correct master only | P0 |

### 6.14 Low-Power Interface (F-20, if applicable)

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-LP-001 | Clock gating request/accept | CSYSREQ low with no traffic | CSYSACK handshake correct; clock may stop | P1 |
| TC-LP-002 | Deny low-power entry | Traffic active during request | CACTIVE high / request denied | P1 |
| TC-LP-003 | Wake-up | Raise CSYSREQ after low power | Traffic resumes correctly | P1 |
| TC-LP-004 | Traffic after wake | Run full traffic post wake-up | No corruption | P1 |

### 6.15 Random and Stress Tests

| ID | Title | Stimulus | Expected result | Pri |
|---|---|---|---|---|
| TC-RND-001 | Fully constrained random | Random len/size/burst/ID/address/delay/response | Zero scoreboard and assertion failures | P0 |
| TC-RND-002 | Long-duration soak | ≥ 10 million transactions | No failures, no deadlock | P0 |
| TC-RND-003 | Random reset injection | Reset at random times under traffic | Clean recovery every time | P0 |
| TC-RND-004 | Corner-weighted random | Bias to len=0, len=max, 4KB edges, wrap edges | Zero failures | P0 |
| TC-RND-005 | Many-master / many-slave random | Full topology random | Zero failures | P1 |
| TC-RND-006 | Seed regression | Run N seeds per test | Pass rate target per Section 10 | P0 |

---

## 7. Negative / Protocol Violation Tests

These tests drive illegal stimulus to confirm the protocol checker detects violations. They are run in a separate "checker validation" suite and are expected to fail with the specific assertion named.

| ID | Violation injected | Expected assertion to fire |
|---|---|---|
| NEG-001 | VALID deasserted before READY | `p_valid_stable_*` |
| NEG-002 | Payload changed while VALID high and READY low | `p_payload_stable_*` |
| NEG-003 | WLAST asserted early | `p_wlast_position` |
| NEG-004 | WLAST missing on final beat | `p_wlast_position` |
| NEG-005 | Burst crosses 4KB | `p_no_4kb_cross` |
| NEG-006 | WRAP burst with illegal length (e.g., 3 beats) | `p_wrap_len_legal` |
| NEG-007 | WRAP burst with unaligned address | `p_wrap_addr_aligned` |
| NEG-008 | Size larger than data bus width | `p_size_le_bus` |
| NEG-009 | FIXED burst longer than 16 beats | `p_fixed_len_le_16` |
| NEG-010 | BVALID asserted before WLAST handshake | `p_bvalid_after_wlast` |
| NEG-011 | RVALID asserted before AR handshake | `p_rvalid_after_ar` |
| NEG-012 | RLAST on wrong beat | `p_rlast_position` |
| NEG-013 | Response ID with no matching outstanding request | `p_id_match` |
| NEG-014 | VALID high during reset / on first cycle after reset | `p_reset_valid_low` |
| NEG-015 | Same-ID responses out of order | `p_same_id_order` |
| NEG-016 | Exclusive access with illegal size/alignment | `p_excl_legal` |
| NEG-017 | Attribute signals change mid-burst | `p_attr_stable` |
| NEG-018 | EXOKAY returned to a non-exclusive access | `p_exokay_only_excl` |

---

## 8. Protocol Assertions (SVA)

The following rules are bound to every AXI interface and enabled in all tests.

### 8.1 Handshake
- Once `xVALID` is asserted, it stays asserted until `xREADY` is high on a clock edge.
- While `xVALID && !xREADY`, all payload signals of that channel are stable.
- After `ARESETn` deasserts, `AWVALID`, `WVALID`, `ARVALID`, `BVALID`, `RVALID` are low on the first rising clock edge.
- `xVALID` is never X/Z after reset; payload is never X/Z when `xVALID` is high.

### 8.2 Burst and Address
- `AxBURST` is not the reserved value.
- `AxSIZE` ≤ log2(data bus bytes).
- WRAP: length is 2, 4, 8, or 16 beats; start address aligned to transfer size.
- FIXED: length ≤ 16 beats.
- INCR: length ≤ 256 beats.
- A burst does not cross a 4KB address boundary.
- `AxLEN`, `AxSIZE`, `AxBURST`, `AxCACHE`, `AxPROT`, `AxLOCK` are stable while the request is pending.

### 8.3 Write Channel
- `WLAST` is asserted on, and only on, the beat number `AWLEN + 1`.
- `BVALID` is asserted only after the `AW` handshake and the final `W` handshake.
- `BID` corresponds to an outstanding write.
- `WSTRB` bits are low for byte lanes outside the active lanes of a narrow transfer.
- Number of `W` beats matches `AWLEN + 1` for each write.

### 8.4 Read Channel
- `RVALID` is asserted only after the `AR` handshake.
- `RLAST` is asserted on, and only on, the beat number `ARLEN + 1`.
- `RID` corresponds to an outstanding read.
- Responses to reads with the same ID return in order.

### 8.5 Response
- `EXOKAY` is returned only to exclusive accesses.
- Write responses are issued one per write burst.
- No response is issued without a matching outstanding request.

### 8.6 Liveness (formal or timeout-based)
- Every request eventually receives a response (bounded by a configurable timeout).
- No channel remains stalled forever when the peer is ready.

---

## 9. Functional Coverage

### 9.1 Coverage Groups

| Group | Coverpoints |
|---|---|
| Burst | `AxBURST` × `AxLEN` (0, 1, 2–3, 4–7, 8–15, 16–63, 64–254, 255) × `AxSIZE` |
| Address | Alignment (aligned/unaligned for each size) × burst type; 4KB-edge hit; wrap-boundary hit; each decode region first/last address |
| Strobe | Full, partial, sparse, zero × transfer size |
| ID | Each ID value used; same-ID multiple outstanding; cross-ID reordering seen |
| Outstanding | Depth 1…max for reads and writes; max-depth hit |
| Response | OKAY, EXOKAY, SLVERR, DECERR × read/write × burst length |
| Handshake delay | Delay bins (0, 1, 2–4, 5–16, 17+) per channel × each of VALID-first / READY-first / simultaneous |
| Channel order | W before AW, AW before W, simultaneous |
| Concurrency | Read and write active simultaneously; multiple masters active |
| Exclusive | Success, failure (intervening write), no-prior-read, size × length |
| Attributes | `AxCACHE`, `AxPROT`, `AxQOS`, `AxREGION` values |
| Reset | Reset in each state: idle, mid-AW, mid-W, wait-B, mid-AR, mid-R |
| Errors | Error response at first/middle/last beat; error with outstanding traffic |
| Cross | Burst type × size × length × alignment; ID × outstanding depth; response × burst type |

### 9.2 Coverage Targets
| Metric | Target |
|---|---|
| Functional coverage | 100% of defined bins (with documented waivers) |
| Line / statement coverage | ≥ 98% |
| Branch coverage | ≥ 95% |
| Toggle coverage | ≥ 95% |
| FSM state / transition coverage | 100% reachable |
| Assertion coverage (cover properties hit) | 100% |

---

## 10. Pass/Fail and Exit Criteria

### 10.1 Pass/Fail for a Test
A test passes when all of the following hold:
- No scoreboard mismatches.
- No SVA assertion failures (except in negative-test suite where specific failures are expected).
- No UVM errors or fatals.
- All issued transactions receive responses before end of test.
- No X/Z propagation on checked signals.
- No deadlock or timeout.

### 10.2 Exit Criteria
- All P0 test cases pass.
- ≥ 95% of P1 test cases pass; remaining failures have documented issues and waivers.
- Coverage targets in Section 9.2 met, or gaps reviewed and waived.
- Regression pass rate ≥ 99% over the last 3 consecutive full regressions with different seed sets.
- Zero open severity-1 or severity-2 bugs.
- All negative tests confirm that the corresponding assertion fires.
- Review sign-off from design and verification leads.

---

## 11. Regression Plan

| Level | Contents | Frequency | Seeds |
|---|---|---|---|
| Smoke | TC-RST-001, TC-WR-001, TC-RD-001, one random test | Every commit | 1 |
| Nightly | All directed tests + random tests | Nightly | 5–10 per random test |
| Weekly | Full suite + soak + all parameter configurations | Weekly | 50+ per random test |
| Pre-release | Full suite across the entire configuration matrix, gate-level (if applicable) | Before milestone | 100+ |

Failures are triaged within one working day; each failure is logged with seed, test name, and waveform pointer.

---

## 12. Environment and Tools

| Item | Choice (edit as needed) |
|---|---|
| Language / methodology | SystemVerilog, UVM 1.2 |
| Simulator | Questa / VCS / Xcelium |
| AXI VIP | Vendor VIP or in-house agent |
| Formal tools | JasperGold / VC Formal (optional) |
| Coverage tools | Simulator-native, merged via vendor tool |
| Regression management | Jenkins / Slurm / in-house scripts |
| Bug tracking | Jira / equivalent |
| Version control | Git |

---

## 13. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Ambiguity in spec interpretation (e.g., optional features) | False failures or missed bugs | Document design decisions; review with architects |
| VIP and DUT disagree on optional behavior | Wasted debug time | Configure VIP to DUT's supported feature set; review VIP settings |
| Coverage holes in cross-products | Missed corner cases | Add directed tests; review cross bins for reachability |
| Deadlock in rare arbitration cases | Late-found critical bug | Run formal deadlock checks; long soak tests |
| Parameter space too large | Incomplete coverage | Prioritize min/max/typical; use random configuration |
| Late spec changes | Plan churn | Version-control plan; track changes in traceability matrix |

---

## 14. Deliverables

- This test plan (reviewed and approved).
- Testbench source and sequence library.
- SVA protocol checker bound to all interfaces.
- Regression scripts and configuration files.
- Coverage reports and waiver list.
- Test results summary and bug report.
- Final sign-off report.

---

## Appendix A — Traceability Matrix

| Feature | Test cases |
|---|---|
| F-01 Reset | TC-RST-001…008 |
| F-02 Handshake | TC-HS-001…008 |
| F-03 Write channels | TC-WR-001…015 |
| F-04 Read channels | TC-RD-001…009 |
| F-05 Burst types | TC-BST-001…006, 015 |
| F-06 Size / alignment / strobe | TC-BST-010…014, TC-WR-012…014 |
| F-07 4KB rule | TC-BST-007…009 |
| F-08 IDs and ordering | TC-ID-001…007, 010…014 |
| F-09 Outstanding | TC-ID-008, 009 |
| F-10 Responses | TC-RSP-001…012 |
| F-11 Exclusive | TC-EX-001…009 |
| F-12 Attributes | TC-ATTR-001…008 |
| F-13 Backpressure | TC-BP-001…006, 009 |
| F-14 Channel dependencies | TC-WR-004…006 |
| F-15 AXI4-Lite | TC-LITE-001…009 |
| F-16 AXI4-Stream | TC-STR-001…008 |
| F-17 Interconnect | TC-IC-001…013 |
| F-18 Error handling | TC-RSP-002…010, TC-RND-003 |
| F-19 Performance | TC-BP-007, 008 |
| F-20 Low power | TC-LP-001…004 |
| All | TC-RND-001…006, NEG-001…018 |

## Appendix B — Quick Reference of Key Protocol Rules

| Topic | Rule |
|---|---|
| Response encoding | 00 OKAY, 01 EXOKAY, 10 SLVERR, 11 DECERR |
| INCR burst length (AXI4) | 1–256 beats |
| WRAP burst length | 2, 4, 8, or 16 beats |
| FIXED burst length | 1–16 beats |
| 4KB rule | A burst must not cross a 4KB boundary |
| Transfer size | 1, 2, 4, 8, 16, 32, 64, 128 bytes; not wider than the data bus |
| VALID rule | VALID must not wait for READY; once asserted it stays until handshake |
| Write response | BVALID only after AW accepted and last W beat accepted |
| Read data | RVALID only after AR accepted |
| Same-ID ordering | Same-ID transactions complete in order |
| Exclusive access | Power-of-2 total bytes (≤ 128), address aligned to total bytes, ≤ 16 beats |
| Reset | VALID signals low during reset and on the first clock edge after release |
