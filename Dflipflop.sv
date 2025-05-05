module dff (dff_if vif);// in
  
  always@(posedge vif.clk) begin
    if(vif.rst)
      vif.dout<=1'b0;
    else
      vif.dout<=vif.din;
  end
endmodule

interface dff_if;// declaring interface without specifying directions(modport)
  logic clk;//using 4 state logic
  logic rst;
  logic din;
  logic dout;
endinterface




class transaction;
  rand bit din;
  bit dout;
  
  function transaction copy();// performing deep copy randomize single object and copy
    copy=new();
    copy.din=this.din;
    copy.dout=this.dout;
  endfunction
  
  function void display(input string tag);// print according to class hence tag
    $display("[%0s] : DIN =%0b | DOUT=%0b ",tag,din,dout);
  endfunction
  
endclass


class generator;
  
  mailbox #(transaction) gdmbx;//gen->drv
  mailbox #(transaction) mbxref;//drv->sco
  
  transaction t;
  
  int count;//no of times to generate values;
  
  event sconxt;//to generate next values
  event done;// to finish simulation
  
  function new(mailbox #(transaction) gdmbx,mailbox #(transaction) mbxref);// connect mailboxes and also create a single transaction object
    this.gdmbx=gdmbx;
    this.mbxref=mbxref;
    t=new();
  endfunction
  
  task run();//randomize trans and wait for an event by scoreboard
    repeat(count)
      begin
        assert(t.randomize()) else $display("[GEN] RANDOMIZATION FAILED");
        gdmbx.put(t.copy());
        mbxref.put(t.copy());
        t.display("GEN");
        @(sconxt);
      end
    ->done;
  endtask
  
endclass



class driver;
  virtual dff_if vif;//connect to an interface which is static entity
  
  transaction t;
  
  mailbox #(transaction)gdmbx;
  
  function new(mailbox #(transaction)gdmbx);
    this.gdmbx=gdmbx;
  endfunction
  
  
  task reset();
    vif.rst<='b1;
    repeat(5) @(posedge vif.clk);
    vif.rst<=1'b0;
    @(posedge vif.clk);
    $display("[DRV] RESET DONE");
  endtask
  
  task run();// drive the gen value at wait till it to latch then drive zero to clear the latch
    forever begin
      gdmbx.get(t);
      vif.din<=t.din;
      @(posedge vif.clk);
      t.display("DRV");
      vif.din<=1'b0;
      @(posedge vif.clk);
    end
  endtask
endclass


class monitor;
  virtual dff_if vif;
  
  transaction t;
  
  mailbox #(transaction)smmbx;
  
  function new(mailbox #(transaction)smmbx);
    this.smmbx=smmbx;
  endfunction
  
  task run();
    t=new();
    forever begin
      repeat(2) @(posedge vif.clk);// wait for 2 clk cycles to observe the latched o/p as latch happens at 1st clk cycle 
      t.din=vif.din;
      t.dout=vif.dout;
      smmbx.put(t);
      t.display("MON");
    end
  endtask
  
endclass

class scoreboard;
  
  transaction t,tr;// compare with driven object din
  
  event sconxt;
  
  mailbox #(transaction)smmbx;
  mailbox #(transaction)mbxref;
  
  
  function new(mailbox #(transaction)smmbx,mailbox #(transaction)mbxref);
    this.smmbx=smmbx;
    this.mbxref=mbxref;
  endfunction
  
  task run();
    forever begin
      smmbx.get(t);
      mbxref.get(tr);
      t.display("SCO");
      tr.display("REF");
      if(t.dout==tr.din)
        $display("[SCO] : DATA MATCHED");
      else
        $display("[SCO] : DATA MISMATCHED");
      $display("-------------------------");
      ->sconxt;// signal for nxt value
    end
  endtask
  
endclass


class environment;// hold all dynamic entities
  generator g;
  driver d;
  virtual dff_if vif;
  monitor m;
  scoreboard s;
  event sconxt;
  
  mailbox #(transaction)gdmbx;
  mailbox #(transaction)smmbx;
  mailbox #(transaction)mbxref;


  function new(virtual dff_if vif);
    this.vif=vif;
    gdmbx=new();
    smmbx=new();
    mbxref=new();
    g=new(gdmbx,mbxref);
    d=new(gdmbx);
    d.vif=this.vif;
    m=new(smmbx);
    m.vif=this.vif;
    s=new(smmbx,mbxref);
    g.sconxt=sconxt;
    s.sconxt=sconxt;
  endfunction
  
  task pre_test();
    d.reset();
  endtask;
  
  task test();
    fork
      g.run();
      d.run();
      m.run();
      s.run();
    join_any
  endtask
  
  task post_test();
    wait(g.done.triggered);
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
  
endclass


module top;// create all static entities and pass it to dynamic entities
  dff_if vif();
  
  environment e;

  dff dut(vif);
  
  initial begin
    vif.clk<=0;
  end
  
  always #10 vif.clk=~vif.clk;
  
  
  
  initial begin
    e=new(vif);
    e.g.count=30;
    e.run();
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
endmodule

  
  
    
  
  
  
