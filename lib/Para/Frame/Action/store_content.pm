package Para::Frame::Action::store_content;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.012;
use warnings;

use Para::Frame::File;
use Para::Frame::Utils qw( debug throw );

=head1 DESCRIPTION

Paranormal.se Stores content in given file

=cut

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
    my $tpaget = $tpage->template;

    unless( $u->has_page_update_access( $tpaget ) )
    {
	my $uname = $u->desig;
	throw('validation', "User $uname has no right to update $pagename");
    }

    $tpaget->set_content_as_text( \$content );

    return "Stored $pagename";
}

1;
