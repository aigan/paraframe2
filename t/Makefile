#
#  ./t/Makefile
#
#  Run our tests, either quietly or with verbose output
#
#  This is a Makefile - so the indented lines start with a TAB!
#
#  Whoever came up with the wonderful idea that whitespace was significant..?
#
all:
	perl -MTest::Harness -e '$$Test::Harness::verbose=0; runtests @ARGV;' *.t
verbose:
	perl -MTest::Harness -e '$$Test::Harness::verbose=1; runtests @ARGV;' *.t
clean:
	find . -name '*~' -exec rm -f \{\} \;
new:
	perl -I../lib -MTest::Harness -e '$$Test::Harness::verbose=1; runtests @ARGV;' 02_frame.t
strict:
	perl -I../lib -MTest::Harness -e '$$Test::Harness::verbose=0; runtests @ARGV;' strict.t
