#  $Id$  -*-perl-*-
package Para::Frame::Action::server_terminate;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se stop the paraframe server
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( throw );

sub handler
{
    my( $req ) = @_;

    my $u = $Para::Frame::U;

    unless( $u->level >= 42 )
    {
	throw("denied", "Neeeeej! Vill inte!");
    }

    warn "Terminating server by request!\n";

    my $page = "<h1>Server terminated</h1><p><a href='/'>Back home</a>\n";

    $req->send_headers;
    $req->send_in_chunks( \$page );


    print "TERMINATE\n";
    sleep 10; # Waiting to die
    warn "No watchdog? Try to exit by myself...\n";
    exit;     # Tired of waiting...
}

1;
