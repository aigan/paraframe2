#  $Id$  -*-perl-*-
package Para::Frame::DBIx::Pg;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework DBI Pg extension class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::DBIx::Pg - Wrapper module for DBI Pg

=cut

use strict;
use Carp qw( carp croak shortmess );
use DateTime::Format::Pg;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug package_to_module );
use Para::Frame::List;

use base "Para::Frame::DBIx";

=head2 init

  $dbix->init( \%args )

Sets C<datetime_formatter> to L<DateTime::Format::Pg> which uses SQL
standard C<ISO 8601> (2003-01-16T23:12:01+0200). It's used by
L</format_datetime>.

=cut

sub init
{
    my( $dbix, $args ) = @_;

    $args ||= {};

    $dbix->{'datetime_formatter'} = 'DateTime::Format::Pg';
}


1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::DBIx>

=cut
