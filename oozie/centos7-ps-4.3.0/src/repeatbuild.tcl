# allow build failed caused by network problem to continue.

for {set index 0} { $index < 100 } { incr index } {
    catch {exec /home/oozie-4.3.0/bin/mkdistro.sh "-Dtomcat.version=2.7.3" "-Dhive.version=2.1.1" "-Dhbase.version=1.2.4" "-Dtomcat.version=8.0.39"} o msg
    puts $msg
}