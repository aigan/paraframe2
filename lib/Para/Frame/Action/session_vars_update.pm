package Para::Frame::Action::session_vars_update;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

=head1 NAME

Para::Frame::Action::user_logou - For logging out

=cut

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $session = $req->session;

    my @varlist = split /\s*,\s*/, $q->param('session_vars_update');

    our %BLACKLIST;
    unless( %BLACKLIST )
    {
	%BLACKLIST = map {$_=>1}
	    qw(
	       sid
	       active
	       created
	       latest
	       user
	       debug
	       template_error
	       list
	       listid
	       route
	       referer
	       page_result
	      );
    }

    foreach my $key ( @varlist )
    {
	if( $BLACKLIST{$key} )
	{
	    die "You should not update session $key in this way";
	}
	$session->{$key} = $q->param($key);
    }

    return "";
}

1;
