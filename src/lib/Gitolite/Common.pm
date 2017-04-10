package Gitolite::Common;

# common (non-gitolite-specific) functions
# ----------------------------------------------------------------------

#<<<
@EXPORT = qw(
  print2  dbg     _mkdir  _open   ln_sf     tsh_rc      sort_u
  say     _warn   _chdir  _print            tsh_text    list_phy_repos
  say2    _die    _system slurp             tsh_lines
          trace           cleanup_conf_line tsh_try
          usage                             tsh_run
          gen_lfn
          gl_log

          dd
          t_start
          t_lap

          ssh_fingerprint_file
          ssh_fingerprint_line
);
#>>>
use Exporter 'import';
use File::Path qw(mkpath);
use File::Temp qw(tempfile);
use Carp qw(carp cluck croak confess);

use strict;
use warnings;

# ----------------------------------------------------------------------

sub print2 {
    local $/ = "\n";
    print STDERR @_;
}

sub say {
    local $/ = "\n";
    print @_, "\n";
}

sub say2 {
    local $/ = "\n";
    print STDERR @_, "\n";
}

sub trace {
    gl_log( "\t" . join( ",", @_[ 1 .. $#_ ] ) ) if $_[0] <= 1 and defined $Gitolite::Rc::rc{LOG_EXTRA};

    return unless defined( $ENV{D} );

    my $level = shift; return if $ENV{D} < $level;
    my $sub = ( caller 1 )[3] || ''; $sub =~ s/.*://;
    if ( not $sub ) {
        $sub = (caller)[1];
        $sub =~ s(.*/(.*))(($1));
    }
    $sub .= ' ' x ( 31 - length($sub) );
    say2 "$level\t$sub\t", join( "\t", @_ );
}

sub dbg {
    use Data::Dumper;
    return unless defined( $ENV{D} );
    for my $i (@_) {
        print STDERR "DBG: " . Dumper($i);
    }
}

sub dd {
    local $ENV{D} = 1;
    dbg(@_);
}

{
    my %start_times;

    eval "require Time::HiRes";
    # we just ignore any errors from this; nothing needs to be done as long as
    # no code *calls* either of the next two functions.

    sub t_start {
        my $name = shift || 'default';
        $start_times{$name} = [ Time::HiRes::gettimeofday() ];
    }

    sub t_lap {
        my $name = shift || 'default';
        return Time::HiRes::tv_interval( $start_times{$name} );
    }
}

sub _warn {
    gl_log( 'warn', @_ );
    if ( $ENV{D} and $ENV{D} >= 3 ) {
        cluck "WARNING: ", @_, "\n";
    } elsif ( defined( $ENV{D} ) ) {
        carp "WARNING: ", @_, "\n";
    } else {
        warn "WARNING: ", @_, "\n";
    }
}
$SIG{__WARN__} = \&_warn;

sub _die {
    gl_log( 'die', @_ );
    if ( $ENV{D} and $ENV{D} >= 3 ) {
        confess "FATAL: " . join( ",", @_ ) . "\n" if defined( $ENV{D} );
    } elsif ( defined( $ENV{D} ) ) {
        croak "FATAL: " . join( ",", @_ ) . "\n";
    } else {
        die "FATAL: " . join( ",", @_ ) . "\n";
    }
}
$SIG{__DIE__} = \&_die;

sub usage {
    my $script = (caller)[1];
    my $function = shift if @_ and $_[0] =~ /^[\w-]+$/;
    $function ||= ( ( ( caller(1) )[3] ) || ( ( caller(0) )[3] ) );
    $function =~ s/.*:://;
    my $code = slurp($script);
    $code =~ /^=for $function\b(.*?)^=cut/sm;
    say( $1 ? $1 : "...no usage message for '$function' in $script" );
    exit 1;
}

sub _mkdir {
    # It's not an error if the directory exists, but it is an error if it
    # doesn't exist and we can't create it. This includes not guaranteeing
    # dead symlinks or if mkpath traversal is blocked by a file.
    my $dir  = shift;
    my $perm = shift;    # optional
    return if -d $dir;
    mkpath($dir);
    chmod $perm, $dir if $perm;
    return 1;
}

sub _chdir {
    chdir( $_[0] || $ENV{HOME} ) or _die "chdir $_[0] failed: $!\n";
}

sub _system {
    # run system(), catch errors.  Be verbose only if $ENV{D} exists.  If not,
    # exit with <rc of system()> if it applies, else just "exit 1".
    trace( 1, 'system', @_ );
    if ( system(@_) != 0 ) {
        trace( 1, "system() failed", @_, "-> $?" );
        if ( $? == -1 ) {
            die "failed to execute: $!\n" if $ENV{D};
        } elsif ( $? & 127 ) {
            die "child died with signal " . ( $? & 127 ) . "\n" if $ENV{D};
        } else {
            die "child exited with value " . ( $? >> 8 ) . "\n" if $ENV{D};
            exit( $? >> 8 );
        }
        exit 1;
    }
}

sub _open {
    open( my $fh, $_[0], $_[1] ) or _die "open $_[1] failed: $!\n";
    return $fh;
}

sub _print {
    my ( $file, @text ) = @_;
    my $fh = _open( ">", "$file.$$" );
    print $fh @text;
    close($fh) or _die "close $file failed: $! at ", (caller)[1], " line ", (caller)[2], "\n";
    my $oldmode = ( ( stat $file )[2] );
    rename "$file.$$", $file;
    chmod $oldmode, $file if $oldmode;
}

sub slurp {
    return unless defined wantarray;
    local $/ = undef unless wantarray;
    my $fh = _open( "<", $_[0] );
    return <$fh>;
}

sub dos2unix {
    # WARNING: when calling this, make sure you supply a list context
    s/\r\n/\n/g for @_;
    return @_;
}

sub ln_sf {
    trace( 3, @_ );
    my ( $srcdir, $glob, $dstdir ) = @_;
    for my $hook ( glob("$srcdir/$glob") ) {
        $hook =~ s/$srcdir\///;
        unlink "$dstdir/$hook";
        symlink "$srcdir/$hook", "$dstdir/$hook" or croak "could not symlink $srcdir/$hook to $dstdir\n";
    }
}

sub sort_u {
    my %uniq;
    my $listref = shift;
    return [] unless @{$listref};
    undef @uniq{ @{$listref} };    # expect a listref
    my @sort_u = sort keys %uniq;
    return \@sort_u;
}

sub cleanup_conf_line {
    my $line = shift;
    return $line if $line =~ /^# \S+ \d+$/;

    # kill comments, but take care of "#" inside *simple* strings
    $line =~ s/^((".*?"|[^#"])*)#.*/$1/;
    # normalise whitespace; keeps later regexes very simple
    $line =~ s/=/ = /;
    $line =~ s/\s+/ /g;
    $line =~ s/^ //;
    $line =~ s/ $//;
    return $line;
}

{
    my @phy_repos = ();

    sub list_phy_repos {
        # use cached value only if it exists *and* no arg was received (i.e.,
        # receiving *any* arg invalidates cache)
        return \@phy_repos if ( @phy_repos and not @_ );

        my $cmd = 'find . ' . ($Gitolite::Rc::rc{REPO_SYMLINKS} || '') . ' -name "*.git" -prune';
        for my $repo (`$cmd`) {
            chomp($repo);
            $repo =~ s/\.git$//;
            $repo =~ s(^\./)();
            push @phy_repos, $repo unless $repo =~ m(/$);
                # tolerate bare repos within ~/repositories but silently ignore them
        }
        trace( 3, scalar(@phy_repos) . " physical repos found" );
        return sort_u( \@phy_repos );
    }
}

# generate a timestamp
sub gen_ts {
    my ( $s, $min, $h, $d, $m, $y ) = (localtime)[ 0 .. 5 ];
    $y += 1900; $m++;    # usual adjustments
    for ( $s, $min, $h, $d, $m ) {
        $_ = "0$_" if $_ < 10;
    }
    my $ts = "$y-$m-$d.$h:$min:$s";

    return $ts;
}

# generate a log file name
sub gen_lfn {
    my ( $s, $min, $h, $d, $m, $y ) = (localtime)[ 0 .. 5 ];
    $y += 1900; $m++;    # usual adjustments
    for ( $s, $min, $h, $d, $m ) {
        $_ = "0$_" if $_ < 10;
    }

    my ($template) = shift;
    # substitute template parameters and set the logfile name
    $template =~ s/%y/$y/g;
    $template =~ s/%m/$m/g;
    $template =~ s/%d/$d/g;

    return $template;
}

my $log_dest;
my $syslog_opened = 0;
END { closelog() if $syslog_opened; }
sub gl_log {
    # the log filename and the timestamp come from the environment.  If we get
    # called even before they are set, we have no choice but to dump to STDERR
    # (and probably call "logger").

    # tab sep if there's more than one field
    my $msg = join( "\t", @_ );
    $msg =~ s/[\n\r]+/<<newline>>/g;

    my $ts = gen_ts();
    my $tid = $ENV{GL_TID} ||= $$;

    $log_dest = $Gitolite::Rc::rc{LOG_DEST} || '' if not defined $log_dest;

    # log (update records only) to "gl-log" in the bare repo dir; this is to
    # make 'who-pushed' more efficient.  Since this is only for the update
    # records, it is not a replacement for the other two types of logging.
    if ($log_dest =~ /repo-log/ and $_[0] eq 'update') {
        # if the log line is 'update', we're already in the bare repo dir
        open my $lfh, ">>", "gl-log" or _die "open gl-log failed: $!";
        print $lfh "$ts\t$tid\t$msg\n";
        close $lfh;
    }

    # syslog
    if ($log_dest =~ /syslog/) {            # log_dest *includes* syslog
        if ($syslog_opened == 0) {
            require Sys::Syslog;
            Sys::Syslog->import(qw(:standard));

            openlog("gitolite" . ( $ENV{GL_TID} ? "[$ENV{GL_TID}]" : "" ), "pid", $Gitolite::Rc::rc{LOG_FACILITY} || 'local0');
            $syslog_opened = 1;
        }

        # gl_log is called either directly, or, if the rc variable LOG_EXTRA
        # is set, from trace(1, ...).  The latter use is considered additional
        # info for troubleshooting.  Trace prefixes a tab to the arguments
        # before calling gl_log, to visually set off such lines in the log
        # file.  Although syslog eats up that leading tab, we use it to decide
        # the priority/level of the syslog message.
        syslog( ( $msg =~ /^\t/ ? 'debug' : 'info' ), "%s", $msg);

        return if $log_dest !~ /normal/;
    }

    my $fh;
    logger_plus_stderr( "errors found before logging could be setup", "$msg" ) if not $ENV{GL_LOGFILE};
    open my $lfh, ">>", $ENV{GL_LOGFILE}
      or logger_plus_stderr( "errors found but logfile could not be created", "$ENV{GL_LOGFILE}: $!", "$msg" );
    print $lfh "$ts\t$tid\t$msg\n";
    close $lfh;
}

sub logger_plus_stderr {
    open my $fh, "|-", "logger" or confess "it's really not my day is it...?\n";
    for (@_) {
        print STDERR "FATAL: $_\n";
        print $fh "FATAL: $_\n";
    }
    exit 1;
}

# ----------------------------------------------------------------------
# Get the SSH fingerprint of a file
# If the fingerprint cannot be parsed, it will be undef
# In a scalar context, returns the fingerprint
# In a list context, returns (fingerprint, output) where output
# is the raw output of the ssh-keygen command
sub ssh_fingerprint_file {
    my $in = shift;
    -f $in or die "file not found: $in\n";
    my $fh;
    open( $fh, "ssh-keygen -l -f $in |" ) or die "could not fork: $!\n";
    my $output = <$fh>;
    chomp $output;
    # dbg("fp = $fp");
    close $fh;
    # Return a valid fingerprint or undef
    my $fp = undef;
    if($output =~ /((?:MD5:)?(?:[0-9a-f]{2}:){15}[0-9a-f]{2})/i or
       $output =~ m{((?:RIPEMD|SHA)\d+:[A-ZA-z0-9+/=]+)}i) {
        $fp = $1;
    }
    return wantarray ? ($fp, $output) : $fp;
}

# Get the SSH fingerprint of a line of text
# If the fingerprint cannot be parsed, it will be undef
# In a scalar context, returns the fingerprint
# In a list context, returns (fingerprint, output) where output
# is the raw output of the ssh-keygen command
sub ssh_fingerprint_line {
    my ( $fh, $fn ) = tempfile();
    print $fh shift() . "\n";
    close $fh;
    my ($fp,$output) = ssh_fingerprint_file($fn);
    unlink $fn;
    return wantarray ? ($fp,$output) : $fp;
}

# ----------------------------------------------------------------------

# bare-minimum subset of 'Tsh' (see github.com/sitaramc/tsh)
{
    my ( $rc, $text );
    sub tsh_rc   { return $rc   || 0; }
    sub tsh_text { return $text || ''; }
    sub tsh_lines { return split /\n/, $text; }

    sub tsh_try {
        my $cmd = shift; die "try: expects only one argument" if @_;
        $text = `( $cmd ) 2>&1; printf RC=\$?`;
        if ( $text =~ s/RC=(\d+)$// ) {
            $rc = $1;
            trace( 3, $text );
            return ( not $rc );
        }
        die "couldnt find RC= in result; this should not happen:\n$text\n\n...\n";
    }

    sub tsh_run {
        open( my $fh, "-|", @_ ) or die "popen failed: $!";
        local $/ = undef; $text = <$fh>;
        close $fh; warn "pclose failed: $!" if $!;
        $rc = ( $? >> 8 );
        trace( 3, $text );
        return $text;
    }
}

1;
