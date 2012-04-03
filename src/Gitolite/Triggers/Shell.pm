package Gitolite::Triggers::Shell;

# usage notes: this module must be loaded first in the INPUT trigger list.  Or
# at least before Mirroring::input anyway.

use Gitolite::Rc;
use Gitolite::Common;

# fedora likes to do things that are a little off the beaten track, compared
# to typical gitolite usage:
# - every user has their own login
# - the forced command may not get the username as an argument.  If it does
#   not, the gitolite user name is $USER (the unix user name)
# - and finally, if the first argument to the forced command is '-s', and
#   $SSH_ORIGINAL_COMMAND is empty or runs a non-git/gitolite command, then
#   the user gets a shell

sub input {
    my $shell_allowed = 0;
    if ( @ARGV and $ARGV[0] eq '-s' ) {
        shift @ARGV;
        $shell_allowed++;
    }

    @ARGV = ( $ENV{USER} ) unless @ARGV;

    return unless $shell_allowed;

    # now determine if this was intended as a shell command or git/gitolite
    # command

    my $soc = $ENV{SSH_ORIGINAL_COMMAND};

    # no command, just 'ssh alice@host'; doesn't return ('exec's out)
    shell_out() if $shell_allowed and not $soc;

    return if git_gitolite_command($soc);

    gl_log( 'shell', $ENV{SHELL}, "-c", $soc );
    exec $ENV{SHELL}, "-c", $soc;
}

sub shell_out {
    my $shell = $ENV{SHELL};
    $shell =~ s/.*\//-/;    # change "/bin/bash" to "-bash"
    gl_log( 'shell', $shell );
    exec { $ENV{SHELL} } $shell;
}

# some duplication with gitolite-shell, factor it out later, if it works fine
# for fedora and they like it.
sub git_gitolite_command {
    my $soc = shift;

    my $git_commands = "git-upload-pack|git-receive-pack|git-upload-archive";
    return 1 if $soc =~ /^($git_commands) /;

    my @words = split ' ', $soc;
    return 1 if $rc{COMMANDS}{ $words[0] };

    return 0;
}

1;
