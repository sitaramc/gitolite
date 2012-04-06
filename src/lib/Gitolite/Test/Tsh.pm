#!/usr/bin/perl
use 5.10.0;

# Tsh -- non interactive Testing SHell in perl

# TODO items:
# - allow an RC file to be used to add basic and extended commands
# - convert internal defaults to additions to the RC file
# - implement shell commands as you go
# - solve the "pass/fail" inconsistency between shell and perl
# - solve the pipes problem (use 'overload'?)

# ----------------------------------------------------------------------
# modules

package Tsh;

use Exporter 'import';
@EXPORT = qw(
  try run cmp AUTOLOAD
  rc error_count text lines error_list put
  cd tsh_tempdir

  $HOME $PWD $USER
);
@EXPORT_OK = qw();

use Env qw(@PATH HOME PWD USER TSH_VERBOSE);
# other candidates:
# GL_ADMINDIR GL_BINDIR GL_RC GL_REPO_BASE_ABS GL_REPO GL_USER

use strict;
use warnings;

use Text::Tabs;    # only used for formatting the usage() message
use Text::ParseWords;

use File::Temp qw(tempdir);
END { chdir( $ENV{HOME} ); }
# we need this END handler *after* the 'use File::Temp' above.  Without
# this, if $PWD at exit was $tempdir, you get errors like "cannot remove
# path when cwd is [...] at /usr/share/perl5/File/Temp.pm line 902".

use Data::Dumper;

# ----------------------------------------------------------------------
# globals

my $rc;      # return code from backticked (external) programs
my $text;    # STDOUT+STDERR of backticked (external) programs
my $lec;     # the last external command (the rc and text are from this)
my $cmd;     # the current command

my $testnum;     # current test number, for info in TAP output
my $testname;    # current test name, for error info to user
my $line;        # current line number and text

my $err_count;   # count of test failures
my @errors_in;   # list of testnames that errored

my $tick;        # timestamp for git commits

my %autoloaded;
my $tempdir = '';

# ----------------------------------------------------------------------
# setup

# unbuffer STDOUT and STDERR
select(STDERR); $|++;
select(STDOUT); $|++;

# set the timestamp (needed only under harness)
test_tick() if $ENV{HARNESS_ACTIVE};

# ----------------------------------------------------------------------
# this is for one-liner access from outside, using @ARGV, as in:
#   perl -MTsh -e 'tsh()' 'tsh command list'
# or via STDIN
#   perl -MTsh -e 'tsh()' < file-containing-tsh-commands
# NOTE: it **exits**!

sub tsh {
    my @lines;

    if (@ARGV) {
        # simple, single argument which is a readable filename
        if ( @ARGV == 1 and $ARGV[0] !~ /\s/ and -r $ARGV[0] ) {
            # take the contents of the file
            @lines = <>;
        } else {
            # more than one argument *or* not readable filename
            # just take the arguments themselves as the command list
            @lines = @ARGV;
            @ARGV  = ();
        }
    } else {
        # no arguments given, take STDIN
        usage() if -t;
        @lines = <>;
    }

    # and process them
    try(@lines);

    # print error summary by default
    if ( not defined $TSH_VERBOSE ) {
        say STDERR "$err_count error(s)" if $err_count;
    }

    exit $err_count;
}

# these two get called with series of tsh commands, while the autoload,
# (later) handles single commands

sub try {
    $line = $rc = $err_count = 0;
    @errors_in = ();

    # break up multiline arguments into separate lines
    my @lines = map { split /\n/ } @_;

    # and process them
    rc_lines(@lines);

    # bump err_count if the last command had a non-0 rc (that was apparently not checked).
    $err_count++ if $rc;

    # finish up...
    dbg( 1, "$err_count error(s)" ) if $err_count;
    return ( not $err_count );
}

# run() differs from try() in that
#   -   uses open(), not backticks
#   -   takes only one command, not tsh-things like ok, /patt/ etc
#   -   -   if you pass it an array it uses the list form!

sub run {
    open( my $fh, "-|", @_ ) or die "tell sitaram $!";
    local $/ = undef; $text = <$fh>;
    close $fh; warn "tell sitaram $!" if $!;
    $rc = ( $? >> 8 );
    return $text;
}

sub put {
    my ( $file, $data ) = @_;
    die "probable quoting error in arguments to put: $file\n" if $file =~ /^\s*['"]/;
    my $mode = ">";
    $mode = "|-" if $file =~ s/^\s*\|\s*//;

    $rc = 0;
    my $fh;
    open( $fh, $mode, $file )
      and print $fh $data
      and close $fh
      and return 1;

    $rc = 1;
    dbg( 1, "put $file: $!" );
    return '';
}

# ----------------------------------------------------------------------
# TODO: AUTOLOAD and exportable convenience subs for common shell commands

sub cd {
    my $dir = shift || '';
    _cd($dir);
    dbg( 1, "cd $dir: $!" ) if $rc;
    return ( not $rc );
}

# this is classic AUTOLOAD, almost from the perlsub manpage.  Although, if
# instead of `ls('bin');` you want to be able to say `ls 'bin';` you will need
# to predeclare ls, with `sub ls;`.
sub AUTOLOAD {
    my $program = $Tsh::AUTOLOAD;
    dbg( 4, "program = $program, arg=$_[0]" );
    $program =~ s/.*:://;
    $autoloaded{$program}++;

    die "tsh's autoload support expects only one arg\n" if @_ > 1;
    _sh("$program $_[0]");
    return ( not $rc );    # perl truth
}

# ----------------------------------------------------------------------
# exportable service subs

sub rc {
    return $rc || 0;
}

sub text {
    return $text || '';
}

sub lines {
    return split /\n/, $text;
}

sub error_count {
    return $err_count;
}

sub error_list {
    return (
        wantarray
        ? @errors_in
        : join( "\n", @errors_in )
    );
}

sub tsh_tempdir {
    # create tempdir if not already done
    $tempdir = tempdir( "tsh_tempdir.XXXXXXXXXX", TMPDIR => 1, CLEANUP => 1 ) unless $tempdir;
    # XXX TODO that 'UNLINK' doesn't work for Ctrl_C

    return $tempdir;
}

# ----------------------------------------------------------------------
# internal (non-exportable) service subs

sub print_plan {
    return unless $ENV{HARNESS_ACTIVE};
    my $_ = shift;
    say "1..$_";
}

sub rc_lines {
    my @lines = @_;

    while (@lines) {
        my $_ = shift @lines;
        chomp; $_ = trim_ws($_);

        $line++;

        # this also sets $testname
        next if is_comment_or_empty($_);

        dbg( 2, "L: $_" );
        $line .= ": $_";    # save line for printing with 'FAIL:'

        # a DEF has to be on a line by itself
        if (/^DEF\s+([-.\w]+)\s*=\s*(\S.*)$/) {
            def( $1, $2 );
            next;
        }

        my @cmds = cmds($_);

        # process each command
        # (note: some of the commands may put stuff back into @lines)
        while (@cmds) {
            # this needs to be the 'global' one, since fail() prints it
            $cmd = shift @cmds;

            # is the current command a "testing" command?
            my $testing_cmd = ( $cmd =~ m(^ok(?:\s+or\s+(.*))?$) or $cmd =~ m(^!ok(?:\s+or\s+(.*))?$) or $cmd =~ m(^/(.*?)/(?:\s+or\s+(.*))?$) or $cmd =~ m(^!/(.*?)/(?:\s+or\s+(.*))?$) );

            # warn if the previous command failed but rc is not being checked
            if ( $rc and not $testing_cmd ) {
                dbg( 1, "rc: $rc from cmd prior to '$cmd'\n" );
                # count this as a failure, for exit status purposes
                $err_count++;
                # and reset the rc, otherwise for example 'ls foo; tt; tt; tt'
                # will tell you there are 3 errors!
                $rc = 0;
                push @errors_in, $testname if $testname;
            }

            # prepare to run the command
            dbg( 3, "C: $cmd" );
            if ( def($cmd) ) {
                # expand macro and replace head of @cmds (unshift)
                dbg( 2, "DEF: $cmd" );
                unshift @cmds, cmds( def($cmd) );
            } else {
                parse($cmd);
            }
            # reset rc if checking is done
            $rc = 0 if $testing_cmd;
            # assumes you will (a) never have *both* 'ok' and '!ok' after
            # an action command, and (b) one of them will come immediately
            # after the action command, with /patt/ only after it.
        }
    }
}

sub def {
    my ( $cmd, $list ) = @_;
    state %def;
    %def = read_rc_file() unless %def;

    if ($list) {
        # set mode
        die "attempt to redefine macro $cmd\n" if $def{$cmd};
        $def{$cmd} = $list;
        return;
    }

    # get mode: split the $cmd at spaces, see if there is a definition
    # available, substitute any %1, %2, etc., in it and send it back
    my ( $c, @d ) = shellwords($cmd);
    my $e;    # the expanded value
    if ( $e = $def{$c} ) {    # starting value
        for my $i ( 1 .. 9 ) {
            last unless $e =~ /%$i/;    # no more %N's (we assume sanity)
            die "$def{$c} requires more arguments\n" unless @d;
            my $f = shift @d;           # get the next datum
            $e =~ s/%$i/$f/g;           # and substitute %N all over
        }
        return join( " ", $e, @d );     # join up any remaining data
    }
    return '';
}

sub _cd {
    my $dir = shift || $HOME;
    # a directory name of 'tsh_tempdir' is special
    $dir = tsh_tempdir() if $dir eq 'tsh_tempdir';
    $rc = 0;
    chdir($dir) or $rc = 1;
}

sub _sh {
    my $cmd = shift;
    # TODO: switch to IPC::Open3 or something...?

    dbg( 4, "  running: ( $cmd ) 2>&1" );
    $text = `( $cmd ) 2>&1; echo -n RC=\$?`;
    $lec  = $cmd;
    dbg( 4, "  results:\n$text" );

    if ( $text =~ /RC=(\d+)$/ ) {
        $rc = $1;
        $text =~ s/RC=\d+$//;
    } else {
        die "couldnt find RC= in result; this should not happen:\n$text\n\n...\n";
    }
}

sub _perl {
    my $perl = shift;
    local $_;
    $_ = $text;

    dbg( 4, "  eval: $perl" );
    my $evrc = eval $perl;

    if ($@) {
        $rc = 1;    # shell truth
        dbg( 1, $@ );
        # leave $text unchanged
    } else {
        $rc = not $evrc;
        # $rc is always shell truth, so we need to cover the case where
        # there was no error but it still returned a perl false
        $text = $_;
    }
    dbg( 4, "  eval-rc=$evrc, results:\n$text" );
}

sub parse {
    my $cmd = shift;

    if ( $cmd =~ /^sh (.*)/ ) {

        _sh($1);

    } elsif ( $cmd =~ /^perl (.*)/ ) {

        _perl($1);

    } elsif ( $cmd eq 'tt' or $cmd eq 'test-tick' ) {

        test_tick();

    } elsif ( $cmd =~ /^plan ?(\d+)$/ ) {

        print_plan($1);

    } elsif ( $cmd =~ /^cd ?(\S*)$/ ) {

        _cd($1);

    } elsif ( $cmd =~ /^ENV (\w+)=['"]?(.+?)['"]?$/ ) {

        $ENV{$1} = $2;

    } elsif ( $cmd =~ /^(?:tc|test-commit)\s+(\S.*)$/ ) {

        # this is the only "git special" really; the default expansions are
        # just that -- defaults.  But this one is hardwired!
        dummy_commits($1);

    } elsif ( $cmd =~ '^put(?:\s+(\S.*))?$' ) {

        if ($1) {
            put( $1, $text );
        } else {
            print $text if defined $text;
        }

    } elsif ( $cmd =~ m(^ok(?:\s+or\s+(.*))?$) ) {

        $rc ? fail( "ok, rc=$rc from $lec", $1 || '' ) : ok();

    } elsif ( $cmd =~ m(^!ok(?:\s+or\s+(.*))?$) ) {

        $rc ? ok() : fail( "!ok, rc=0 from $lec", $1 || '' );

    } elsif ( $cmd =~ m(^/(.*?)/(?:\s+or\s+(.*))?$) ) {

        expect( $1, $2 );

    } elsif ( $cmd =~ m(^!/(.*?)/(?:\s+or\s+(.*))?$) ) {

        not_expect( $1, $2 );

    } else {

        _sh($cmd);

    }
}

# currently unused
sub executable {
    my $cmd = shift;
    # path supplied
    $cmd =~ m(/) and -x $cmd and return 1;
    # barename; look up in $PATH
    for my $p (@PATH) {
        -x "$p/$cmd" and return 1;
    }
    return 0;
}

sub ok {
    $testnum++;
    say "ok ($testnum)" if $ENV{HARNESS_ACTIVE};
}

sub fail {
    $testnum++;
    say "not ok ($testnum)" if $ENV{HARNESS_ACTIVE};

    my $die = 0;
    my ( $msg1, $msg2 ) = @_;
    if ($msg2) {
        # if arg2 is non-empty, print it regardless of debug level
        $die = 1 if $msg2 =~ s/^die //;
        say STDERR "# $msg2";
    }

    local $TSH_VERBOSE = 1 if $ENV{TSH_ERREXIT};
    dbg( 1, "FAIL: $msg1", $testname || '', "test number $testnum", "L: $line", "results:\n$text" );

    # count the error and add the testname to the list if it is set
    $err_count++;
    push @errors_in, $testname if $testname;

    return unless $die or $ENV{TSH_ERREXIT};
    dbg( 1, "exiting at cmd $cmd\n" );

    exit( $rc || 74 );
}

sub cmp {
    # compare input string with text()
    my $text = text();
    my $in   = shift;

    if ( $text eq $in ) {
        ok();
    } else {
        fail( 'cmp failed', '' );
        dbg( 4, "\n\ntext = <<<$text>>>, in = <<<$in>>>\n\n" );
    }
}

sub expect {
    my ( $patt, $msg ) = @_;
    $msg =~ s/^\s+// if $msg;
    my $sm;
    if ( $sm = sm($patt) ) {
        dbg( 4, "  M: $sm" );
        ok();
    } else {
        fail( "/$patt/", $msg || '' );
    }
}

sub not_expect {
    my ( $patt, $msg ) = @_;
    $msg =~ s/^\s+// if $msg;
    my $sm;
    if ( $sm = sm($patt) ) {
        dbg( 4, "  M: $sm" );
        fail( "!/$patt/", $msg || '' );
    } else {
        ok();
    }
}

sub sm {
    # smart match?  for now we just do regex match
    my $patt = shift;

    return ( $text =~ qr($patt) ? $& : "" );
}

sub trim_ws {
    my $_ = shift;
    s/^\s+//; s/\s+$//;
    return $_;
}

sub is_comment_or_empty {
    my $_ = shift;
    chomp; $_ = trim_ws($_);
    if (/^##\s(.*)/) {
        $testname = $1;
        say "# $1";
    }
    return ( /^#/ or /^$/ );
}

sub cmds {
    my $_ = shift;
    chomp; $_ = trim_ws($_);

    # split on unescaped ';'s, then unescape the ';' in the results
    my @cmds = map { s/\\;/;/g; $_ } split /(?<!\\);/;
    @cmds = grep { $_ = trim_ws($_); /\S/; } @cmds;
    return @cmds;
}

sub dbg {
    return unless $TSH_VERBOSE;
    my $level = shift;
    return unless $TSH_VERBOSE >= $level;
    my $all = join( "\n", grep( /./, @_ ) );
    chomp($all);
    $all =~ s/\n/\n\t/g;
    say STDERR "# $all";
}

sub ddump {
    for my $i (@_) {
        print STDERR "DBG: " . Dumper($i);
    }
}

sub usage {
    # TODO
    print "Please see documentation at:

        https://github.com/sitaramc/tsh/blob/master/README.mkd

Meanwhile, here are your local 'macro' definitions:

";
    my %m = read_rc_file();
    my @m = map { "$_\t$m{$_}\n" } sort keys %m;
    $tabstop = 16;
    print join( "", expand(@m) );
    exit 1;
}

# ----------------------------------------------------------------------
# git-specific internal service subs

sub dummy_commits {
    for my $f ( split ' ', shift ) {
        if ( $f eq 'tt' or $f eq 'test-tick' ) {
            test_tick();
            next;
        }
        my $ts = ( $tick ? localtime($tick) : localtime() );
        _sh("echo $f at $ts >> $f && git add $f && git commit -m '$f at $ts'");
    }
}

sub test_tick {
    unless ( $ENV{HARNESS_ACTIVE} ) {
        sleep 1;
        return;
    }
    $tick += 60 if $tick;
    $tick ||= 1310000000;
    $ENV{GIT_COMMITTER_DATE} = "$tick +0530";
    $ENV{GIT_AUTHOR_DATE}    = "$tick +0530";
}

# ----------------------------------------------------------------------
# the internal macros, for easy reference and reading

sub read_rc_file {
    my $rcfile = "$HOME/.tshrc";
    my $rctext;
    if ( -r $rcfile ) {
        local $/ = undef;
        open( my $rcfh, "<", $rcfile ) or die "this should not happen: $!\n";
        $rctext = <$rcfh>;
    } else {
        # this is the default "rc" content
        $rctext = "
            add         =   git add
            branch      =   git branch
            clone       =   git clone
            checkout    =   git checkout
            commit      =   git commit
            fetch       =   git fetch
            init        =   git init
            push        =   git push
            reset       =   git reset
            tag         =   git tag

            empty       =   git commit --allow-empty -m empty
            push-om     =   git push origin master
            reset-h     =   git reset --hard
            reset-hu    =   git reset --hard \@{u}
        "
    }

    # ignore everything except lines of the form "aa = bb cc dd"
    my %commands = ( $rctext =~ /^\s*([-.\w]+)\s*=\s*(\S.*)$/gm );
    return %commands;
}

1;
