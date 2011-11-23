# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

BEGIN { require 5.010 }
use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
	      'NAME'	       => 'Para::Frame',
#	      'PMLIBDIRS'      => [],
#	      'SKIP'           => ['all','install'],
 	      'VERSION_FROM'   => 'lib/Para/Frame.pm', # finds $VERSION
	      'ABSTRACT_FROM'  => 'lib/Para/Frame.pm',
	      'AUTHOR'         => 'Jonas Liljegren <jonas@paranormal.se>',
 	      'PREREQ_PM'      =>
	      {
		  'BerkeleyDB'                 => 0.26,
                  'Captcha::reCAPTCHA'         => 0.92,
		  'Carp'                       => 1.04,
		  'CGI'                        => 3.46,
		  'CGI::Cookie'                => 1.25,
#		  'Crypt::OpenPGP'             => 1.03,
	          'Data::Dump'                 => 1.08,
	          'Data::Validate::Domain'     => 0.08,
		  'Date::Manip'                => 5.44,
		  'DateTime'                   => 0.2901,
	          'DateTime::Format::HTTP'     => 0.00,
	          'DateTime::Format::Pg'       => 0.16003,
	          'DateTime::Format::Strptime' => 0.00,
		  'DateTime::Format::MySQL'    => 0.00,
		  'DateTime::Set'              => 0.22,
		  'DateTime::TimeZone'         => 0.37,
	          'DateTime::Incomplete'       => 0.02,
		  'DBI'                        => 1.48,
		  'Digest::MD5'                => 2.33,
	          'Email::MIME'                => 1.902,
		  'Encode'                     => 2.10,
	          'Encode::Detect::Detector'   => 1.00,
	          'Encode::InCharset'          => 0.03,
		  'File::Basename'             => 2.73,
	          'File::MimeInfo'             => 0.13,
                  'File::Remove'               => 0.31,
		  'File::Slurp'                => 9999.09,
		  'File::Spec'                 => 3.05,
		  'File::stat'                 => 1.00,
		  'FreezeThaw'                 => 0.43,
		  'HTTP::BrowserDetect'        => 1.25,
		  'HTTP::Request'              => 1.40,
		  'IDNA::Punycode'             => 0.02,
	          'Image::Magick'              => 6.002004,
		  'IO'                         => 1.21,
	          'IO::Socket'                 => 1.29,
	          'List::Uniq'                 => 0.10,
		  'LWP::UserAgent'             => 2.03,
		  'Mail::Address'              => 1.62,
		  'MIME::Lite'                 => 3.01,
		  'MIME::Words'                => 5.41,
		  'Net::DNS'                   => 0.48,
                  'Net::SCP'                   => 0.07,
		  'Net::SMTP'                  => 2.29,
	          'Net::Domain::TLD'           => 1.67,
                  'Number::Bytes::Human'       => 0.04,
		  'Proc::ProcessTable'         => 0.39,
		  'Socket'                     => 1.77,
		  'Sys::CpuLoad'               => 0.02,
		  'Template'                   => 2.15,
		  'Text::Autoformat'           => 1.12,
		  'Time::HiRes'                => 1.66,
		  'Time::Piece'                => 1.08,
		  'Unicode::MapUTF8'           => 1.09,
		  'URI'                        => 1.59,
		  'URI::QueryParam'            => 0.00,
                  'Test::Pod::Coverage'        => 1.08,
		  'Spreadsheet::ParseExcel'    => 0.32,
		  'Linux::SysInfo'             => 0.10,
		  'JSON'                       => 2.17,
		  'XML::Simple'                => 2.18,

# Testing
		  'Test::More'                 => 0.61,
		  'Test::Warn'                 => 0.08,
		  'Test::Perl::Critic'         => 1.01,
		  'Test::Distribution'         => 2.00,
		  'Test::Pod'                  => 1.26,
		  'Test::Strict'               => 0.09,
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

sub postamble
{
    my ($mm, %args) = @_;
    my $postamble = "";


    # first, we must add a target in install::
    for my $makeline (@{ $mm->{RESULT} }) {
        $makeline =~ s/(install *::.+)\n/$1 priv_data_files\n/;
    }

    # then, declare the target with the files
    $postamble .= "\nINSTALL = install -p -D\n\npriv_data_files:\n";
#    $postamble .= "\tpwd\n";
#    $postamble .= "\techo \$(DISTVNAME)\n";

    use File::Find;
    find(\&wanted, 'share');
    sub wanted
    {
        next if -d;
        $File::Find::name =~ m/^share\/(.*)/ or next;
        my $file = $1;
        $postamble .= "\tcd share && \$(INSTALL) $file \$(SITEPREFIX)/share/paraframe/$file\n";
    }

    return $postamble

#    die $mm->dist_target;
#    die "INSTALL!?!?";
}


1;
