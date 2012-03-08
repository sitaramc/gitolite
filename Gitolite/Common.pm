package Gitolite::Common;

# common (non-gitolite-specific) functions
# ----------------------------------------------------------------------

#<<<
@EXPORT = qw(
  print2  dbg     _mkdir  _open   ln_sf     tsh_rc      sort_u
  say     _warn   _chdir  _print            tsh_text
  say2    _die            slurp             tsh_lines
          trace                             tsh_try
          usage                             tsh_run
);
#>>>
use Exporter 'import';
use File::Path qw(mkpath);
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
    return unless defined( $ENV{D} );

    my $level = shift;
    my $args  = ''; $args = join( ", ", @_ ) if @_;
    my $sub   = ( caller 1 )[3] || ''; $sub =~ s/.*://; $sub .= ' ' x ( 32 - length($sub) );
    say2 "TRACE $level $sub", $args if $ENV{D} >= $level;
}

sub dbg {
    use Data::Dumper;
    return unless defined( $ENV{D} );
    for my $i (@_) {
        print STDERR "DBG: " . Dumper($i);
    }
}

sub _warn {
    if ( $ENV{D} and $ENV{D} >= 3 ) {
        cluck "WARNING: ", @_, "\n";
    } elsif ( defined( $ENV{D} ) ) {
        carp "WARNING: ", @_, "\n";
    } else {
        warn "WARNING: ", @_, "\n";
    }
}

sub _die {
    if ( $ENV{D} and $ENV{D} >= 3 ) {
        confess "FATAL: " . join( ",", @_ ) . "\n" if defined( $ENV{D} );
    } elsif ( defined( $ENV{D} ) ) {
        croak "FATAL: " . join( ",", @_ ) . "\n";
    } else {
        die "FATAL: " . join( ",", @_ ) . "\n";
    }
}

sub usage {
    _warn(shift) if @_;
    my $scriptname = ( caller() )[1];
    my $script     = slurp($scriptname);
    $script =~ /^=for usage(.*?)^=cut/sm;
    say2( $1 ? $1 : "...no usage message in $scriptname" );
    exit 1;
}

sub _mkdir {
    # it's not an error if the directory exists, but it is an error if it
    # doesn't exist and we can't create it
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
    local $/ = undef;
    my $fh = _open( "<", $_[0] );
    return <$fh>;
}

sub dos2unix {
    # WARNING: when calling this, make sure you supply a list context
    s/\r\n/\n/g for @_;
    return @_;
}

sub ln_sf {
    trace( 4, @_ );
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
    return [] unless @{ $listref };
    undef @uniq{ @{ $listref } }; # expect a listref
    my @sort_u = sort keys %uniq;
    return \@sort_u;
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
        $text = `( $cmd ) 2>&1; echo -n RC=\$?`;
        if ( $text =~ s/RC=(\d+)$// ) {
            $rc = $1;
            trace( 4, $text );
            return ( not $rc );
        }
        die "couldnt find RC= in result; this should not happen:\n$text\n\n...\n";
    }

    sub tsh_run {
        open( my $fh, "-|", @_ ) or die "popen failed: $!";
        local $/ = undef; $text = <$fh>;
        close $fh; warn "pclose failed: $!" if $!;
        $rc = ( $? >> 8 );
        trace( 4, $text );
        return $text;
    }
}

1;
