package Gitolite::Conf;

# explode/parse a conf file
# ----------------------------------------------------------------------

@EXPORT = qw(
  compile
  explode
  parse
);

use Exporter 'import';
use Getopt::Long;

use lib $ENV{GL_BINDIR};
use Gitolite::Common;
use Gitolite::Rc;
use Gitolite::Conf::Sugar;
use Gitolite::Conf::Store;

use strict;
use warnings;

# ----------------------------------------------------------------------

# 'seen' for include/subconf files
my %included = ();
# 'seen' for group names on LHS
my %prefixed_groupname = ();

# ----------------------------------------------------------------------

sub compile {
    trace(3);
    # XXX assume we're in admin-base/conf

    _chdir( $rc{GL_ADMIN_BASE} );
    _chdir("conf");

    explode( 'gitolite.conf', 'master', \&parse );

    # the order matters; new repos should be created first, to give store a
    # place to put the individual gl-conf files
    new_repos();
    store();
}

sub explode {
    trace( 4, @_ );
    my ( $file, $subconf, $parser ) = @_;

    # $parser is a ref to a callback; if not supplied we just print
    $parser ||= sub { print shift, "\n"; };

    # seed the 'seen' list if it's empty
    $included{ device_inode("conf/gitolite.conf") }++ unless %included;

    my $fh    = _open( "<", $file );
    my @fh    = <$fh>;
    my @lines = macro_expand( "# BEGIN $file\n", @fh, "# END $file\n" );
    my $line;
    while (@lines) {
        $line = shift @lines;

        $line = cleanup_conf_line($line);
        next unless $line =~ /\S/;

        $line = prefix_groupnames( $line, $subconf ) if $subconf ne 'master';

        if ( $line =~ /^(include|subconf) "(.+)"$/ or $line =~ /^(include|subconf) '(.+)'$/ ) {
            incsub( $1, $2, $subconf, $parser );
        } else {
            # normal line, send it to the callback function
            $parser->($line);
        }
    }
}

sub parse {
    trace( 4, @_ );
    my $line = shift;

    # user or repo groups
    if ( $line =~ /^(@\S+) = (.*)/ ) {
        add_to_group( $1, split( ' ', $2 ) );
    } elsif ( $line =~ /^repo (.*)/ ) {
        set_repolist( split( ' ', $1 ) );
    } elsif ( $line =~ /^(-|C|R|RW\+?(?:C?D?|D?C?)M?) (.* )?= (.+)/ ) {
        my $perm  = $1;
        my @refs  = parse_refs( $2 || '' );
        my @users = parse_users($3);

        # XXX what do we do? s/\bCREAT[EO]R\b/~\$creator/g for @users;

        for my $ref (@refs) {
            for my $user (@users) {
                add_rule( $perm, $ref, $user );
            }
        }
    } elsif ( $line =~ /^config (.+) = ?(.*)/ ) {
        my ( $key, $value ) = ( $1, $2 );
        my @validkeys = split( ' ', ( $rc{GL_GITCONFIG_KEYS} || '' ) );
        push @validkeys, "gitolite-options\\..*";
        my @matched = grep { $key =~ /^$_$/ } @validkeys;
        # XXX move this also to add_config: _die "git config $key not allowed\ncheck GL_GITCONFIG_KEYS in the rc file for how to allow it" if (@matched < 1);
        # XXX both $key and $value must satisfy a liberal but secure pattern
        add_config( 1, $key, $value );
    } elsif ( $line =~ /^subconf (\S+)$/ ) {
        set_subconf($1);
    } else {
        _warn "?? $line";
    }
}

# ----------------------------------------------------------------------

sub incsub {
    my $is_subconf = ( +shift eq 'subconf' );
    my ( $include_glob, $subconf, $parser ) = @_;

    _die "subconf $subconf attempting to run 'subconf'\n" if $is_subconf and $subconf ne 'master';

    # XXX move this to Macros... substitute HOSTNAME word if GL_HOSTNAME defined, otherwise leave as is
    # $include_glob =~ s/\bHOSTNAME\b/$GL_HOSTNAME/ if $GL_HOSTNAME;

    # XXX g2 diff: include glob is *implicitly* from $rc{GL_ADMIN_BASE}/conf, not *explicitly*
    # for my $file (glob($include_glob =~ m(^/) ? $include_glob : "$rc{GL_ADMIN_BASE}/conf/$include_glob")) {

    trace( 3, $is_subconf, $include_glob );

    for my $file ( glob($include_glob) ) {
        _warn("included file not found: '$file'"), next unless -f $file;
        _die "invalid include/subconf filename $file" unless $file =~ m(([^/]+).conf$);
        my $basename = $1;

        next if already_included($file);

        if ($is_subconf) {
            $parser->("subconf $basename");
            explode( $file, $basename, $parser );
            $parser->("subconf $subconf");
            # XXX g2 delegaton compat: deal with this: $subconf_seen++;
        } else {
            explode( $file, $subconf, $parser );
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
        trace( 3, "prefixed_groupname.$subconf.\@$lhs = \@$subconf.$lhs" );
    }

    return $line;
}

sub already_included {
    my $file = shift;

    my $file_id = device_inode($file);
    return 0 unless $included{$file_id}++;

    _warn("$file already included");
    trace( 3, "$file already included" );
    return 1;
}

sub device_inode {
    my $file = shift;
    trace( 3, $file, ( stat $file )[ 0, 1 ] );
    return join( "/", ( stat $file )[ 0, 1 ] );
}

1;
