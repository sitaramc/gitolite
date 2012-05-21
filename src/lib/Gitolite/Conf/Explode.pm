package Gitolite::Conf::Explode;

# include/subconf processor
# ----------------------------------------------------------------------

@EXPORT = qw(
  explode
);

use Exporter 'import';

use Gitolite::Rc;
use Gitolite::Common;

use strict;
use warnings;

# ----------------------------------------------------------------------

# 'seen' for include/subconf files
my %included = ();
# 'seen' for group names on LHS
my %prefixed_groupname = ();

sub explode {
    trace( 3, @_ );
    my ( $file, $subconf, $out ) = @_;

    # seed the 'seen' list if it's empty
    $included{ device_inode("conf/gitolite.conf") }++ unless %included;

    my $fh = _open( "<", $file );
    while (<$fh>) {
        my $line = cleanup_conf_line($_);
        next unless $line =~ /\S/;

        # subst %HOSTNAME word if rc defines a hostname, else leave as is
        $line =~ s/%HOSTNAME\b/$rc{HOSTNAME}/g if $rc{HOSTNAME};

        $line = prefix_groupnames( $line, $subconf ) if $subconf ne 'master';

        if ( $line =~ /^(include|subconf) (?:(\S+) )?(\S.+)$/ ) {
            incsub( $1, $2, $3, $subconf, $out );
        } else {
            # normal line, send it to the callback function
            push @{$out}, $line;
        }
    }
}

sub incsub {
    my $is_subconf = ( +shift eq 'subconf' );
    my ( $new_subconf, $include_glob, $current_subconf, $out ) = @_;

    _die "subconf '$current_subconf' attempting to run 'subconf'\n" if $is_subconf and $current_subconf ne 'master';

    _die "invalid include/subconf file/glob '$include_glob'"
      unless $include_glob =~ /^"(.+)"$/
          or $include_glob =~ /^'(.+)'$/;
    $include_glob = $1;

    trace( 2, $is_subconf, $include_glob );

    for my $file ( glob($include_glob) ) {
        _warn("included file not found: '$file'"), next unless -f $file;
        _die "invalid include/subconf filename '$file'" unless $file =~ m(([^/]+).conf$);
        my $basename = $1;

        next if already_included($file);

        if ($is_subconf) {
            push @{$out}, "subconf " . ( $new_subconf || $basename );
            explode( $file, ( $new_subconf || $basename ), $out );
            push @{$out}, "subconf $current_subconf";
        } else {
            explode( $file, $current_subconf, $out );
        }
    }
}

sub prefix_groupnames {
    my ( $line, $subconf ) = @_;

    my $lhs = '';
    # save 'foo' if it's an '@foo = list' line
    $lhs = $1 if $line =~ /^@(\S+) = /;
    # prefix all @groups in the line
    $line =~ s/(^| )(@\S+)(?= |$)/ $1 . ($prefixed_groupname{$subconf}{$2} || $2) /ge;
    # now prefix the LHS and store it if needed
    if ($lhs) {
        $line =~ s/^@\S+ = /"\@$subconf.$lhs = "/e;
        $prefixed_groupname{$subconf}{"\@$lhs"} = "\@$subconf.$lhs";
        trace( 3, "prefixed_groupname.$subconf.\@$lhs = \@$subconf.$lhs" );
    }

    return $line;
}

sub already_included {
    my $file = shift;

    my $file_id = device_inode($file);
    return 0 unless $included{$file_id}++;

    _warn("$file already included");
    trace( 2, "$file already included" );
    return 1;
}

sub device_inode {
    my $file = shift;
    trace( 3, $file, ( stat $file )[ 0, 1 ] );
    return join( "/", ( stat $file )[ 0, 1 ] );
}

1;

