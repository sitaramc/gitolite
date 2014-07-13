#!/bin/bash

# author: damien.nozay@gmail.com

# Given a username,
# Provides a space-separated list of groups that the user is a member of.
#
# see http://gitolite.com/gitolite/conf.html#ldap
# GROUPLIST_PGM => /path/to/ldap_groups.sh

ldap_groups() {
    username=$1;
    # this relies on openldap / pam_ldap to be configured properly on your
    # system. my system allows anonymous search.
    echo $(
        ldapsearch -x -LLL "(&(objectClass=posixGroup)(memberUid=${username}))" cn \
        | grep "^cn" \
        | cut -d' ' -f2
    );
}

ldap_groups $@
