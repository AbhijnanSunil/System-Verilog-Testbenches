module fifo(dout,empty,full,clk,rst,din,wr,rd);
  output reg [7:0]dout;
  output empty,full;
  input clk,rst;
  input [7:0]din;
  input wr,rd;
  reg [7:0]mem[0:15];
  reg [4:0]cnt;
  reg [3:0]wradd,rdadd;

  
  always@(posedge clk)
    begin
      if(rst)
        begin
          dout<=0;
          wradd<=0;
          rdadd<=0;
          cnt<=0;
        end
      else if((rd&&!empty)&&(wr&&!full))
        begin
          dout<=mem[rdadd];
          mem[wradd]<=din;
          wradd<=wradd+1;
          rdadd<=rdadd+1;
          cnt<=cnt;
        end
       else if(rd&&!empty)
        begin
          dout<=mem[rdadd];
          rdadd<=rdadd+1;
          cnt<=cnt-1;
        end
       else if(wr&&!full)
        begin
          mem[wradd]<=din;
          wradd<=wradd+1;
          cnt<=cnt+1;
        end
    end
  
  assign empty=cnt==0;
  assign full=cnt==16;
  
endmodule

interface fifo_if;
  logic[7:0]dout,din;
  logic empty,full;
  logic rd,wr;
  logic rst,clk;
endinterface


//Testbench

class transaction;
  rand  bit rd,wr;
  bit empty,full;
  rand bit [7:0]din;
  bit [7:0]dout;
  bit emptyin,fullin;
  
  constraint rd_wr_e {
    rd dist {0:=50,1:=50};
    wr dist {0:=50,1:=50};
    }
  
  function transaction copy();
    copy = new();
    copy.rd = this.rd;
    copy.wr = this.wr;
    copy.din = this.din;
    copy.dout = this.dout;
    copy.empty = this.empty;
    copy.full = this.full;
    copy.emptyin=this.emptyin;
    copy.fullin=this.fullin;
  endfunction

  function void display(input string tag);
    $display("[%s]: DIN=%d | RD=%d | WR=%d | EMPTY=%d | FULL=%d | DOUT=%d",tag,din,rd,wr,empty,full,dout);
  endfunction
  
endclass


class generator;
  
  mailbox #(transaction) mbx;
  transaction t;
  int count;
  event done,sconxt;
  
  function new(mailbox #(transaction) mbx);
    this.mbx=mbx;
    t=new();
  endfunction
  
  task run();
    for(int i=0;i<count;i++)
      begin
        assert(t.randomize()) else $display("[GEN] :RANDOMIZATION FAILED");
        mbx.put(t.copy());
        t.display("GEN");
        @(sconxt);
      end
    ->done;
  endtask
  
endclass


class driver;

  mailbox #(transaction) mbx;
  transaction t;
  virtual fifo_if vif;
  event sconxt;
  
  function new(mailbox #(transaction) mbx);
    this.mbx=mbx;
  endfunction
  
  task reset();
    vif.rst<=1;
    vif.rd<=0;
    vif.wr<=0;
    vif.din<=0;
    repeat(5) @(posedge vif.clk);
    vif.rst<=0;
    @(posedge vif.clk);
    $display("[DRV] RESET DONE");
  endtask
  
  task run();
    forever begin
      mbx.get(t);
      vif.din<=t.din;
      vif.rd<=t.rd;
      vif.wr<=t.wr;
      @(posedge vif.clk);
      t.display("DRV");
      vif.din<=0;
      vif.rd<=0;
      vif.wr<=0;
      @(posedge vif.clk);
    end
  endtask
  
  task cycle();
    for(int i=0;i<17;i++) begin
      vif.din<=$urandom_range(0,255);
      vif.rd<=0;
      vif.wr<=1;
      @(posedge vif.clk);
      $display("[DRV] : DIN=%d RD=%d WR=%d",vif.din,vif.rd,vif.wr);
      vif.din<=0;
      vif.rd<=0;
      vif.wr<=0;
      @(posedge vif.clk);
      @(sconxt);
    end
    
    for(int i=0;i<17;i++) begin
      vif.din<=0;
      vif.rd<=1;
      vif.wr<=0;
      @(posedge vif.clk);
      $display("[DRV] : DIN=%d RD=%d WR=%d",vif.din,vif.rd,vif.wr);
      vif.din<=0;
      vif.rd<=0;
      vif.wr<=0;
      @(sconxt);
    end
  endtask;
endclass


class monitor;
  virtual fifo_if vif;
  mailbox #(transaction) mbx;
  transaction t;
  
  
  function new(mailbox #(transaction) mbx);
    this.mbx=mbx;
    t=new();
  endfunction
  
  task run();
    forever begin
      @(posedge vif.clk);
      t.rd=vif.rd;
      t.wr=vif.wr;
      t.din=vif.din;
      t.fullin=vif.full;
      t.emptyin=vif.empty;
      @(posedge vif.clk);
      t.dout=vif.dout;
      t.empty=vif.empty;
      t.full=vif.full;
      mbx.put(t.copy());
      t.display("MON");
    end
  endtask
endclass

class scoreboard;
  mailbox #(transaction)mbx;
  
  transaction t;
  
  event sconxt;
  
  bit [7:0] arr[$];
  bit [7:0] temp;
  
  function new(mailbox #(transaction) mbx);
  	this.mbx=mbx;
  endfunction
  
  task run();
     forever begin
      mbx.get(t);
      t.display("SCO");
      if(t.wr&&t.rd) begin
        if(!t.emptyin&&!t.fullin) begin //valid read and write
          temp=arr.pop_front();
          arr.push_back(t.din);
          
          if(t.dout==temp)
            $display("[SCO] RD+WR MATCHED %d ",t.dout);
          else
            $error("[SCO] RD+WR MISMATCH : EXPECTED %d : GOT %d",temp,t.dout);
        end
        else if(t.emptyin && !t.fullin) begin
          arr.push_back(t.din);
          $display("[SCO] READ IGNORED DUE TO EMPTY : WROTE");
        end
        else if(!t.emptyin && t.fullin) begin
          temp=arr.pop_front();
          if(temp==t.dout)
            $display("[SCO] WRITE IGNORED DUE TO FULL : READ MATCHED %d",t.dout);
          else
            $error("[SCO] WRITE IGNORED DUE TO FULL : READ MISMATCHED : EXPECTED %d : GOT %d",temp,t.dout);
        end
        else
          $error("[SCO] RD+WR IGNORED DUE TO FULL AND EMPTY FLAGS BEING HIGH AT SAME TIME ???");
      end
       
      
      
      
      
      else if(t.wr) begin  //only wr 
        if(!t.fullin) begin
            arr.push_back(t.din);
          	$display("[SCO] WROTE");
        end
        else
          $display("[SCO] WRITE IGNORED DUE TO FULL");
      end
    
      
      else if(t.rd) begin
        
        if(!t.emptyin) begin
          temp=arr.pop_front();
          if(temp==t.dout)
            $display("[SCO] DATA MATCHED %d",temp);
          else
            $error("[SCO] DATA MISMATCHED : EXPECTED %d :GOT %d",temp,t.dout);
        end
        else begin
          $display("[SCO] READ IGNORED DUE TO EMPTY");
        end
        
      end
    
      else begin
        $display("[SCO] IDLE CYCLE FIFO UNTOUCHED");
      end
    
    
    
      if ((arr.size() == 0 && !t.empty) || (arr.size() != 0 && t.empty))
      	$error("[SCO] : EMPTY flag mismatch. Model size = %0d, DUT empty = %0b", arr.size(), t.empty);
  	  if ((arr.size() == 16 && !t.full) || (arr.size() != 16 && t.full))
    	$error("[SCO] : FULL flag mismatch. Model size = %0d, DUT full = %0b", arr.size(), t.full);
    
    ->sconxt;
    end
  endtask
endclass

class environment;
  mailbox #(transaction) mbx1,mbx2;
  generator g;
  driver d;
  monitor m;
  scoreboard s;
  virtual fifo_if vif;
  
  function new(virtual fifo_if vif);
    this.vif=vif;
    mbx1=new();
    mbx2=new();
    g=new(mbx1);
    d=new(mbx1);
    d.vif=vif;
    m=new(mbx2);
    s=new(mbx2);
    m.vif=vif;
    g.sconxt=s.sconxt;
    d.sconxt=s.sconxt;
  endfunction
  
  
  task pre_test();
    d.reset();
    fork
      d.cycle();
      s.run();
      m.run();
    join_any
    disable fork;
      d.reset();
  endtask
  
  task test();
    fork 
      g.run();
      d.run();
      s.run();
      m.run();
    join_any
  endtask
  
  task post_test();
    wait(g.done.triggered);
    $display("[ENV] TEST VECTORS EXECUTION DONE");
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
    
endclass


module top();
  fifo_if vif();
  
  environment env;
  
  initial vif.clk=0;
  
  always #5 vif.clk=~vif.clk;
  
  fifo dut(.dout(vif.dout),.empty(vif.empty),.full(vif.full),.clk(vif.clk),.rst(vif.rst),.din(vif.din),.wr(vif.wr),.rd(vif.rd));
  
  initial begin
    env=new(vif);
    env.g.count=50;
    env.run();
  end
  
endmodule

