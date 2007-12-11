package Para::Frame::Client::Fixup;

use strict;
use warnings FATAL => qw(all);

use Apache2::Const -compile => qw(DIR_MAGIC_TYPE OK DECLINED);
use Apache2::RequestRec;

sub handler
{
    my $r = shift;

#    my $uri = $r->uri;
#    warn "In DirectoryFixup $uri\n";

    if( $r->handler eq 'perl-script' &&
        -d $r->filename              &&
        $r->is_initial_req )
    {
	my $dirconfig = $r->dir_config;
	if( $dirconfig->{'site'} and $dirconfig->{'site'} eq 'ignore' )
	{
#	    warn "  Setting DIR_MAGIC_TYPE\n";
	    $r->handler(Apache2::Const::DIR_MAGIC_TYPE);
	}

	return Apache2::Const::OK;
    }

    return Apache2::Const::DECLINED;
}

1;
