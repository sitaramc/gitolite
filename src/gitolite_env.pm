# stuff that detects or sets up the runtime environment

package gitolite_env;
use Exporter 'import';
@EXPORT = qw(
    setup_environment
    simulate_ssh_connection
    get_logfilename
);

use strict;
use warnings;

# ----------------------------------------------------------------------------
#       find the rc file, then pull the libraries
# ----------------------------------------------------------------------------

BEGIN {
    die "ENV GL_RC not set\n" unless $ENV{GL_RC};
    die "ENV GL_BINDIR not set\n" unless $ENV{GL_BINDIR};
}

use lib $ENV{GL_BINDIR};
use gitolite_rc;
use gitolite;

# ----------------------------------------------------------------------------
#       start
# ----------------------------------------------------------------------------

# firstly, the following function, 'setup_environment', is not only about env
# vars; it does other stuff too (like umask, nice...)

# a lot of stuff gets carried around in env vars primarily for 2 reasons.  One
# is that git calls the hooks, so they're not in the same 'process' as the
# 'gl-auth-command' that probably started things off.

# Granted; we could write the same 'discovery' within the hook code, but
# that's needless code duplication, plus in some cases a good amount of
# inefficiency.

# Even more important, we do *not* want to burden the ADCs (admin defined
# commands) with all this discovery, because those are written by the users
# themselves (my 'user' == some gitolite 'admin' somewhere; I don't mean
# 'gitolite user')

# think of it OS-supported memo-ization :-)
sub setup_environment {
    $ENV{GL_ADMINDIR} = $GL_ADMINDIR;
    $ENV{GL_LOG} = get_logfilename($GL_LOGT);
    $ENV{PATH} = "$GIT_PATH:$ENV{PATH}" if $GIT_PATH;
    # set default permission of wildcard repositories
    $ENV{GL_WILDREPOS_DEFPERMS} = $GL_WILDREPOS_DEFPERMS if $GL_WILDREPOS_DEFPERMS;
    # this is used in so many places, inside and outside gitolite by external
    # hooks and ADCs, it isn't even funny...
    $ENV{GL_REPO_BASE_ABS} = ( $REPO_BASE =~ m(^/) ? $REPO_BASE : "$ENV{HOME}/$REPO_BASE" );

    # be nice if asked.  If you want me to pull in BSD::Resource to get rid of
    # the first '0', feel free to send me a patch that does everything needed
    # from within my own installer, does not require internet access (don't
    # ask!), and doesn't require a C compiler or the perl-devel (or eqvt
    # named) packages.  Heck in some cases it's not even Linux...
    setpriority(0, 0, $GL_NICE_VALUE) if $GL_NICE_VALUE and $GL_NICE_VALUE > 0;

    umask($REPO_UMASK);

    set_up_http_death() if $ENV{GITOLITE_HTTP_HOME};
}

sub simulate_ssh_connection {
    # these patterns indicate normal git usage; see "services[]" in
    # http-backend.c for how I got that.  Also note that "info" is overloaded;
    # git uses "info/refs...", while gitolite uses "info" or "info?...".  So
    # there's a "/" after info in the list below
    if ($ENV{PATH_INFO} =~ m(^/(.*)/(HEAD$|info/refs$|objects/|git-(?:upload|receive)-pack$))) {
        my $repo = $1;
        my $verb = ($ENV{REQUEST_URI} =~ /git-receive-pack/) ?  'git-receive-pack' : 'git-upload-pack';
        $ENV{SSH_ORIGINAL_COMMAND} = "$verb '$repo'";
    } else {
        # this is one of our custom commands; could be anything really,
        # because of the adc feature
        my ($verb) = ($ENV{PATH_INFO} =~ m(^/(\S+)));
        my $args = $ENV{QUERY_STRING};
        $args =~ s/\+/ /g;
        $ENV{SSH_ORIGINAL_COMMAND} = $verb;
        $ENV{SSH_ORIGINAL_COMMAND} .= " $args" if $args;
        print_http_headers();  # in preparation for the eventual output!
    }
    $ENV{SSH_CONNECTION} = "$ENV{REMOTE_ADDR} $ENV{REMOTE_PORT} $ENV{SERVER_ADDR} $ENV{SERVER_PORT}";
}

# a plain "die" was fine for ssh but http has all that extra gunk it needs.
# So we need to, in effect, create a "death handler".
sub set_up_http_death
{
    $SIG{__DIE__} = sub {
        my $service = ($ENV{SSH_ORIGINAL_COMMAND} =~ /git-receive-pack/ ?  'git-receive-pack' : 'git-upload-pack');
        my $message = shift; chomp($message);
        print STDERR "$message\n";

        # format the service response, then the message.  With initial
        # help from Ilari and then a more detailed email from Shawn...
        $service = "# service=$service\n"; $message = "ERR $message\n";
        $service = sprintf("%04X", length($service)+4) . "$service";        # no CRLF on this one
        $message = sprintf("%04X", length($message)+4) . "$message";

        print_http_headers();
        print $service;
        print "0000";       # flush-pkt, apparently
        print $message;
        print STDERR $service;
        print STDERR $message;
        exit 0;     # if it's ok for die_webcgi in git.git/http-backend.c, it's ok for me ;-)
    }
}

# ----------------------------------------------------------------------------
#       helpers
# ----------------------------------------------------------------------------

my $http_headers_printed = 0;
sub print_http_headers {
    my($code, $text) = @_;

    return if $http_headers_printed++;
    $code ||= 200;
    $text ||= "OK - gitolite";

    $|++;
    print "Status: $code $text\r\n";
    print "Expires: Fri, 01 Jan 1980 00:00:00 GMT\r\n";
    print "Pragma: no-cache\r\n";
    print "Cache-Control: no-cache, max-age=0, must-revalidate\r\n";
    print "\r\n";
}

sub get_logfilename {
    # this sub has a wee little side-effect; it sets $ENV{GL_TS}
    my($template) = shift;

    my ($s, $min, $h, $d, $m, $y) = (localtime)[0..5];
    $y += 1900; $m++;               # usual adjustments
    for ($s, $min, $h, $d, $m) {
        $_ = "0$_" if $_ < 10;
    }
    $ENV{GL_TS} = "$y-$m-$d.$h:$min:$s";

    # substitute template parameters and set the logfile name
    $template =~ s/%y/$y/g;
    $template =~ s/%m/$m/g;
    $template =~ s/%d/$d/g;
    return ($template);
}

# ------------------------------------------------------------------------------
# per perl rules, this should be the last line in such a file:
1;
