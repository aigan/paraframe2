#  $Id$  -*-cperl-*-
package Para::Frame::Action::store_content;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Stores content in given file
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

use Para::Frame::File;
use Para::Frame::Utils qw( debug throw );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    my $pagename = $q->param('page');
    my $content = $q->param('content');

    my $u = $req->user;

    my $tpage = Para::Frame::File->new({url => $pagename,
					site => $req->site,
				       });

    unless( $u->has_page_update_access( $tpage ) )
    {
	my $uname = $u->name;
	throw('validation', "User $uname has no right to update $pagename");
    }

    $tpage->set_content( \$content );

    return "Stored $pagename";
}

1;