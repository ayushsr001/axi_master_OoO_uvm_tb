class axi_m_driver extends uvm_driver #(axi_transaction);

  `uvm_component_utils(axi_m_driver)

  virtual interface axi_if vif;

  function new (string name = "axi_m_driver", uvm_component parent);
    super.new(name, parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db #(virtual interface axi_if)::get(this, "", "vif", vif) ) 
      `uvm_error("[DRV] : no vif present", UVM_MEDIUM);
  endfunction : build_phase
  
  axi_transaction pending_read[bit [3:0]][$];
  axi_transaction pending_write[bit [3:0]][$];

  task write_addr_channel(axi_transaction txn);
    // drive the write address channel
    //No need to caclulate the address for the write data channel - managed by slave
    vif.cb.awvalid <= 1'b1;
    vif.cb.awaddr <= txn.addr;
    vif.cb.awlen <= txn.len;
    vif.cb.awsize <= txn.size;
    vif.cb.awburst <= txn.burst;
    vif.cb.awid <= txn.id;
    do @(posedge vif.cb) while(!vif.cb.awready);  //wait for the slave to accept the address
    vif.cb.awvalid <= 1'b0;
  endtask : write_addr_channel

  task write_data_channel(axi_transaction txn);
    // drive the write data channel
    //No need to check if the if the txn is FIXED, WRAP OR INCR - data driving logic remains same
    //Address being handled by the slave - so just drive the data as per len
    for(int i=0; i<(txn.len+1); i++) begin
      vif.cb.wvalid <= 1'b1;
      vif.cb.wdata <= txn.data[i];
      if(i == txn.len) vif.cb.wlast <= 1'b1;
      else vif.cb.wlast <= 1'b0;
      do @(vif.cb) while(!vif.cb.wready);  //wait for the slave to accept the data
      vif.cb.wvalid <= 1'b0;
      vif.cb.wlast <= 1'b0;
    end
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
    vif.cb.arlen <= txn.len;
    vif.cb.arsize <= txn.size;
    vif.cb.arburst <= txn.burst;
    vif.cb.arid <= txn.id;
    do @(vif.cb) while(!vif.cb.arready);  //wait for the slave to accept the address
    vif.cb.arvalid <= 1'b0;
  endtask : read_addr_channel

  task drive_read_txn(axi_transaction txn);
    read_addr_channel(txn);
    pending_read[txn.id].push_back(txn);   //push the transaction to the pending read response queue  
  endtask : drive_read_txn

  task poll_read_resp();
    forever begin
      automatic int count = 0;
      axi_transaction resp_txn;
      vif.cb.rready <= 1'b1;  //assert the ready for data to be received
      do @(vif.cb) while(!vif.cb.rvalid);
      while(!pending_read.exists(vif.cb.rid)) begin
        `uvm_error($sformatf("UNEXPECTED: id=%0d", vif.cb.rid), UVM_MEDIUM);
        @(vif.cb);
        count++;
        if(count > 100) begin
          `uvm_fatal("TIMEOUT", "No pending read transaction found for the response id");
        end
      end
      resp_txn = pending_read[vif.cb.rid].pop_front();  //pop the transaction from the pending read response queue
      forever begin
        do @(vif.cb) while(!vif.cb.rvalid);
        resp_txn.data.push_back(vif.cb.rdata);
        resp_txn.rresp.push_back(vif.cb.rresp);
        if(vif.cb.rlast) begin
          vif.cb.rready <= 1'b0;  //deassert the ready for data to be received
          break;
        end
      end
      //send the response
      set_id_info(resp_txn);
      seq_item_port.put_response(resp_txn);
      if(pending_read[resp_txn.id].size() == 0) pending_read.delete(resp_txn.id);  //delete the queue if all the transactions are completed
    end
  endtask : poll_read_resp

  task poll_write_resp();
    forever begin
      automatic int count = 0;
      axi_transaction resp_txn;
      vif.cb.bready <= 1'b1;  //assert the ready for data to be received
      do @(vif.cb) while(!vif.cb.bvalid);
      while(!pending_write.exists(vif.cb.bid)) begin
        `uvm_error($sformatf("UNEXPECTED: id=%0d", vif.cb.bid), UVM_MEDIUM);
        @(vif.cb);
        count++;
        if(count > 100) begin
          `uvm_fatal("TIMEOUT", "No pending write response transaction found for the response id");
        end
      end
      resp_txn = pending_write[vif.cb.bid].pop_front();  //pop the transaction from the pending write response queue
      resp_txn.bresp = vif.cb.bresp;
      vif.cb.bready <= 1'b0;  //deassert the ready for data to be received
      //send the response
      set_id_info(resp_txn);
      seq_item_port.put_response(resp_txn);
      if(pending_write[resp_txn.id].size() == 0) pending_write.delete(resp_txn.id);  //delete the queue if all the transactions are completed
    end
  endtask : poll_write_resp

  task drive_the_dut(axi_transaction txn);
    if(txn.txn_t == WRITE_TXN)  drive_write_txn(txn);
    else if(txn.txn_t == READ_TXN) drive_read_txn(txn);
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
