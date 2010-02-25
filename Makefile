# this is a simple wrapper around "git archive" using make

# "make [refname].tar" produces a tar of refname, then adds a file containing
# the "git describe" output for that refname to the tar.  This lets you say
# "cat .GITOLITE-VERSION" to find out which ref produced this tar

# Note: I'm not sure if that "-r" is a GNU tar extension...

.GITOLITE-VERSION:
	@touch conf/VERSION

%.tar:	.GITOLITE-VERSION
	git describe --tags --long $* > conf/VERSION
	git archive $* > $@
	tar -r -f $@ conf/VERSION
	rm conf/VERSION
