# Shared behavioral-simulation contract. A normal return from run is insufficient:
# XSim also returns after $finish, a fatal assertion, or a fixed-time limit.
proc auris_run_simulation {completion_path duration} {
    set project [current_project]
    set log_path [file join [get_property DIRECTORY $project] \
        "[get_property NAME $project].sim" sim_1 behav xsim simulate.log]
    set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
    # Numerical regressions do not need a waveform database of every IP signal.
    set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
    launch_simulation
    run {*}$duration
    set done [get_value -radix unsigned $completion_path]
    close_sim -force
    if {![file exists $log_path]} { error "Missing simulator transcript: $log_path" }
    set channel [open $log_path r]
    set transcript [read $channel]
    close $channel
    if {[regexp -nocase {(^|\n)[ \t]*(fatal|error):} $transcript]} {
        error "Simulator reported an error: $log_path"
    }
    if {$done ne "1"} { error "Simulation did not reach successful completion" }
}
