#  $Id$  -*-perl-*-
package Para::Frame::DBIx::mysql;
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

Para::Frame::DBIx::mysql - Wrapper module for DBI mysql

=cut

use strict;
use Carp qw( carp croak shortmess confess );
use DateTime::Format::MySQL;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug package_to_module );
use Para::Frame::List;

use base "Para::Frame::DBIx";


#######################################################################

=head2 init

  $dbix->init( \%args )

Sets C<datetime_formatter> to L<DateTime::Format::MySQL> which uses a
format like "2003-01-16 23:12:01". It's used by
L<Para::Frame::DBIx/format_datetime>.

=cut

sub init
{
    my( $dbix, $args ) = @_;

    $args ||= {};

    $dbix->{'datetime_formatter'} = 'DateTime::Format::MySQL';
}


#######################################################################

=head2 get_nextval

=cut

sub get_nextval
{
    confess "get_nextval not working in MySQL";
}


#######################################################################

=head2 get_lastval

=cut

sub get_lastval
{
    return $_[0]->dbh->{'mysql_insertid'};
}


#######################################################################

=head2 bool

=cut

sub bool
{
    return '0' unless $_[1];
    return '0' if $_[1] eq 'f';
    return '1';
}


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::DBIx>

=cut
