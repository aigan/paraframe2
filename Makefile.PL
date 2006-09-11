# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

BEGIN { require 5.008 }
use ExtUtils::MakeMaker;

WriteMakefile(
	      'NAME'	       => 'Para::Frame',
	      'PMLIBDIRS'      => [],
	      'SKIP'           => ['all','install'],
 	      'VERSION_FROM'   => 'lib/Para/Frame.pm', # finds $VERSION
	      'ABSTRACT_FROM'  => 'lib/Para/Frame.pm',
	      'AUTHOR'         => 'Jonas Liljegren <jonas@paranormal.se>',
 	      'PREREQ_PM'      =>
	      {
		  'Socket'                     => 1.77,
		  'Text::Autoformat'           => 1.12,
		  'Time::HiRes'                => 1.66,
		  'Carp'                       => 1.04,
		  'Sys::CpuLoad'               => 0.02,
		  'Template'                   => 2.15,
		  'FreezeThaw'                 => 0.43,
		  'File::Slurp'                => 0.00,
		  'CGI'                        => 3.10,
		  'CGI::Cookie'                => 1.25,
		  'DBI'                        => 1.48,
		  'Net::DNS'                   => 0.48,
		  'Net::SMTP'                  => 2.29,
		  'Mail::Address'              => 1.62,
		  'MIME::Lite'                 => 3.01,
		  'MIME::Words'                => 5.41,
		  'Crypt::OpenPGP'             => 1.03,
		  'HTTP::BrowserDetect'        => 0.98,
		  'File::stat'                 => 1.00,
		  'File::Basename'             => 2.73,
		  'URI'                        => 1.35,
		  'Encode'                     => 2.10,
		  'LWP::UserAgent'             => 2.03,
		  'HTTP::Request'              => 1.40,
		  'URI::QueryParam'            => 0.00,
		  'Date::Manip'                => 5.44,
		  'DateTime'                   => 0.2901,
		  'DateTime::Set'              => 0.22,
		  'DateTime::TimeZone'         => 0.37,
	          'DateTime::Format::Pg'       => 0.08,
	          'DateTime::Format::Strptime' => 0.00,
	          'DateTime::Format::HTTP'     => 0.00,
		  'File::Spec'                 => 3.05,
		  'IO'                         => 1.21,
	          'IO::Socket'                 => 1.29,
		  'Digest::MD5'                => 2.33,
		  'Time::Piece'                => 1.08,
		  'BerkeleyDB'                 => 0.26,
		  'IDNA::Punycode'             => 0.02,
		  'Unicode::MapUTF8'           => 1.09,
		  'Proc::ProcessTable'         => 0.39,
		  'Test::More'                 => 0.61,
		  'Test::Warn'                 => 0.08,
	      },
	      'dist'          =>
	      {
		  'COMPRESS' => 'gzip',
		  'SUFFIX'   => 'gz',
	      }
);

package MY; # so that "SUPER" works right
sub test
{
    my $inherited = shift->SUPER::test(@_);
    $inherited =~ s/test_dynamic :: pure_all/test_dynamic ::/;
    return $inherited;
}

sub test_via_harness
{
    my($self, $perl, $tests) = @_;

    return qq{\t$perl "-MExtUtils::Command::MM" }.
           qq{"-e" "test_harness(\$(TEST_VERBOSE), 'lib')" $tests\n};
}


1;
