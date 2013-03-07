#!/usr/bin/perl

# Call like this:
# TSH_VERBOSE=1 TSH_ERREXIT=1 HARNESS_ACTIVE=1 GITOLITE_TEST=y prove t/ukm.t

use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Common;
use Gitolite::Test;

# basic tests using ssh
# ----------------------------------------------------------------------

my $bd = `gitolite query-rc -n GL_BINDIR`;
my $h  = $ENV{HOME};
my $ab = `gitolite query-rc -n GL_ADMIN_BASE`;
my $pd = "$bd/../t/keys"; # source for pubkeys
umask 0077;

_mkdir( "$h/.ssh", 0700 ) if not -d "$h/.ssh";

try "plan 204";


# Reset everything.
# Only admin and u1, u2, and u3 keys are available initially
# Keys u4, u5, and u6 are used as guests later.
# For easy access, we put the keys into ~/.ssh/, though.
try "
    rm -f $h/.ssh/authorized_keys; ok or die 1
    cp $pd/u[1-6]* $h/.ssh; ok or die 2
    cp $pd/admin*  $h/.ssh; ok or die 3
    cp $pd/config  $h/.ssh; ok or die 4
        cat $h/.ssh/config
        perl s/%USER/$ENV{USER}/
        put $h/.ssh/config
    mkdir             $ab/keydir; ok or die 5
    cp $pd/u[1-3].pub $ab/keydir; ok or die 6
    cp $pd/admin.pub  $ab/keydir; ok or die 7
";

# Put the keys into ~/.ssh/authorized_keys
system("gitolite ../triggers/post-compile/ssh-authkeys");

# enable user key management in a simple form.
# Guest key managers can add keyids looking like email addresses, but
# cannot add emails containing example.com or hemmecke.org.
system("sed -i \"s/.*ENABLE =>.*/'UKM_CONFIG'=>{'FORBIDDEN_GUEST_PATTERN'=>'example.com|hemmecke.org'}, ENABLE => ['ukm',/\" $h/.gitolite.rc");

# super-key-managers can add/del any key
# super-key-managers should in fact agree with people having write
# access to gitolite-admin repo.
# guest-key-managers can add/del guest keys
confreset; confadd '
    @guest-key-managers = u2 u3
    @creators = u2 u3
    repo pub/CREATOR/..*
        C   =   @creators
        RW+ =   CREATOR
        RW  =   WRITERS
        R   =   READERS
';

# Populate the gitolite-admin/keydir in the same way as it was used for
# the initialization of .ssh/authorized_keys above.
try "
    mkdir             keydir; ok or die 8
    cp $pd/u[1-3].pub keydir; ok or die 9;
    cp $pd/admin.pub  keydir; ok or die 10;
    git add conf keydir; ok
    git commit -m ukm; ok; /master.* ukm/
";

# Activate new config data.
try "PUSH admin; ok; gsh; /master -> master/; !/FATAL/" or die text();

# Check whether the above setup yields the expected behavior for ukm.
# The admin is super-key-manager, thus can manage every key.
try "
    ssh admin ukm; ok; /Hello admin, you manage the following keys:/
                       / admin +admin/
                       / u1 +u1/
                       / u2 +u2/
                       / u3 +u3/
";

# u1 isn't a key manager, so shouldn't be above to manage keys.
try "ssh u1 ukm; !ok; /FATAL: You are not a key manager./";

# u2 and u3 are guest key managers, but don't yet manage any key.
try "ssh u2 ukm; ok"; cmp "Hello u2, you manage the following keys:\n\n\n";
try "ssh u3 ukm; ok"; cmp "Hello u3, you manage the following keys:\n\n\n";


###################################################################
# Unknows subkommands abort ukm.
try "ssh u2 ukm fake; !ok; /FATAL: unknown ukm subcommand: fake/";


###################################################################
# Addition of keys.

# If no data is provided on stdin, we don't block, but rather timeout
# after one second and abort the program.
try "ssh u2 ukm add u4\@example.org; !ok; /FATAL: missing public key data/";

# If no keyid is given, we cannot add a key.
try "ssh u2 ukm add; !ok; /FATAL: keyid required/";

try "
    DEF ADD = cat $pd/%1.pub|ssh %2 ukm add %3
    DEF ADDOK = ADD %1 %2 %3; ok
    DEF ADDNOK = ADD %1 %2 %3; !ok
    DEF FP = ADDNOK u4 u2 %1
    DEF FORBIDDEN_PATTERN = FP %1; /FATAL: keyid not allowed:/
";

# Neither a guest key manager nor a super key manager can add keys that have
# double dot in their keyid. This is hardcoded to forbid paths with .. in it.
try "
    ADDNOK u4 u2    u4\@hemmecke..org; /Not allowed to use '..' in keyid./
    ADDNOK u4 admin u4\@hemmecke..org; /Not allowed to use '..' in keyid./
    ADDNOK u4 admin ./../.myshrc;      /Not allowed to use '..' in keyid./
";

# guest-key-managers can only add keys that look like emails.
try "
    FORBIDDEN_PATTERN u4
    FORBIDDEN_PATTERN u4\@example
    FORBIDDEN_PATTERN u4\@foo\@example.org

    # No support for 'old style' multiple keys.
    FORBIDDEN_PATTERN u4\@example.org\@foo

    # No path delimiter in keyid
    FORBIDDEN_PATTERN foo/u4\@example.org

    # Certain specific domains listed in FORBIDDEN_GUEST_PATTERN are forbidden.
    # Note that also u4\@example-com would be rejected, because MYDOMAIN
    # contains a regular expression --> I don't care.
    FORBIDDEN_PATTERN u4\@example.com
    FORBIDDEN_PATTERN u4\@hemmecke.org
";

# Accept one guest key.
try "ADDOK u4 u2 u4\@example.org";
try "ssh u2 ukm; ok; /Hello u2, you manage the following keys:/
                     / u4\@example.org *u4\@example.org/";

# Various ways how a key must be rejected.
try "
    # Cannot add the same key again.
    ADDNOK u4 u2 u4\@example.org; /FATAL: cannot override existing key/

    # u2 can also not add u4.pub under another keyid
    ADDNOK u4 u2 u4\@example.net; /FATAL: cannot add key/
         /Same key is already available under another userid./

    # u2 can also not add another key under the same keyid.
    ADDNOK u5 u2 u4\@example.org; /FATAL: cannot override existing key/

    # Also u3 cannot not add another key under the same keyid.
    ADDNOK u5 u3 u4\@example.org
         /FATAL: cannot add another public key for an existing user/

    # And u3 cannot not add u4.pub under another keyid.
    ADDNOK u4 u3 u4\@example.net; /FATAL: cannot add key/
         /Same key is already available under another userid./

    # Not even the admin can add the same key u4 under a different userid.
    ADDNOK u4 admin u4\@example.net; /FATAL: cannot add key/
         /Same key is already available under another userid./
         /Found  .* u4\@example.org/

    # Super key managers cannot add keys that start with @.
    # We don't care about @ in the dirname, though.
    ADDNOK u4 admin foo/\@ex.net; /FATAL: cannot add key that starts with \@/
    ADDNOK u4 admin foo/\@ex;     /FATAL: cannot add key that starts with \@/
    ADDNOK u4 admin     \@ex.net; /FATAL: cannot add key that starts with \@/
    ADDNOK u4 admin     \@ex;     /FATAL: cannot add key that starts with \@/
";

# But u3 can add u4.pub under the same keyid.
try "ADDOK u4 u3 u4\@example.org";

try "ssh u3 ukm; ok; /Hello u3, you manage the following keys:/
                     / u4\@example.org *u4\@example.org/";

# The admin can add multiple keys for the same userid.
try "
    ADDOK u5 admin u4\@example.org
    ADDOK u5 admin u4\@example.org\@home
    ADDOK u5 admin laptop/u4\@example.org
    ADDOK u5 admin laptop/u4\@example.org\@home
";

# And admin can also do this for other guest key managers. Note,
# however, that the gitolite-admin must be told where the
# GUEST_DIRECTORY is. But he/she could find out by cloning the
# gitolite-admin repository and adding the same key directly.
try "
    ADDOK u5 admin zzz/guests/u2/u4\@example.org\@foo
    ADDOK u6 admin zzz/guests/u3/u6\@example.org
";

try "ssh admin ukm; ok"; cmp "Hello admin, you manage the following keys:
fingerprint                                     userid         keyid
a4:d1:11:1d:25:5c:55:9b:5f:91:37:0e:44:a5:a5:f2 admin          admin
00:2c:1f:dd:a3:76:5a:1e:c4:3c:01:15:65:19:a5:2e u1             u1
69:6f:b5:8a:f5:7b:d8:40:ce:94:09:a2:b8:95:79:5b u2             u2
26:4b:20:24:98:a4:e4:a5:b9:97:76:9a:15:92:27:2d u3             u3
78:cf:7e:2b:bf:18:58:54:23:cc:4b:3d:7e:f4:63:79 u4\@example.org laptop/u4\@example.org
78:cf:7e:2b:bf:18:58:54:23:cc:4b:3d:7e:f4:63:79 u4\@example.org laptop/u4\@example.org\@home
78:cf:7e:2b:bf:18:58:54:23:cc:4b:3d:7e:f4:63:79 u4\@example.org u4\@example.org
78:cf:7e:2b:bf:18:58:54:23:cc:4b:3d:7e:f4:63:79 u4\@example.org u4\@example.org\@home
8c:a6:c0:a5:71:85:0b:89:d3:08:97:22:ae:95:e1:bb u4\@example.org zzz/guests/u2/u4\@example.org
78:cf:7e:2b:bf:18:58:54:23:cc:4b:3d:7e:f4:63:79 u4\@example.org zzz/guests/u2/u4\@example.org\@foo
8c:a6:c0:a5:71:85:0b:89:d3:08:97:22:ae:95:e1:bb u4\@example.org zzz/guests/u3/u4\@example.org
fc:0f:eb:52:7a:d2:35:da:89:96:f5:15:0e:85:46:e7 u6\@example.org zzz/guests/u3/u6\@example.org
\n\n";

# Now, u2 has two keys in his directory, but u2 can manage only one of
# them, since the one added by the admin has two @ in it. Thus the key
# added by admin is invisible to u2.
try "ssh u2 ukm; ok"; cmp "Hello u2, you manage the following keys:
fingerprint                                     userid         keyid
8c:a6:c0:a5:71:85:0b:89:d3:08:97:22:ae:95:e1:bb u4\@example.org u4\@example.org
\n\n";

# Since admin added key u6@example.org to the directory of u2, u2 is
# also able to see it and, in fact, to manage it.
try "ssh u3 ukm; ok"; cmp "Hello u3, you manage the following keys:
fingerprint                                     userid         keyid
8c:a6:c0:a5:71:85:0b:89:d3:08:97:22:ae:95:e1:bb u4\@example.org u4\@example.org
fc:0f:eb:52:7a:d2:35:da:89:96:f5:15:0e:85:46:e7 u6\@example.org u6\@example.org
\n\n";

###################################################################
# Deletion of keys.
try "
    DEF DEL = ssh %1 ukm del %2
    DEF DELOK  = DEL %1 %2; ok
    DEF DELNOK = DEL %1 %2; !ok
    DEF DELNOMGR = DELNOK %1 %2; /FATAL: You are not managing the key /
";

# Deletion requires a keyid.
try "ssh u3 ukm del; !ok; /FATAL: keyid required/";

# u3 can, of course, not remove any unmanaged key.
try "DELNOMGR u3 u2";

# But u3 can delete u4@example.org and u6@example.org. This will, of course,
# not remove the key u4@example.org that u2 manages.
try "
    DELOK u3 u4\@example.org
    DELOK u3 u6\@example.org
";

# After having deleted u4@example.org, u3 cannot remove it again,
# even though, u2 still manages that key.
try "DELNOMGR u3 u4\@example.org";

# Of course a super-key-manager can remove any (existing) key.
try "
    DELOK  admin zzz/guests/u2/u4\@example.org
    DELNOK admin zzz/guests/u2/u4\@example.org
        /FATAL: You are not managing the key zzz/guests/u2/u4\@example.org./
    DELNOK admin zzz/guests/u2/u4\@example.org\@x
        /FATAL: You are not managing the key zzz/guests/u2/u4\@example.org./
    DELOK  admin zzz/guests/u2/u4\@example.org\@foo
";

# As the admin could do that via pushing to the gitolite-admin manually,
# it's also allowed to delete even non-guest keys.
try "DELOK admin u3";

# Let's clean the environment again.
try "
    DELOK admin laptop/u4\@example.org\@home
    DELOK admin laptop/u4\@example.org
    DELOK admin        u4\@example.org\@home
    DELOK admin        u4\@example.org
    ADDOK u3 admin u3
 ";

# Currently the admin has just one key. It cannot be removed.
# But after adding another key, deletion should work fine.
try "
    DELNOK admin admin; /FATAL: You cannot delete your last key./
    ADDOK u6 admin second/admin; /Adding new public key for admin./
    DELOK admin admin
    DELNOK u6 admin; /FATAL: You are not managing the key admin./
    DELNOK u6 second/admin; /FATAL: You cannot delete your last key./
    ADDOK admin u6 admin; /Adding new public key for admin./
    DELOK u6 second/admin
";

###################################################################
# Selfkey management.

# If self key management is not switched on in the .gitolite.rc file,
# it's not allowed at all.
try "ssh u2 ukm add \@second; !ok; /FATAL: selfkey management is not enabled/";

# Let's enable it.
system("sed -i \"/'UKM_CONFIG'=>/s/=>{/=>{'SELFKEY_MANAGEMENT'=>1,/\" $h/.gitolite.rc");

# And add self-key-managers to gitolite.conf
# chdir("../gitolite-admin") or die "in `pwd`, could not cd ../g-a";
try "glt pull admin origin master; ok";
put "|cut -c5- > conf/gitolite.conf", '
    repo gitolite-admin
        RW+ = admin
    repo testing
        RW+ = @all
    @guest-key-managers = u2 u3
    @self-key-managers = u1 u2
    @creators = u2 u3
    repo pub/CREATOR/..*
        C   =   @creators
        RW+ =   CREATOR
        RW  =   WRITERS
        R   =   READERS
';
try "
    git add conf keydir; ok
    git commit -m selfkey; ok; /master.* selfkey/
";
try "PUSH admin; ok; gsh; /master -> master/; !/FATAL/" or die text();

# Now we can start with the tests.

# Only self key managers are allowed to use selfkey management.
# See variable @self-key-managers.
try "ssh u3 ukm add \@second; !ok; /FATAL: You are not a selfkey manager./";

# Cannot add keyid that are not alphanumeric.
try "ssh u1 ukm add \@second-key; !ok; /FATAL: keyid not allowed:/";

# Add a second key for u1, but leave it pending by not feeding in the
# session key. The new user can login, but he/she lives under a quite
# random gl_user name and thus is pretty much excluded from everything
# except permissions given to @all. If this new id calls ukm without
# providing the session key, this (pending) key is automatically
# removed from the system.
# If a certain keyid is in the system, then it cannot be added again.
try "
    ADDOK u4 u1 \@second
    ssh admin ukm; ok; /u1     zzz/self/u1/zzz-add-[a-z0-9]{32}-second-u1/
    ssh u1    ukm; ok; /u1     \@second .pending add./
    ADDNOK u4 u1 \@second; /FATAL: keyid already in use: \@second/
    ssh u4    ukm; ok; /pending keyid deleted: \@second/
    ssh admin ukm; ok; !/zzz/; !/second/
";

# Not providing a proper ssh public key will abort. Providing a good
# ssh public key, which is not a session key makes the key invalid.
# The key will, therefore, be deleted by this operation.
try "
    ADDOK u4 u1 \@second
    echo fake|ssh u4 ukm; !ok; /FATAL: does not seem to be a valid pubkey/
    cat $pd/u5.pub | ssh u4 ukm; ok;
        /session key not accepted/
        /pending keyid deleted: \@second/
";

# True addition of a new selfkey is done via piping it to a second ssh
# call that uses the new key to call ukm. Note that the first ssh must
# have completed its job before the second ssh is able to successfully
# log in. This can be done via sleep or via redirecting to a file and
# then reading from it.
try "
    # ADDOK u4 u1 \@second | (sleep 2; ssh u4 ukm); ok
    ADD u4 u1 \@second > session; ok
    cat session | ssh u4 ukm; ok;  /pending keyid added: \@second/
";

# u1 cannot add his/her initial key, since that key can never be
# confirmed via ukm, so it is forbidden altogether. In fact, u1 is not
# allowed to add any key twice.
try "
    ADDNOK u1 u1 \@first
       /FATAL: You cannot add a key that already belongs to you./
    ADDNOK u4 u1 \@first
       /FATAL: You cannot add a key that already belongs to you./
";

# u1 also can add more keys, but not under an existing keyid. That can
# be done by any of his/her identities (here we choose u4).
try "
    ADDNOK u5 u1 \@second; /FATAL: keyid already in use: \@second/
    ADD u5 u4 \@third > session; ok
    cat session | ssh u5 ukm; ok;  /pending keyid added: \@third/
";

# u2 cannot add the same key, but is allowed to use the same name (@third).
try "
    ADDNOK u5 u2 \@third; /FATAL: cannot add key/
        /Same key is already available under another userid./
    ADD u6 u2 \@third > session; ok
    cat session | ssh u6 ukm; ok;  /pending keyid added: \@third/
";

# u6 can schedule his/her own key for deletion, but cannot actually
# remove it. Trying to do so results in bringing back the key. Actual
# deletion must be confirmed by another key.
try "
    ssh u6 ukm del \@third; /prepare deletion of key \@third/
    ssh u2 ukm; ok; /u2     \@third .pending del./
    ssh u6 ukm; ok; /undo pending deletion of keyid \@third/
    ssh u6 ukm del \@third; /prepare deletion of key \@third/
    ssh u2 ukm del \@third; ok;  /pending keyid deleted: \@third/
";

# While in pending-deletion state, it's forbidden to add another key
# with the same keyid. It's also forbidden to add a key with the same
# fingerprint as the to-be-deleted key).
# A new key under another keyid, is OK.
try "
    ssh u1 ukm del \@third; /prepare deletion of key \@third/
    ADDNOK u4 u1 \@third; /FATAL: keyid already in use: \@third/
    ADDNOK u5 u1 \@fourth;
        /FATAL: You cannot add a key that already belongs to you./
    ADD u6 u1 \@fourth > session; ok
    ssh u1 ukm; ok;
        /u1     \@second/
        /u1     \@fourth .pending add./
        /u1     \@third .pending del./
";
# We can remove a pending-for-addition key (@fourth) by logging in
# with a non-pending key. Trying to do anything with key u5 (@third)
# will just bring it back to its normal state, but not change the
# state of any other key. As already shown above, using u6 (@fourth)
# without a proper session key, would remove it from the system.
# Here we want to demonstrate that key u1 can delete u6 immediately.
try "ssh u1 ukm del \@fourth; /pending keyid deleted: \@fourth/";

# The pending-for-deletion key @third can also be removed via the u4
# (@second) key.
try "ssh u4 ukm del \@third; ok; /pending keyid deleted: \@third/";

# Non-existing selfkeys cannot be deleted.
try "ssh u4 ukm del \@x; !ok; /FATAL: You are not managing the key \@x./";
