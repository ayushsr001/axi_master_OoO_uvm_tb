//import the UVM ibrary

  import uvm_pkg::*
  `include "uvm_machos.svh"

//AXI Interface
    interface axi_if (a_clk, a_rstn);
      
      //Read address channel
      logic [3:0] arid;     
      logic [31:0] araddr;
      logic arvalid;
      logic arready;
      logic [1:0] arburst;    //FIXED, INCR, WRAP, 2'b11 -> RESERVED
      logic [2:0] arsize;     //0 -> 1B; 1 -> 2B, 111 -> 128B (MUST NOT EXCEED DATA WIDTH)
      logic [7:0] arlen;      // No of transfers per transactions

      //Read data channel
      logic [DATA_WIDTH-1:0] rdata;
      logic rvalid;
      logic [3:0] rid;
      logic [1:0] rresp;  // OKAY, EXOKAY, SLVERR, DECERR
      logic rlast;
      logic rready;

      //Write address channel
      logic [31:0] awaddr;
      logic awvalid;
      logic awready;
      logic [2:0] awsize;
      logic [7:0] awlen;
      logic [1:0] awburst;
      logic [3:0] awid;

      //write data channel
      logic [DATA_WIDTH-1:0] wdata;
      logic wvalid;
      logic wlast;
      logic wready;
      
      //Write response channel
      logic [1:0] bresp;
      logic bvalid;
      logic [3:0] bid;
      logic bready;


        //add TB signals here
      endclocking

      //Modports - assuming AXI SLAVE DUT
      modport DUT (input 
                   a_clk, a_rstn,
                   //read addr channel
                   arvalid, araddr, arid, arsize, arlen, arburst,
                   //read-response channel
                   rready,
                   //write-addr channel
                   awid, awaddr, awvalid, awsize, awlen, awbusrt,
                   //write-data channel
                   wdata, wvalid, wlast,
                   //write-resp channel
                   bready,
                   
                   output
                   //read addr channel
                   arready,
                   read response channel
                   rid, rdata, rlast, rvalid, rresp,
                   //write addr channel
                   awready,
                   //write data channel
                   wready,
                   //write-resp channel
                   breasp, bvalid, bid  
                  );

      //clocking block
      clocking cb @(posedge clk);
           output  //read addr channel
                   arvalid, araddr, arid, arsize, arlen, arburst,
                   //read-response channel
                   rready,
                   //write-addr channel
                   awid, awaddr, awvalid, awsize, awlen, awbusrt,
                   //write-data channel
                   wdata, wvalid, wlast,
                   //write-resp channel
                   bready;
                
            input  //read addr channel
                   arready,
                   read response channel
                   rid, rdata, rlast, rvalid, rresp,
                   //write addr channel
                   awready,
                   //write data channel
                   wready,
                   //write-resp channel
                   breasp, bvalid, bid;
      endclocking

      modport TB ( clocking cb, 
        input a_rstn);
                   
      //Constraints - Maybe in individual transaction class

    endinterface : axi_if

    /////////////////////////////// TESTBENCH TOP /////////////////////////////////

    module tb_top();

      bit a_clk, a_rstn;

      initial begin
        a_clk = 1'b0;
        forever clk = #5 !clk;
      end

      initial begin
        a_rstn = 1'b1;
        #5;
        a_rstn = 1'b0;
        #5;
        a_rstn = 1'b1;
      end

      //interface
      axi_if axi_intf(a_clk, a_rstn);

      //DUT
      axi_slave_dut (axi_intf.DUT);

      initial begin
        $dumpfile("waves.shm");
        $dumpvars();
      end

      initial begin
        //setting the virtual interface for all the components who want to access this interface.
        uvm_config_db(#virtual interface axi_if)::set(null, "*", "vif", axi_intf);
        run_test();
      end 
    endmodule

///////////////////////// TRANSACTION CLASS /////////////////////////////

    typedef enum {READ_TXN, WRITE_TXN} txn_type;

    class axi_transaction #(int DATA_WIDTH=64) extends uvm_sequence_item;

      function new(string name = "axi_transaction");
        super.new(name);
      endfunction : new

      //txn type
      rand txn_type txn_t;

      //Read address channel
      rand bit [3:0] id;     
      rand bit [31:0] addr;
      rand bit [1:0] burst;    //FIXED, INCR, WRAP, 2'b11 -> RESERVED
      rand bit [2:0] size;     //0 -> 1B; 1 -> 2B, 111 -> 128B (MUST NOT EXCEED DATA WIDTH)
      rand bit [7:0] len;      // No of transfers per transactions
      rand bit [DATA_WIDTH-1:0] data[$];
      bit [1:0] resp;          // OKAY, EXOKAY, SLVERR, DECERR

      rand bit [7:0] beat_size;
      rand bit [9:0] beat_num;
      rand bit [32:0] last_addr;
      rand bit [31:0] lower_bound, upper_bound;

      `uvm_object_utils_begin(axi_transaction)
          `uvm_field_enum(txn_type, txn_t, UVM_ALL_ON)
          `uvm_field_int( id, UVM_ALL_ON)    
          `uvm_field_int( burst, UVM_ALL_ON)
          `uvm_field_int( size, UVM_ALL_ON)
          `uvm_field_int( len, UVM_ALL_ON)
          `uvm_field_int( resp, UVM_ALL_ON)
          `uvm_field_int( addr, UVM_ALL_ON)
          `uvm_field_queue_int( data, UVM_ALL_ON)
      `uvm_object_utils_end
      
      //Constraints
      constraint beat_size_c { beat_size == (1 << size); }
      constraint beat_num_c { beat_num == len + 9'd1; }
      constraint bound_c { lower_bound == (addr - addr % (beat_size * beat_num) ); 
                           upper_bound == lower_bound + beat_size * (beat_num-1); 
                         }
      constraint axi_data { txn_t == WRITE_TXN -> data.size() == (beat_num);}
      constraint boundary_4k {
        last_addr[31:12] == addr[31:12];            //next address within the same 4k boundary
        if( burst != 2'b00) {last_addr % beat_size == 0; }              //end addr 4k aligned
                             }
      constraint burst_c { burst != 2'b11; }
      constraint size_c { size <= $clog2(DATA_WIDTH); }
      constraint axi_burst_c { 
        if (burst == 2'b01) {                                 //INCR
        (beat_num) inside {[1:256]};                          //1 to 256 beats
        last_addr == (33'd0 + addr + (beat_num - 1) * beat_size) - (33'd0 + addr + (beat_num - 1) * beat_size) % beat_size; 
              }  
        else if (burst == 2'b00) { (beat_num) inside {[1:16]};   //FIXED
                                 last_addr == addr; 
                                 }     
        else if (burst == 2'b10) 
        { (beat_num) inside {2,4,8,16};                          //WRAP
         if( lower_bound == addr) {last_addr == upper_bound; }                    //address aligned wrt size 
           else {last_addr == addr - beat_size; } 
          }                
        }
      
    endclass : axi_transaction

 /////////////////////////// MONITOR ////////////////////////////////////////////

  class axi_m_monitor extends uvm_component;

      `uvm_component_utils("axi_m_monitor")

      virtual interface axi_if vif;

      function new (string name = "axi_m_monitor", uvm_component parent);
        super.new(name, parent);
      endfunction

      function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db(#virtual interface axi_if)::get( this, "", "vif", vif))
          `uvm_error("[MON] NO-VIF present", UVM_MEDIUM);
      endfunction : build_phase

      extern task sample_aw();
      extern task sample_wr();
      extern task sample_wr_resp();
      extern task sample_ar();
      extern task sample_rd();
          
      task run_phase(uvm_phase phase);
        fork begin
          sample_aw();
          sample_wr();
          sample_wr_resp();
          sample_ar();
          sample_rd();
        end
      endtask : run_phase

  endclass


 /////////////////////////// DRIVER ////////////////////////////////////////////            
            
  class axi_m_driver extends uvm_driver #(axi_transaction);
  
    `uvm_component_utils(axi_m_driver)
  
    virtual interface axi_if vif;
  
    function new (string name = "axi_m_driver", uvm_component parent);
      super.new(name, parent);
    endfunction : new
  
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(!uvm_config_db(#virtual interface axi_if)::get(this, "", "vif", vif) ) 
        `uvm_error("[DRV] : no vif present", UVM_MEDIUM);
    endfunction : build_phase
    
    int pending_read[bit [3:0]][$];
    int pending_write[bit [3:0]][$];

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
        do @(posedge vif.cb) while(!vif.cb.wready);  //wait for the slave to accept the data
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
      do @(posedge vif.cb) while(!vif.cb.arready);  //wait for the slave to accept the address
      vif.cb.arvalid <= 1'b0;
    endtask : read_addr_channel

        
    task drive_the_dut(axi_transaction txn);
      fork 
        begin
          if(txn.txn_t == WRITE_TXN)  drive_write_txn(txn);
          else if(txn.txn_t == READ_TXN) drive_read_txn(txn);
        end
        poll_read_resp();
        poll_write_resp();
      join
    endtask : drive_the_dut
      
    virtual task run_phase(uvm_phase phase);
      forever begin
        //wait for reset
        #100;
        seq_item_port.get_next_item(req);
        drive_the_dut(req);
        seq_item_port.item_done();
      end
    endtask : run_phase
        
  endclass : axi_m_driver


  /////////////////////////// AGENT ////////////////////////////////////////////              
