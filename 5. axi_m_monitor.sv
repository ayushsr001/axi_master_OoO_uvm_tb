class axi_monitor #(parameter int DATA_WIDTH = 64) extends uvm_monitor;

  `uvm_component_param_utils(axi_monitor #(DATA_WIDTH))

  virtual axi_if vif;
  uvm_analysis_port #(axi_transaction) ap;

  // write assembly: address phases and data bursts are paired by arrival order
  axi_transaction        aw_q[$];                      // AW seen, waiting for its W burst
  bit [DATA_WIDTH-1:0]   w_bursts[$][$];               // complete W bursts, waiting for an AW
  bit [DATA_WIDTH-1:0]   cur_wdata[$];                 // W burst being collected

  // outstanding requests keyed by AXI ID, oldest first within an ID
  axi_transaction pending_write [bit [3:0]][$];        // paired, waiting for B
  axi_transaction pending_read  [bit [3:0]][$];        // AR seen, waiting for R beats

  function new(string name = "axi_monitor", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "No virtual interface present")
  endfunction

  // ---------------- helpers ----------------
  // Pair the oldest AW with the oldest complete W burst (either may arrive first)
  function void pair_writes();
    axi_transaction t;
    while (aw_q.size() > 0 && w_bursts.size() > 0) begin
      t      = aw_q.pop_front();
      t.data = w_bursts.pop_front();
      if (t.data.size() != t.len + 1)
        `uvm_error(get_type_name(), $sformatf("W beat count %0d != AWLEN+1 (%0d), id=%0d",
                                               t.data.size(), t.len + 1, t.id))
      pending_write[t.id].push_back(t);
    end
  endfunction

  function void flush_all();
    aw_q.delete();
    w_bursts.delete();
    cur_wdata.delete();
    pending_write.delete();
    pending_read.delete();
  endfunction

  // ---------------- channel processes ----------------
  task collect_aw();
    axi_transaction t;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n && vif.mon_cb.awvalid && vif.mon_cb.awready) begin
        t       = axi_transaction::type_id::create("wr_txn");
        t.txn_t = WRITE_TXN;
        t.addr  = vif.mon_cb.awaddr;
        t.len   = vif.mon_cb.awlen;
        t.size  = vif.mon_cb.awsize;
        t.burst = vif.mon_cb.awburst;
        t.id    = vif.mon_cb.awid;
        aw_q.push_back(t);
        pair_writes();
      end
    end
  endtask

  task collect_w();
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n && vif.mon_cb.wvalid && vif.mon_cb.wready) begin
        cur_wdata.push_back(vif.mon_cb.wdata);
        if (vif.mon_cb.wlast) begin
          w_bursts.push_back(cur_wdata);     // queue is copied into the outer queue
          cur_wdata.delete();
          pair_writes();
        end
      end
    end
  endtask

  task collect_b();
    axi_transaction t;
    bit [3:0]       id;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n && vif.mon_cb.bvalid && vif.mon_cb.bready) begin
        id = vif.mon_cb.bid;
        if (!pending_write.exists(id) || pending_write[id].size() == 0) begin
          `uvm_error(get_type_name(), $sformatf("B response with no pending write, BID=%0d", id))
        end
        else begin
          t       = pending_write[id].pop_front();
          t.bresp = vif.mon_cb.bresp;
          if (pending_write[id].size() == 0) pending_write.delete(id);
          ap.write(t);                       // write is complete at B
        end
      end
    end
  endtask

  task collect_ar();
    axi_transaction t;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n && vif.mon_cb.arvalid && vif.mon_cb.arready) begin
        t       = axi_transaction::type_id::create("rd_txn");
        t.txn_t = READ_TXN;
        t.addr  = vif.mon_cb.araddr;
        t.len   = vif.mon_cb.arlen;
        t.size  = vif.mon_cb.arsize;
        t.burst = vif.mon_cb.arburst;
        t.id    = vif.mon_cb.arid;
        pending_read[t.id].push_back(t);
      end
    end
  endtask

  task collect_r();
    axi_transaction t;
    bit [3:0]       id;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n && vif.mon_cb.rvalid && vif.mon_cb.rready) begin
        id = vif.mon_cb.rid;
        if (!pending_read.exists(id) || pending_read[id].size() == 0) begin
          `uvm_error(get_type_name(), $sformatf("R beat with no pending read, RID=%0d", id))
        end
        else begin
          t = pending_read[id][0];           // head of this ID's queue
          t.data.push_back(vif.mon_cb.rdata);
          t.rresp.push_back(vif.mon_cb.rresp);
          if (vif.mon_cb.rlast != (t.data.size() == t.len + 1))
            `uvm_error(get_type_name(), $sformatf("RLAST mismatch: id=%0d beats=%0d expected=%0d",
                                                   id, t.data.size(), t.len + 1))
          if (vif.mon_cb.rlast) begin
            void'(pending_read[id].pop_front());
            if (pending_read[id].size() == 0) pending_read.delete(id);
            ap.write(t);                     // read is complete at RLAST
          end
        end
      end
    end
  endtask

  task watch_reset();
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n === 1'b0) flush_all();
    end
  endtask

  // ---------------- run and end-of-test checks ----------------
  virtual task run_phase(uvm_phase phase);
    fork
      collect_aw();
      collect_w();
      collect_b();
      collect_ar();
      collect_r();
      watch_reset();
    join
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    foreach (pending_write[i])
      if (pending_write[i].size() > 0)
        `uvm_error(get_type_name(), $sformatf("%0d write(s) with ID %0d never got a B response", pending_write[i].size(), i))
    foreach (pending_read[i])
      if (pending_read[i].size() > 0)
        `uvm_error(get_type_name(), $sformatf("%0d read(s) with ID %0d never completed", pending_read[i].size(), i))
    if (aw_q.size() > 0)     `uvm_error(get_type_name(), $sformatf("%0d AW(s) never got W data", aw_q.size()))
    if (w_bursts.size() > 0) `uvm_error(get_type_name(), $sformatf("%0d W burst(s) never got an AW", w_bursts.size()))
  endfunction

endclass : axi_monitor
