onerror {resume}
   puts "==========================================================
Initialize simulation
==========================================================
type isim_restart to restart simulation"
   set FIRSTRUN 1
   
   proc add_divider {TEXT} {
    divider add "$TEXT"
   }
   
   #Add wave flags, label and signal name
   proc add_wave_label { FLAGS LABEL NAME } {
      set cmd "wave add $FLAGS"
      if { $LABEL != "" } {
         append cmd " -name \"$LABEL\""
      }
      append cmd " $NAME"
      if {[catch {eval $cmd } stderr] != 0} {
         puts "  WARNING : Signal $NAME doesn't exist"
      }
   }
   
   #Add wave flags and signal name
   proc add_wave {FLAGS NAME} {
    add_wave_label "$FLAGS" "" "$NAME"
   }
         	
   proc isim_restart {} {
      global FIRSTRUN
      #set TESTBENCH_SCRIPT "C:/FitkitSVN/apps/inp/inp2016-proj2/build/fpga/../../fpga/sim/isim.tcl"
      if {$FIRSTRUN == 0} { wcfg new }
      set FIRSTRUN 0
      #puts "../../fpga/sim/isim.tcl" 
      #puts [pwd]
      if {[catch {source "../../fpga/sim/isim.tcl"}]} { 
         puts "isim source failed"
         flush stdout
      } else {
         puts "isim found, tb entity: testbench"
         flush stdout
         if {[catch {isim_script} stderr] != 0} {
            puts "ERROR: $stderr"
         }
      } 
   }
   
   isim_restart	
   
