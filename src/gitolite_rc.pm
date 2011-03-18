# stuff to help pull in the rc file, plus various constants

package gitolite_rc;
use Exporter 'import';

# the first set (before the blank line) are constants defined right here in
# this program.  The second set are from the 'rc'; We're clubbing all in
# because they're all "constants" in a programmatic sense
@EXPORT = qw(
    $ABRT $WARN
    $R_COMMANDS $W_COMMANDS
    $REPONAME_PATT $USERNAME_PATT $REPOPATT_PATT
    $ADC_CMD_ARGS_PATT
    $current_data_version

    $ADMIN_POST_UPDATE_CHAINS_TO $ENV $GITOLITE_BASE $GITOLITE_PATH $GIT_PATH
    $GL_ADC_PATH $GL_ADMINDIR $GL_ALL_INCLUDES_SPECIAL $GL_ALL_READ_ALL
    $GL_BIG_CONFIG $GL_CONF $GL_CONF_COMPILED $GL_GET_MEMBERSHIPS_PGM
    $GL_GITCONFIG_KEYS $GL_GITCONFIG_WILD $GL_KEYDIR $GL_LOGT $GL_NICE_VALUE
    $GL_NO_CREATE_REPOS $GL_NO_DAEMON_NO_GITWEB $GL_NO_SETUP_AUTHKEYS
    $GL_PACKAGE_CONF $GL_PACKAGE_HOOKS $GL_PERFLOGT $GL_SITE_INFO
    $GL_SLAVE_MODE $GL_WILDREPOS $GL_WILDREPOS_DEFPERMS
    $GL_WILDREPOS_PERM_CATS $HTPASSWD_FILE $PROJECTS_LIST $REPO_BASE
    $REPO_UMASK $RSYNC_BASE $SVNSERVE $UPDATE_CHAINS_TO

    $GL_HTTP_ANON_USER
);

# ------------------------------------------------------------------------------
#       real constants
# ------------------------------------------------------------------------------

$current_data_version = '1.7';

$ABRT = "\n\t\t***** ABORTING *****\n       ";
$WARN = "\n\t\t***** WARNING *****\n       ";

# commands we're expecting
$R_COMMANDS=qr/^(git[ -]upload-pack|git[ -]upload-archive)$/;
$W_COMMANDS=qr/^git[ -]receive-pack$/;

# note that REPONAME_PATT allows "/", while USERNAME_PATT does not
# also, the reason REPONAME_PATT is a superset of USERNAME_PATT is (duh!)
# because a repo can have "CREATOR" in the name
$REPONAME_PATT=qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@/+-]*$);
$USERNAME_PATT=qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@+-]*$);
# same as REPONAME, but used for wildcard repos, allows some common regex metas
$REPOPATT_PATT=qr(^\@?[0-9a-zA-Z[][\\^.$|()[\]*+?{}0-9a-zA-Z._\@/-]*$);

# ADC commands and arguments must match this pattern
$ADC_CMD_ARGS_PATT=qr(^[0-9a-zA-Z._\@/+:-]*$);

# ------------------------------------------------------------------------------
#       bring in the rc vars and allow querying them
# ------------------------------------------------------------------------------

# in case we're running under Apache using smart http
$ENV{HOME} = $ENV{GITOLITE_HTTP_HOME} if $ENV{GITOLITE_HTTP_HOME};

# we also need to "bring in" the rc variables.  The rc can only be in one of
# these two places; the first one we find, wins
for ("$ENV{HOME}/.gitolite.rc", "/etc/gitolite/gitolite.rc") {
    $ENV{GL_RC} ||= $_ if -f;
}
die "no rc file found\n" unless $ENV{GL_RC};
do $ENV{GL_RC} or die "error parsing $ENV{GL_RC}\n";

# fix up REPO_BASE
$REPO_BASE = "$ENV{HOME}/$REPO_BASE" unless $REPO_BASE =~ m(^/);

# ------------------------------------------------------------------------------
# per perl rules, this should be the last line in such a file:
1;
