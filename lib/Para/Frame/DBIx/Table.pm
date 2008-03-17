#  $Id$  -*-cperl-*-
package Para::Frame::DBIx::Table;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2008 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::DBIx::Table - DB table objects

=cut

use strict;
use Carp qw( carp croak shortmess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug );
use Para::Frame::List;


#######################################################################

=head2 new

=cut

sub new
{
    my( $this, $table_in ) = @_;

    my $class = ref($this) || $this;

    my $table;

    unless( ref $table_in )
    {
	die "Malformed argument: $table_in";
    }

    $table = $table_in;
    return bless $table, $class;
}


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::DBIx>

=cut
