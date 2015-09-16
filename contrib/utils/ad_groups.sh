#!/bin/bash

# author derived from: damien.nozay@gmail.com
# author: Jonathan Gray

# Given a username,
# Provides a space-separated list of groups that the user is a member of.
#
# see http://gitolite.com/gitolite/conf.html#ldap
# GROUPLIST_PGM => /path/to/ldap_groups.sh

# Be sure to add your domain CA to the trusted certificates in /etc/openldap/ldap.conf using the TLS_CACERT option or you'll get certificate validation errors

ldaphost='ldap://AD.DC1.local:3268,ldap://AD.DC2.local:3268,ldap://AD.DC3.local:3268'
ldapuser='git@domain.local'
ldappass='super.secret.password'
binddn='dc=domain,dc=local'
username=$1;

# I don't assume your users share a common OU, so I search the entire domain
ldap_groups() {
        # Go fetch the full user CN as it could be anywhere inside the DN
        usercn=$(
                ldapsearch -ZZ -H ${ldaphost} -D ${ldapuser} -w ${ldappass} -b ${binddn} -LLL -o ldif-wrap=no "(sAMAccountName=${username})" \
                | grep "^dn:" \
                | perl -pe 's|dn: (.*?)|\1|'
        )

        # Using a proprietary AD extension, let the AD Controller resolve all nested group memberships
        # http://ddkonline.blogspot.com/2010/05/how-to-recursively-get-group-membership.html
        # Also, substitute spaces in AD group names for '_' since gitolite expects a space separated list
        echo $(
                ldapsearch -ZZ -H ${ldaphost} -D ${ldapuser} -w ${ldappass} -b ${binddn} -LLL -o ldif-wrap=no "(member:1.2.840.113556.1.4.1941:=${usercn})" \
                | grep "^dn:" \
                | perl -pe 's|dn: CN=(.*?),.*|\1|' \
                | sed 's/ /_/g'
        )
}

ldap_groups $@
