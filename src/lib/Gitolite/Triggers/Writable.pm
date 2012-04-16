package Gitolite::Triggers::Writable;

use Gitolite::Rc;
use Gitolite::Common;

sub access_1 {
    my ( $repo, $aa, $result ) = @_[ 1, 3, 5 ];
    return if $aa eq 'R' or $result =~ /DENIED/;

    for my $f ( "$ENV{HOME}/.gitolite.down", "$rc{GL_REPO_BASE}/$repo.git/.gitolite.down" ) {
        next unless -f $f;
        _die slurp($f) if -s $f;
        _die "sorry, writes are currently disabled (no more info available)\n";
    }
}

1;
