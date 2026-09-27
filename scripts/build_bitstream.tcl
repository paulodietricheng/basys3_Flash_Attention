# Run only after creating/opening the project. Build failures are not ignored.
if {[llength [get_projects -quiet]] == 0} {error "Open fa_basys3.xpr first."}
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed; inspect the run log."}
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed; inspect resources and run log."}
open_run impl_1
set report_dir [file join [get_property DIRECTORY [current_project]] reports]
file mkdir $report_dir
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing.rpt]
report_drc -file [file join $report_dir drc.rpt]
foreach type {setup hold} {
    set paths [get_timing_paths -$type -max_paths 1]
    if {[llength $paths] && [get_property SLACK [lindex $paths 0]] < 0} {
        error "Negative $type slack. See reports/timing.rpt before programming the board."
    }
}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set bit_file [file join [get_property DIRECTORY [get_runs impl_1]] basys3_top.bit]
if {![file exists $bit_file]} {error "Bitstream generation failed; inspect implementation log."}
puts "Bitstream ready: $bit_file"
puts "Program it through Vivado Hardware Manager, then use host/fa_client.py."
