#!/usr/bin/perl
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
# ldap-query.pl <arg1>
#
# this script is used to perform ldap querys by giving one argument:
# - <arg1> the user UID for ldap search query
#
# NOTICE: This script requires libnet-ldap-perl package to be installed
#         to the system.
#

use Net::LDAP;

# Script requires user UID as the only parameter
if ( $ARGV[0] eq '' || $ARGV[1] ne '' )
{
	print "ldap-query.pl requires one argument, user's uid\n";
	exit 1;
}
$user = $ARGV[0];

# Create communication structure for LDAP connection
$ldap = Net::LDAP->new(
      'localhost',
      port    => 389,
      debug   => 0,
      timeout => 120,
      version => 3 ) or die "$@";

# Bind to LDAP with proper user
$ldapret = $ldap->bind( 'cn=administrator,o=company',
			password => '5ecretpa55w0rd' );
die "$ldapret->code" if $ldapret->code;

# Create filter for LDAP query
my $filter = '(&'.
	'(objectClass=groupAttributeObjectClassName)'.
	"(uid=$user)".
	')';

# Execute the actual LDAP search to get groups for the given UID
$ldapret = $ldap->search( base   => 'ou=users,ou=department,o=company',
                          scope	 => 'subtree',
                          filter => $filter );

# Parse search result to get actual group names
my $default_group = '';
my $extra_groups = '';

foreach my $entry ( $ldapret->entries ) {

	$default_group = $entry->get_value( 'defaultGroupAttributeName' ) . ' ' . "$default_group";
	$extra_groups = $entry->get_value( 'extraGroupsAttributeName' ) . ' ' . "$extra_groups";
}

# Return group names for given user UID
print "$default_group" . "$extra_groups";
