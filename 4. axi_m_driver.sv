class axi_m_driver #(parameter int DATA_WIDTH = 64) extends uvm_driver #(axi_transaction);

  `uvm_component_param_utils(axi_m_driver #(DATA_WIDTH))

  virtual axi_if vif;

  // pending requests keyed by AXI ID, oldest first within an ID
  axi_transaction pending_read  [bit [3:0]][$];
  axi_transaction pending_write [bit [3:0]][$];

  function new(string name = "axi_m_driver", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "No virtual interface present")
  endfunction

  // ---------------- idle / reset ----------------
  task drive_idle();
    vif.cb.awvalid <= 1'b0;
    vif.cb.wvalid  <= 1'b0;
    vif.cb.wlast   <= 1'b0;
    vif.cb.arvalid <= 1'b0;
    vif.cb.bready  <= 1'b0;
    vif.cb.rready  <= 1'b0;
    // vif.cb.wstrb <= '1;   // strobes not used: tie all ones here, if the port exists
  endtask

  // ---------------- request channels ----------------
  // Pattern: drive, wait one edge, test the sampled READY, repeat, then drop VALID.
  task write_addr_channel(axi_transaction txn);
    vif.cb.awvalid <= 1'b1;
    vif.cb.awaddr  <= txn.addr;
    vif.cb.awlen   <= txn.len;
    vif.cb.awsize  <= txn.size;
    vif.cb.awburst <= txn.burst;
    vif.cb.awid    <= txn.id;
    do @(vif.cb); while (!vif.cb.awready);
    vif.cb.awvalid <= 1'b0;
  endtask

  task write_data_channel(axi_transaction txn);
    for (int i = 0; i <= txn.len; i++) begin
      vif.cb.wvalid <= 1'b1;
      vif.cb.wdata  <= txn.data[i];
      vif.cb.wlast  <= (i == txn.len);
      do @(vif.cb); while (!vif.cb.wready);   // next beat (if any) is driven at this same edge
    end
    vif.cb.wvalid <= 1'b0;
    vif.cb.wlast  <= 1'b0;
  endtask

  task read_addr_channel(axi_transaction txn);
    vif.cb.arvalid <= 1'b1;
    vif.cb.araddr  <= txn.addr;
    vif.cb.arlen   <= txn.len;
    vif.cb.arsize  <= txn.size;
    vif.cb.arburst <= txn.burst;
    vif.cb.arid    <= txn.id;
    do @(vif.cb); while (!vif.cb.arready);
    vif.cb.arvalid <= 1'b0;
  endtask

  task drive_write_txn(axi_transaction txn);
    pending_write[txn.id].push_back(txn);   // queued BEFORE any response can exist
    fork
      write_addr_channel(txn);
      write_data_channel(txn);
    join
  endtask

  task drive_read_txn(axi_transaction txn);
    txn.data.delete();                      // results start empty
    txn.rresp.delete();
    pending_read[txn.id].push_back(txn);
    read_addr_channel(txn);
  endtask

  // ---------------- response collectors (forked once) ----------------
  task poll_read_resp();
    axi_transaction     t;
    bit [3:0]           id;
    vif.cb.rready <= 1'b1;                  // held high for this first version
    forever begin
      @(vif.cb);
      if (vif.cb.rvalid) begin
        id = vif.cb.rid;
        if (!pending_read.exists(id) || pending_read[id].size() == 0) begin
          `uvm_error(get_type_name(), $sformatf("R beat with unknown RID %0d, dropped", id))
        end
        else begin
          t = pending_read[id][0];          // head of this ID's queue
          t.data.push_back(vif.cb.rdata);
          t.rresp.push_back(vif.cb.rresp);
          if (vif.cb.rlast != (t.data.size() == t.len + 1))
            `uvm_error(get_type_name(), $sformatf("RLAST/beat count mismatch: id=%0d beats=%0d len+1=%0d",
                                                   id, t.data.size(), t.len + 1))
          if (vif.cb.rlast) begin
            void'(pending_read[id].pop_front());
            if (pending_read[id].size() == 0) pending_read.delete(id);
            seq_item_port.put_response(t);
          end
        end
      end
    end
  endtask

  task poll_write_resp();
    axi_transaction t;
    bit [3:0]       id;
    vif.cb.bready <= 1'b1;                  // held high for this first version
    forever begin
      @(vif.cb);
      if (vif.cb.bvalid) begin
        id = vif.cb.bid;
        if (!pending_write.exists(id) || pending_write[id].size() == 0) begin
          `uvm_error(get_type_name(), $sformatf("B response with unknown BID %0d, dropped", id))
        end
        else begin
          t = pending_write[id].pop_front();
          t.bresp = vif.cb.bresp;
          if (pending_write[id].size() == 0) pending_write.delete(id);
          seq_item_port.put_response(t);
        end
      end
    end
  endtask

  // ---------------- top level ----------------
  task drive_the_dut(axi_transaction txn);
    @(vif.cb);                              // align to a clock edge before driving
    if (txn.txn_t == WRITE_TXN)      drive_write_txn(txn);
    else if (txn.txn_t == READ_TXN)  drive_read_txn(txn);
  endtask

  virtual task run_phase(uvm_phase phase);
    drive_idle();
    wait (vif.cb.rst_n === 1'b1);           // level wait; assumes active-low reset
    @(vif.cb);
    fork
      poll_read_resp();
      poll_write_resp();
    join_none
    forever begin
      seq_item_port.get_next_item(req);
      drive_the_dut(req);
      seq_item_port.item_done();
    end
  endtask

endclass : axi_m_driver

////////////////////////////////// My version ////////////////////////////////////////////
class axi_m_driver #(parameter int DATA_WIDTH = 64) extends uvm_driver #(axi_transaction);

  `uvm_component_utils(axi_m_driver #(DATA_WIDTH))

  virtual interface axi_if vif;

  function new (string name = "axi_m_driver", uvm_component parent);
    super.new(name, parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db #(virtual interface axi_if)::get(this, "", "vif", vif) ) 
      `uvm_fatal(get_type_name(), "No virtual interface present");
  endfunction : build_phase
  
  axi_transaction pending_read[bit [3:0]][$];
  axi_transaction pending_write[bit [3:0]][$];
  bit [DATA_WIDTH-1:0] read_data[bit [3:0]][$];
  bit [1:0] read_resp[bit [3:0]][$];

  task write_addr_channel(axi_transaction txn);
    // drive the write address channel
    //No need to caclulate the address for the write data channel - managed by slave
    vif.cb.awvalid <= 1'b1;
    vif.cb.awaddr <= txn.addr;
    vif.cb.awlen <= txn.len;
    vif.cb.awsize <= txn.size;
    vif.cb.awburst <= txn.burst;
    vif.cb.awid <= txn.id;
    while(!vif.cb.awready) @(vif.cb);  //wait for the slave to accept the address
    vif.cb.awvalid <= 1'b0; //drop the valid signal in next cycle once sampled
    @(vif.cb);  //wait for the next clock cycle
  endtask : write_addr_channel

  task write_data_channel(axi_transaction txn);
    // drive the write data channel
    //No need to check if the if the txn is FIXED, WRAP OR INCR - data driving logic remains same
    //Address being handled by the slave - so just drive the data as per len
    
    for(int i=0; i<(txn.len+1); i++) begin
      vif.cb.wvalid <= 1'b1;
      vif.cb.wdata <= txn.data[i];
      if(i == (txn.len)) vif.cb.wlast <= 1'b1;
      else vif.cb.wlast <= 1'b0;
      while(!vif.cb.wready) @(vif.cb) ;  //wait for the slave to accept the data
      if(!vif.cb.wlast) @(vif.cb);  //wait for the next clock cycle
    end
    vif.cb.wvalid <= 1'b0; 
    vif.cb.wlast <= 1'b0;
  endtask : write_data_channel

  task drive_write_txn(axi_transaction txn);
    fork 
      write_addr_channel(txn);
      write_data_channel(txn);
    join
    pending_write[txn.id].push_back(txn);   //push the transaction to the pending write response queue
  endtask : drive_write_txn

  task read_addr_channel(axi_transaction txn);
    // drive the read address channel
    //No need to caclulate the address for the write data channel - managed by slave
    vif.cb.arvalid <= 1'b1;
    vif.cb.araddr <= txn.addr;
    vif.cb.arlen <= txn.len;d
    vif.cb.arsize <= txn.size;
    vif.cb.arburst <= txn.burst;
    vif.cb.arid <= txn.id;
    while(!vif.cb.arready) @(vif.cb);  //wait for the slave to accept the address
    vif.cb.arvalid <= 1'b0;    
    @(vif.cb);  //wait for the next clock cycle
  endtask : read_addr_channel

  task drive_read_txn(axi_transaction txn);
    read_addr_channel(txn);
    pending_read[txn.id].push_back(txn);   //push the transaction to the pending read response queue  
  endtask : drive_read_txn

  task poll_read_resp();
    axi_transaction resp_txn;
    //sampling the read data and storing the response in buffer until the last signal is asserted, then send the response to the sequencer
    forever begin      
      vif.cb.rready <= 1'b1;  //assert the ready for data to be received
      while(!vif.rvalid) @(vif.cb);
      while(!pending_read.exists(vif.cb.rid)) 
          `uvm_fatal("DRIVER", "Unexpected response received from the slave with no pending read transaction for the response id");
      if(vif.rvalid) begin  //rready is already high, so if rvalid is high, then data is available to be sampled
        read_data[vif.cb.rid].push_back(vif.cb.rdata);
        read_resp[vif.cb.rid].push_back(vif.cb.rresp);
      end 
      if(vif.cb.rlast) begin
        vif.cb.rready <= 1'b0;  //de-assert the ready for data to be received
        resp_txn = pending_read[vif.cb.rid].pop_front();  //pop the transaction from the pending read response queue
        resp_txn.data = read_data[vif.cb.rid];
        resp_txn.rresp = read_resp[vif.cb.rid];
        read_data[vif.cb.rid].delete();
        read_resp[vif.cb.rid].delete();
        //set_id_info(resp_txn); //not required in this case
        seq_item_port.put_response(resp_txn);
        if(pending_read[resp_txn.id].size() == 0) pending_read.delete(resp_txn.id);
      end
      @(vif.cb);  //wait for the next clock cycle
    end
  endtask : poll_read_resp

  task poll_write_resp();
    axi_transaction resp_txn;
    forever begin
      vif.cb.bready <= 1'b1;  //assert the ready for data to be received
      while(!vif.cb.bvalid) @(vif.cb);
      while(!pending_write.exists(vif.cb.bid))
          `uvm_fatal("TIMEOUT", $sformatf("No pending write response transaction found for the response id: %0d", vif.cb.bid));
      resp_txn = pending_write[vif.cb.bid].pop_front();  //pop the transaction from the pending write response queue
      resp_txn.bresp = vif.cb.bresp;
      //send the response
      //set_id_info(resp_txn);//not required in this case
      seq_item_port.put_response(resp_txn);
      if(pending_write[resp_txn.id].size() == 0) pending_write.delete(resp_txn.id);  //delete the queue if all the transactions are completed
      vif.cb.bready <= 1'b0;  //de-assert the ready for data to be received
      @(vif.cb);  //wait for the next clock cycle
    end
  endtask : poll_write_resp

  task drive_the_dut(axi_transaction txn);
    if(txn.txn_t == WRITE_TXN)
      drive_write_txn(txn);
    else if(txn.txn_t == READ_TXN)
      drive_read_txn(txn);
  endtask : drive_the_dut
    
  virtual task run_phase(uvm_phase phase);
    //wait for dut to come out of reset
    @(vif.cb.rst_n);
    fork
      poll_read_resp();
      poll_write_resp();
    join_none
    forever begin
      seq_item_port.get_next_item(req);
      drive_the_dut(req);
      seq_item_port.item_done();
    end
  endtask : run_phase
      
endclass : axi_m_driver
