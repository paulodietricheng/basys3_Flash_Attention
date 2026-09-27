# Source in the Vivado Tcl console, or use vivado -mode batch -source this_file.
set package_root [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $package_root vivado_project]
if {[llength [get_projects -quiet]] != 0} {error "Close the current project before creating this project."}
if {[file exists [file join $project_dir fa_basys3.xpr]]} {
    error "Project already exists. Open $project_dir/fa_basys3.xpr instead."
}
create_project fa_basys3 $project_dir -part xc7a35tcpg236-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set fd [open [file join $package_root rtl files.f] r]
set source_list [split [read $fd] "\n"]
close $fd
foreach relative $source_list {
    set relative [string trim $relative]
    if {$relative ne ""} {add_files -norecurse [file join $package_root $relative]}
}
add_files -fileset constrs_1 -norecurse [file join $package_root constraints basys3.xdc]
add_files -fileset sim_1 -norecurse [file join $package_root tests tb_uart.sv]
add_files -fileset sim_1 -norecurse [file join $package_root tests tb_compute.sv]
set_property top basys3_top [get_filesets sources_1]
set_property top tb_uart [get_filesets sim_1]
set_property top_auto_set 0 [get_filesets sim_1]
set fixture_root [file join $package_root fixtures dummy_fixed]
set_property -name xsim.simulate.xsim.more_options -value "-testplusarg ROOT=$fixture_root -testplusarg CASE=0" -objects [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Project ready: hardware top basys3_top; simulation top tb_uart."
puts "Run Behavioral Simulation to test PC-style UART loading and output readback."
