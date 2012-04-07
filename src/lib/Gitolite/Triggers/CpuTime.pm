package Gitolite::Triggers::CpuTime;

use Time::HiRes;

use Gitolite::Rc;
use Gitolite::Common;

use strict;
use warnings;

# cpu and elapsed times for gitolite+git operations
# ----------------------------------------------------------------------

# Ideally, you will (a) write your own code with a different filename so later
# gitolite upgrades won't overwrite your copy, (b) add appropriate variables
# to the rc file, and (c) change your rc file to call your program instead.

# ----------------------------------------------------------------------
my $start_time;

# this trigger is not yet documented; it gets called at the start and does not
# receive any arguments.
sub input {
    _warn "something wrong with the invocation of CpuTime::input" if $ENV{GL_TID} ne $$;
    $start_time = [ Time::HiRes::gettimeofday() ];
}

sub post_git {
    _warn "something wrong with the invocation of CpuTime::post_git" if $ENV{GL_TID} ne $$;

    my ( $trigger, $repo, $user, $aa, $ref, $verb ) = @_;
    my ( $utime, $stime, $cutime, $cstime ) = times();
    my $elapsed = Time::HiRes::tv_interval($start_time);

    gl_log( 'times', $utime, $stime, $cutime, $cstime, $elapsed );

    # now do whatever you want with the data; the following is just an example.

    if ( my $limit = $rc{CPU_TIME_WARN_LIMIT} ) {
        my $total = $utime + $cutime + $stime + $cstime;
        # some code to send an email or whatever...
        say2 "limit = $limit, actual = $total" if $total > $limit;
    }

    if ( $rc{DISPLAY_CPU_TIME} ) {
        say2 "perf stats for $verb on repo '$repo':";
        say2 "  user CPU time: " . ( $utime + $cutime );
        say2 "  sys  CPU time: " . ( $stime + $cstime );
        say2 "   elapsed time: " . $elapsed;
    }
}

1;
