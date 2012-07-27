Github-users: click the 'wiki' link before sending me anything via github.

Existing users: this is gitolite v3.x.  If you are upgrading from v2.x this
file will not suffice; you *must* check the online docs (see below for URL).

------------------------------------------------------------------------


DOCUMENTATION FOR GITOLITE
==========================

This file contains basic documentation for a fresh, ssh-based, installation of
gitolite and basic usage of its most important features.

If you need more details on any of the topics covered here, or help with some
troubleshooting, or just wish to read about the advanced features not covered
here, please check the gitolite online documentation at:

    http://sitaramc.github.com/gitolite/master-toc.html

This file contains the following sections:

    INSTALLATION AND SETUP
    ADDING USERS AND REPOS
    HELP FOR YOUR USERS
    BASIC SYNTAX
    ACCESS RULES
    GROUPS
    COMMANDS
    THE 'rc' FILE
    GIT-CONFIG
    GIT-DAEMON
    GITWEB

    CONTACT
    LICENSE

------------------------------------------------------------------------


INSTALLATION AND SETUP
----------------------

    Server requirements:

      * any unix system
      * sh
      * git 1.6.6+
      * perl 5.8.8+
      * openssh 5.0+
      * a dedicated userid to host the repos (in this document, we assume it
        is 'git'), with shell access ONLY by 'su - git' from some other userid
        on the same server.

    Steps to install:

      * login as 'git' as described above

      * make sure ~/.ssh/authorized_keys is empty or non-existent

      * make sure your ssh public key from your workstation is available at
        $HOME/YourName.pub

      * run the following commands:

            git clone git://github.com/sitaramc/gitolite
            mkdir -p $HOME/bin
            gitolite/install -to $HOME/bin
            gitolite setup -pk YourName.pub

        If the last command doesn't run perhaps 'bin' in not in your 'PATH'.
        You can either add it, or just run:

            $HOME/bin/gitolite setup -pk YourName.pub


ADDING USERS AND REPOS
----------------------

    Do NOT add new repos or users manually on the server.  Gitolite users,
    repos, and access rules are maintained by making changes to a special repo
    called 'gitolite-admin' and pushing those changes to the server.

    ----

    To administer your gitolite installation, start by doing this on your
    workstation (if you have not already done so):

        git clone git@host:gitolite-admin

    **NOTE**: if you are asked for a password, something has gone wrong.

    Now if you 'cd gitolite-admin', you will see two subdirectories in it:
    'conf' and 'keydir'.

    To add new users alice, bob, and carol, obtain their public keys and add
    them to 'keydir' as alice.pub, bob.pub, and carol.pub respectively.

    To add a new repo 'foo' and give different levels of access to these
    users, edit the file 'conf/gitolite.conf' and add lines like this:

        repo foo
            RW+         =   alice
            RW          =   bob
            R           =   carol

    See the 'ACCESS RULES' section later for more details.

    Once you have made these changes, do something like this:

        git add conf
        git add keydir
        git commit -m 'added foo, gave access to alice, bob, carol'
        git push

    When the push completes, gitolite will add the new users to
    ~/.ssh/authorized_keys on the server, as well as create a new, empty, repo
    called 'foo'.


HELP FOR YOUR USERS
-------------------

    Once a user has sent you their public key and you have added them as
    specified above and given them access, you have to tell them what URL to
    access their repos at.  This is usually 'git clone git@host:reponame'; see
    man git-clone for other forms.

    **NOTE**: again, if they are asked for a password, something is wrong.

    If they need to know what repos they have access to, they just have to run
    'ssh git@host info'; see 'COMMANDS' section later for more on this.


BASIC SYNTAX
------------

    The basic syntax of the conf file is very simple.

      * Everything is space separated; there are no commas, semicolons, etc.,
        in the syntax.

      * Comments are in the usual perl/shell style.

      * User and repo names are as simple as possible; they must start with an
        alphanumeric, but after that they can also contain '.', '_', or '-'.

        Usernames can optionally be followed by an '@' and a domainname
        containing at least one '.'; this allows you to use an email address
        as someone's username.

        Reponames can contain '/' characters; this allows you to put your
        repos in a tree-structure for convenience.

      * There are no continuation lines.


ACCESS RULES
------------

    This section is mostly 'by example'.

    Gitolite's access rules are very powerful.  The simplest use was already
    shown above.  Here is a slightly more detailed example:

        repo foo
            RW+                     =   alice
            -   master              =   bob
            -   refs/tags/v[0-9]    =   bob
            RW                      =   bob
            RW  refs/tags/v[0-9]    =   carol
            R                       =   dave

    For clones and fetches, as long as the user is listed with an R, RW
    or RW+ in at least one rule, he is allowed to read the repo.

    For pushes, rules are processed in sequence until a rule is found
    where the user, the permission (see note 1), and the refex (note 2)
    *all* match.  At that point, if the permission on the matched rule
    was '-', the push is denied, otherwise it is allowed.  If no rule
    matches, the push is denied.

    Note 1: permission matching:

      * a permission of RW matches only a fast-forward push or create
      * a permission of RW+ matches any type of push
      * a permission of '-' matches any type of push

    Note 2: refex matching:
    (refex = optional regex to match the ref being pushed)

      * an empty refex is treated as 'refs/.*'
      * a refex that does not start with 'refs/' is prefixed with 'refs/heads/'
      * finally, a '^' is prefixed
      * the ref being pushed is matched against this resulting refex

    With all that background, here's what the example rules say:

      * alice can do anything to any branch or tag -- create, push,
        delete, rewind/overwrite etc.

      * bob can create or fast-forward push any branch whose name does
        not start with 'master' and create any tag whose name does not
        start with 'v'+digit.

      * carol can create tags whose names start with 'v'+digit.

      * dave can clone/fetch.


GROUPS
------

    Gitolite allows you to groups users or repos for convenience.  Here's an
    example that creates two groups of users:

        @staff      =   alice bob carol
        @interns    =   ashok

        repo secret
            RW      =   @staff

        repo foss
            RW+     =   @staff
            RW      =   @interns

    Group lists accumulate.  The following two lines have the same effect as
    the earlier definition of @staff above:

        @staff      =   alice bob
        @staff      =   carol

    You can also use group names in other group names:

        @all-devs   =   @staff @interns

    Finally, @all is a special group name that is often convenient to use if
    you really mean 'all repos' or 'all users'.


COMMANDS
--------

    Users can run certain commands remotely, using ssh.  For example:

        ssh git@host help

    prints a list of available commands.

    The most commonly used command is 'info'.  All commands respond to a
    single argument of '-h' with suitable information.

    If you have shell on the server, you have a lot more commands available to
    you; try running 'gitolite help'.


THE 'rc' FILE
--------------

    Some of the instructions below may require you to edit the rc file
    (~/.gitolite.rc on the server).

    The rc file is perl code, but you do NOT need to know perl to edit it.
    Just mind the commas, use single quotes unless you know what you're doing,
    and make sure the brackets and braces stay matched up.


GIT-CONFIG
----------

    Gitolite lets you set git-config values for individual repos without
    having to log on to the server and run 'git config' commands:

        repo foo
            config hooks.mailinglist = foo-commits@example.tld
            config hooks.emailprefix = '[foo] '
            config foo.bar = ''
            config foo.baz =

    **WARNING**

        The last syntax shown above is the *only* way to *delete* a config
        variable once you have added it.  Merely removing it from the conf
        file will *not* delete it from the repo.git/config file.

    **SECURITY NOTE**

        Some git-config keys allow arbitrary code to be run on the server.

        If all of your gitolite admins already have shell access to the server
        account hosting it, you can edit the rc file (~/.gitolite.rc) on the
        server, and change the GIT_CONFIG_KEYS line to look like this:

            GIT_CONFIG_KEYS     =>  '.*',

        Otherwise, give it a space-separated list of regular expressions that
        define what git-config keys are allowed.  For example, this one allows
        only variables whose names start with 'gitweb' or with 'gc' to be
        defined:

            GIT_CONFIG_KEYS     =>  'gitweb\..* gc\..*',


GIT-DAEMON
----------

    Gitolite creates the 'git-daemon-export-ok' file for any repo that is
    readable by a special user called 'daemon', like so:

        repo foo
            R   =   daemon


GITWEB
------

    Any repo that is readable by a special user called 'gitweb' will be added
    to the projects.list file.

        repo foo
            R   =   gitweb

    Or you can set one or more of the following config variables instead:

        repo foo
            config gitweb.owner         =   some person's name
            config gitweb.description   =   some description
            config gitweb.category      =   some category

    **NOTE**

        You will probably need to change the UMASK in the rc file from the
        default (0077) to 0027 and add whatever user your gitweb is running as
        to the 'git' group.  After that, you need to run a one-time 'chmod -R'
        on the already created files and directories.


------------------------------------------------------------------------


CONTACT
-------

    NOTE: Unless you have very good reasons, please use the mailing list below
    instead of mailing me personally.  If you have to mail me, use the gmail
    address instead of my work address.

    Author: sitaramc@gmail.com, sitaram@atc.tcs.com

    Mailing list for questions and general discussion:
        gitolite@googlegroups.com
        subscribe address: gitolite+subscribe@googlegroups.com

    Mailing list for announcements and notices:
        gitolite-announce@googlegroups.com
        subscribe address: gitolite-announce+subscribe@googlegroups.com

    IRC: #git and #gitolite on freenode.  Note that I live in India (UTC+0530
    time zone).


LICENSE
-------

    The gitolite *code* is released under GPL v2.  See COPYING for details.

    This documentation, which is part of the source code repository, is
    provided under a Creative Commons Attribution-ShareAlike 3.0 Unported
    License -- see http://creativecommons.org/licenses/by-sa/3.0/
