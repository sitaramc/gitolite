# this file is commonly used using "require".  It is not required to use "use"
# (because it doesn't live in a different package)

# warning: preceding para requires 4th attribute of a programmer after
# laziness, impatience, and hubris: sense of humour :-)

# WARNING
# -------
# the name of this file will change as soon as its function/feature set
# stabilises enough ;-)

# right now all it does is define a function that tells you where to find the
# rc file

# ----------------------------------------------------------------------------
#       where is the rc file hiding?
# ----------------------------------------------------------------------------

sub where_is_rc
{
    # till now, the rc file was in one fixed place: .gitolite.rc in $HOME of
    # the user hosting the gitolite repos.  This was fine, because gitolite is
    # all about empowering non-root users :-)

    # then we wanted to make a debian package out of it (thank you, Rhonda!)
    # which means (a) it's going to be installed by root anyway and (b) any
    # config files have to be in /etc/<something>

    # the only way to resolve this in a backward compat way is to look for the
    # $HOME one, and if you don't find it look for the /etc one

    # this common routine does that, setting an env var for the first one it
    # finds

    return if $ENV{GL_RC};

    for my $glrc ( $ENV{HOME} . "/.gitolite.rc", "/etc/gitolite/gitolite.rc" ) {
        if (-f $glrc) {
            $ENV{GL_RC} = $glrc;
            return;
        }
    }
}

1;
