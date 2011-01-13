#!/bin/sh
#
# Copyright (c) 2010 Nokia Corporation
#
# This code is licensed to you under MIT-style license. License text for that
# MIT-style license is as follows:
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# ldap-query.sh <arg1>
#
# this script is used to perform ldap querys by giving one argument:
# - <arg1> the user UID for ldap search query
#
# NOTICE: This script requires ldap-utils and sed to be installed to the system.
#

# Script requires user UID as the only parameter
#
if [ $# -ne 1 ]
then
        echo "ldap-query.sh requires one argument, user's uid"
        exit 1
fi
uid_param="${1}"

# Set needed LDAP search tool options for the query
ldap_host="localhost"
ldap_binddn="cn=administrator,o=company"
ldap_bindpw="5ecretpa55w0rd"
ldap_searchbase="ou=users,ou=department,o=company"
ldap_scope="subtree"

# Construct the command line base with needed options for the LDAP query
ldap_options="-h ${ldap_host} -x -D ${ldap_binddn} -w ${ldap_bindpw} -b ${ldap_searchbase} -s ${ldap_scope}"

# Construct the search filter for the LDAP query for the given UID
ldap_filter="(&(objectClass=groupAttributeObjectClassName)(uid=${uid_param}))"

# Construct return attribute list for LDAP query result
attr1="defaultGroupAttributeName"
attr2="extraGroupsAttributeName"
ldap_attr="${attr1} ${attr2}"

# Execute the actual LDAP search to get groups for the given UID
ldap_result=$(ldapsearch ${ldap_options} -LLL ${ldap_filter} ${ldap_attr})

# Edit search result to get space separated list of group names
ldap_result=$(echo ${ldap_result} | sed -e "s/.* ${attr1}://" -e "s/ ${attr2}://")

# Return group names for given user UID
echo ${ldap_result}
