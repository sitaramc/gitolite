# gitosis-lite

In this document:

  * "lite"?
  * what's extra
  * whats missing/TODO
  * workflow
  * conf file example

----

### "lite"?

I have been gitosis for a while, and have learnt a lot from it.  But in a
typical $DAYJOB setting, there are some issues.  It's not always Linux, so you
can't just "urpmi gitosis" and be done.  "python-setuptools" isn't often
installed (and on a Solaris 9 I was trying to help remotely, we never did
manage it).  And the most requested feature (see next section) had to be
written anyway.

While I was pondering having to finally learn python (I hate whitespace based
flow logic except for plain text; this is a *personal* opinion so pythonistas
can back off :-), I also realised that:

  * no one in $DAYJOB settings will use or approve access methods that work
    without any authentication, so I didn't need gitweb/daemon support in the
    tool
  * the idea that you admin it by pushing to a special repo is cute and
    convenient, but not really necessary because of how rarely these changes
    are made.

All of this pointed to a rewrite.  In perl, naturally.

I also gained (and used) an unfair advantage: gits newer than 1.6.2 can clone
an empty repo, so I don't need complex logic in the permissions checking part
to *create* the repo initially -- I just create an empty bare repo when I
"compile" the config file (see "workflow" below).

### what's extra?

A lot of people in my $DAYJOB type world want per-branch permissions, so I
copied the basic idea from
git.git:Documentation/howto/update-hook-example.txt.  I think this is the most
significant extra I have.  This includes not just who can push to what branch,
but also whether they are allowed to rewind it or not (non-ff push).

### what's missing/TODO

See TODO file

### workflow

I took the opportunity to change the workflow significantly.

  * all admin happens *on the server*, in a special directory
  * after making any changes, one "compiles" the configuration.  This
    refreshes `~/.ssh/authorized_keys`, as well as puts a parsed form of the
    access list in a file for the other two pieces to use.

Why pre-parse?  Because access control decisions are taken at two separate
stages now:

  * the program that is run via `~/.ssh/authorized_keys` (called
    `gl-auth-command`, equivalent to `gitosis-serve`) decides whether even git
    should be allowed to run (basic R/W/no access)
  * the update-hook on each repo, which decides the per-branch permissions.

But the user specifies only one access file, and he doesn't have to know these
distinctions.  So I avoid having to parse the access file in two completely
different programs by pre-compiling it and storing it as a perl "variable".
