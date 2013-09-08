#!/usr/bin/env perl
#
# ipa_groups.pl
#
# See perldoc for usage
#
use Net::LDAP;
use Net::LDAP::Control::Paged;
use Net::LDAP::Constant qw(LDAP_CONTROL_PAGED);
use strict;
use warnings;

my $usage = <<EOD;
Usage: $0 \$uid
This script returns a list of groups that \$uid is a member of
EOD

my $uid = shift or die $usage;

## CONFIG SECTION

# If you want to do plain-text LDAP, then set ldap_opts to an empty hash and
# then set protocols of ldap_hosts to ldap://
my @ldap_hosts = [
  'ldaps://auth-ldap-001.prod.example.net',
  'ldaps://auth-ldap-002.prod.example.net',
];
my %ldap_opts = (
    verify => 'require',
    cafile => '/etc/pki/tls/certs/prod.example.net_CA.crt'
);

# Base DN to search
my $base_dn = 'dc=prod,dc=example,dc=net';

# User for binding to LDAP server with
my $user = 'uid=svc_gitolite_bind,cn=sysaccounts,cn=etc,dc=prod,dc=example,dc=net';
my $pass = 'reallysecurepasswordstringhere';

## Below variables should not need to be changed under normal circumstances

# OU where groups are located. Anything return that is not within this OU is
# removed from results. This OU is static on FreeIPA so will only need updating
# if you want to support other LDAP servers. This is a regex so can be set to
# anything you want (E.G '.*').
my $groups_ou = qr/cn=groups,cn=accounts,${base_dn}$/;

# strip path - if you want to return the full path of the group object then set
# this to 0
my $strip_group_paths = 1;

# Number of seconds before timeout (for each query)
my $timeout=5;

# user object class
my $user_oclass = 'person';

# group attribute
my $group_attrib = 'memberOf';

## END OF CONFIG SECTION

# Catch timeouts here
$SIG{'ALRM'} = sub {
  die "LDAP queries timed out";
};

alarm($timeout);

# try each server until timeout is reached, has very fast failover if a server
# is totally unreachable
my $ldap = Net::LDAP->new(@ldap_hosts, %ldap_opts) ||
  die "Error connecting to specified servers: $@ \n";

my $mesg = $ldap->bind(
    dn       => $user,
    password => $pass
);

if ($mesg->code()) {
  die ("error:",      $mesg->code(),"\n",
       "error name: ",$mesg->error_name(),"\n",
       "error text: ",$mesg->error_text(),"\n");
}

# How many LDAP query results to grab for each paged round
# Set to under 1000 to limit load on LDAP server
my $page = Net::LDAP::Control::Paged->new(size => 500);

# @queries is an array or array references. We initially fill it up with one
# arrayref (The first LDAP search) and then add more during the execution.
# First start by resolving the group.
my @queries = [ ( base    => $base_dn,
                  filter  => "(&(objectClass=${user_oclass})(uid=${uid}))",
                  control => [ $page ],
) ];

# array to store groups matching $groups_ou
my @verified_groups;

# Loop until @queries is empty...
foreach my $queryref (@queries) {

  # set cookie for paged querying
  my $cookie;
  alarm($timeout);
  while (1) {
    # Perform search
    my $mesg = $ldap->search( @{$queryref} );

    foreach my $entry ($mesg->entries) {
      my @groups = $entry->get_value($group_attrib);
      # find any groups matching $groups_ou  regex and push onto $verified_groups array
      foreach my $group (@groups) {
        if ($group =~ /$groups_ou/) {
          push @verified_groups, $group;
        }
      }
    }

    # Only continue on LDAP_SUCCESS
    $mesg->code and last;

    # Get cookie from paged control
    my($resp)  = $mesg->control(LDAP_CONTROL_PAGED) or last;
    $cookie    = $resp->cookie or last;

    # Set cookie in paged control
    $page->cookie($cookie);
  } # END: while(1)

  # Reset the page control for the next query
  $page->cookie(undef);

  if ($cookie) {
    # We had an abnormal exit, so let the server know we do not want any more
    $page->cookie($cookie);
    $page->size(0);
    $ldap->search( @{$queryref} );
    # Then die
    die("LDAP query unsuccessful");
  }

} # END: foreach my $queryref (...)

# we're assuming that the group object looks something like
# cn=name,cn=groups,cn=accounts,dc=X,dc=Y and there are no ',' chars in group
# names
if ($strip_group_paths) {
  for (@verified_groups) { s/^cn=([^,]+),.*$/$1/g };
}

foreach my $verified (@verified_groups) {
  print $verified . "\n";
}

alarm(0);

__END__

=head1 NAME

ipa_groups.pl

=head2 VERSION

0.1.1

=head2 DESCRIPTION

Connects to one or more FreeIPA-based LDAP servers in a first-reachable fashion and returns a newline separated list of groups for a given uid. Uses memberOf attribute and thus supports nested groups.

=head2 AUTHOR

Richard Clark <rclark@telnic.org>

=head2 FreeIPA vs Generic LDAP

This script uses regular LDAP, but is focussed on support for FreeIPA, where users and groups are generally contained within single OUs, and memberOf attributes within the user object are enumerated with a recursive list of groups that the user is a member of.

It is mostly impossible to provide generic out of the box LDAP support due to varying schemas, supported extensions and overlays between implementations.

=head2 CONFIGURATION

=head3  LDAP Bind Account 

To setup an LDAP bind user in FreeIPA, create a svc_gitolite_bind.ldif file along the following lines:

    dn: uid=svc_gitolite_bind,cn=sysaccounts,cn=etc,dc=prod,dc=example,dc=net
    changetype: add
    objectclass: account
    objectclass: simplesecurityobject
    uid: svc_gitolite_bind
    userPassword: reallysecurepasswordstringhere
    passwordExpirationTime: 20150201010101Z
    nsIdleTimeout: 0

Then create the service account user, using ldapmodify authenticating as the the directory manager account (or other acccount with appropriate privileges to the sysaccounts OU):

    $ ldapmodify -h auth-ldap-001.prod.example.net -Z -x -D "cn=Directory Manager" -W -f svc_gitolite_bind.ldif

=head3 Required Configuration

The following variables within the C<## CONFIG SECTION ##> need to be configured before the script will work.

C<@ldap_hosts> - Should be set to an array of URIs or hosts to connect to. Net::LDAP will attempt to connect to each host in this list and stop on the first reachable server. The example shows TLS-supported URIs, if you want to use plain-text LDAP then set the protocol part of the URI to LDAP:// or just provide hostnames as this is the default behavior for Net::LDAP.

C<%ldap_opts> - To use LDAP-over-TLS, provide the CA certificate for your LDAP servers. To use plain-text LDAP, then empty this hash of it's values or provide other valid arguments to Net::LDAP.

C<%base_dn> - This can either be set to the 'true' base DN for your directory, or alternatively you can set it the the OU that your users are located in (E.G cn=users,cn=accounts,dc=prod,dc=example,dc=net).

C<$user> - Provide the full Distinguished Name of your directory bind account as configured above.

C<$pass> - Set to password of your directory bind account as configured above.

=head3 Optional Configuration

C<$groups_ou> - By default this is a regular expression matching the default groups OU. Any groups not matching this regular expression are removed from the search results. This is because FreeIPA enumerates non-user type groups (E.G system, sudoers, policy and other types) within the memberOf attribute. To change this behavior, set C<$groups_ou> to a regex matching anything you want (E.G: '.*').

C<$strip_group_paths> - If this is set to perl boolean false (E.G '0') then groups will be returned in DN format. Default is true, so just the short/CN value is returned.

C<$timeout> - Number of seconds to wait for an LDAP query before determining that it has failed and trying the next server in the list. This does not affect unreachable servers, which are failed immediately.

C<$user_oclass> - Object class of the user to search for.

C<$group_attrib> - Attribute to search for within the user object that denotes the membership of a group.

=cut

