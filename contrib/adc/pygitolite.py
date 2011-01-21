#!/usr/bin/env python
#
# Original author: Richard Bateman <taxilian@gmail.com>
#
# Any questions or concerns about how this works should be addressed to
# me, not to sitaram. Please note that neither I nor sitaram make any
# guarantees about the security or usefulness of this script. It may
# be used without warantee or any guarantee of any kind.
#
# This script is licensed under the New BSD license 
# Copyright 2011 Richard Bateman
#

import sys, os, subprocess

class gitolite(object):
    def __init__(self, **kvargs):
        self.GL_BINDIR = kvargs["GL_BINDIR"] if "GL_BINDIR" in kvargs else os.environ["GL_BINDIR"]
        self.user = kvargs["GL_USER"] if "GL_USER" in kvargs else os.environ["GL_USER"]
        pass

    def gitolite_execute(self, command, std_inputdata = None):
        cmd = "perl -I%s -Mgitolite -e '%s'" % (self.GL_BINDIR,command)
        p = subprocess.Popen(cmd, shell = True, stdout = subprocess.PIPE, stderr = subprocess.PIPE, stdin = subprocess.PIPE)
        stdout, stderr = p.communicate(std_inputdata)
        if p.returncode is not 0:
            raise Exception(stderr)
        return stdout.strip()

    def run_custom_command(self, repo, user, command, extra = None):
        os.environ["SSH_ORIGINAL_COMMAND"] = "%s %s" % (command, repo)
        return self.gitolite_execute('run_custom_command("%s")' % user, extra)

    def get_perms(self, repo, user):
        full = self.run_custom_command(repo, user, "getperms")
        plist = full.split("\n")
        perms = {}
        for line in plist:
            if line == "":
                continue
            var, strlist = line.split(" ", 1)
            perms[var] = strlist.split(" ")

        return perms

    def set_perms(self, repo, user, perms):
        permstr = ""
        for var, curlist in perms.iteritems():
            if len(curlist) == 0:
                continue;
            varstr = var
            for cur in curlist:
                varstr += " %s" % cur
            permstr = permstr + "\n" + varstr
        resp = self.run_custom_command(repo, user, "setperms", permstr.strip())

    def valid_owned_repo(self, repo, user):
        rights, user = self.get_rights_and_owner(repo, user)
        return owner == user

    def get_rights_and_owner(self, repo, user):
        if not repo.endswith(".git"):
            repo = "%s.git" % repo
        ans = self.gitolite_execute('cli_repo_rights("%s")' % repo)
        perms, owner = ans.split(" ")
        rights = {"Read": "R" in perms, "Write": "W" in perms, "Create": "C" in perms}
        return rights, owner

if __name__ == "__main__":
    if "GL_USER" not in os.environ:
        raise "No user!"
    user = os.environ["GL_USER"]
    repo = sys.argv[1]

    gl = gitolite()
    print gl.get_rights_and_owner(repo, user)
    print gl.get_perms(repo, user)
