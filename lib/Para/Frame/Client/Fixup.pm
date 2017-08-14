package Para::Frame::Client::Fixup;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.012;
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
