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
