package Para::Frame::DBIx::Pg;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::DBIx::Pg - Wrapper module for DBI Pg

=cut

use 5.012;
use warnings;
use base "Para::Frame::DBIx";

use Carp qw( carp croak shortmess );
use DateTime::Format::Pg;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug package_to_module );
use Para::Frame::List;
use Para::Frame::DBIx::Table;

##############################################################################

=head2 init

  $dbix->init( \%args )

Sets C<datetime_formatter> to L<DateTime::Format::Pg> which uses SQL
standard C<ISO 8601> (2003-01-16T23:12:01+0200). It's used by
L<Para::Frame::DBIx/format_datetime>.

=cut

sub init
{
    my( $dbix, $args ) = @_;

    $args ||= {};

    $dbix->{'datetime_formatter'} = 'DateTime::Format::Pg';
}


##############################################################################

sub on_connect # not used
{
    my( $dbix ) = @_;

    my $dbh = $dbix->dbh;
    if( $dbh->{pg_server_version} > 90000 ) # 9.00.00
    {
	$dbh->do("set bytea_output='escape'");
    }
}

##############################################################################

=head2 bool

=cut

sub bool
{
    return 'f' unless $_[1];
    return 'f' if $_[1] eq 'f';
    return 't';
}


##############################################################################

=head2 tables

  $dbix->tables

Returns: a L<Para::Frame::List> of L<Para::Frame::DBIx::Table> objects

=cut

sub tables
{
    my( $dbix ) = @_;

    my $sth = $dbix->dbh->table_info('', 'public', '%', 'TABLE');
    $sth->execute();
    my @list;
    while( my $rec = $sth->fetchrow_hashref )
    {
	push @list, Para::Frame::DBIx::Table->new($rec);
    }
    $sth->finish;

    return Para::Frame::List->new(\@list);
}


##############################################################################

=head2 table

  $dbix->table( $name )

Returns: a L<Para::Frame::DBIx::Table> object for the table, or undef
if not exists;

=cut

sub table
{
    my( $dbix, $name ) = @_;

    my $sth = $dbix->dbh->table_info('', 'public', $name, 'TABLE');
    $sth->execute();
    my $rec = $sth->fetchrow_hashref;
    $sth->finish;

    if( $rec )
    {
	return Para::Frame::DBIx::Table->new($rec);
    }
    else
    {
	return undef;
    }
}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::DBIx>

=cut
