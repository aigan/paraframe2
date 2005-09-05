#  $Id$  -*-perl-*-
package Para::Frame::DBIx;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework DBI extension class
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

=head1 NAME

Para::Frame::DBIx - Wrapper module for DBI

=cut

use strict;
use DBI qw(:sql_types);
use Carp;
use locale;
use Data::Dumper;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug timediff );
use Para::Frame::Time qw( date );

use base qw( Exporter );
BEGIN
{
    our @EXPORT_OK = qw( pgbool );
}



=head1 DESCRIPTION

C<Para::Frame::DBIx> is an optional module.  It will not be used unless
the application calls it.

The application should initiate the connection and store the object in
C<$app-E<gt>{dbix}>.  That is not enforced.  Just praxis.

Multipple connections are not supported.

On error, an 'dbi' exception is thrown.

=head2 Exported objects

=over

=item L</select_list>

=item L</select_record>

=item L</select_possible_record>

=item L</select_key>

=back

=head1 METHODS

=cut


#######################################################################

=head2 select_list

  Perl: $dbix->select_list($statement, @vals)
  Tmpl: select_list(statement, val1, val2, ... )

Executes the $statement, substituting all '?' within with the values.

The C<select *> part of the statement can be left out.

=head3 Template example

  [% FOREACH select_list('from user where age > ?', agelimit) %]
     <li>[% name ] is [% age %] years old
  [% END %]

=head3 Returns

a ref to a list of hash records

=head3 Exceptions

dbi : DBI returned error

=cut

sub select_list
{
    my( $self, $st, @vals ) = @_;
    #
    # Return list or records

    if( ref $vals[0] eq 'ARRAY' )
    {
	@vals = @{$vals[0]};
    }

    my $ref;
    throw('incomplete','no parameter to statement') unless $st;
    $st = "select * ".$st if $st !~/^\s*select\s/i;

    eval
    {
	my $sth = $self->dbh->prepare( $st );
	$sth->execute(@vals);
	$ref =  $sth->fetchall_arrayref({});
	$sth->finish;
    };
    if( $@ )
    {
	debug(0,"Select list error");
	$@ =~ s/ at \/.*//;
	my $error = catch($@);
	my $info = $error->info;
	my( $package, $filename, $line ) = caller();
	$info .= "\nCalled by $package at line $line\n";
	my $values = join ", ", @vals;
	throw('dbi', "$st;\nValues: $values\n$info");
    }

    return $ref;
}


#######################################################################

=head2 select_record

  Perl: $dbix->select_record($statement, @vals)
  Tmpl: select_record(statement, val1, val2, ... )

Executes the $statement, substituting all '?' within with the values.

The C<select *> part of the statement can be left out.

=head3 Template example

  [% user = select_record('from user where uid = ?', uid) %]
  <p>[% user.name ] is [% user.age %] years old

=head3 Returns

a ref to the first hash record

=head3 Exceptions

dbi : DBI returned error

dbi : no records was found

=cut

sub select_record
{
    my( $self, $st, @vals ) = @_;
    #
    # Return list or records

    if( ref $vals[0] eq 'ARRAY' )
    {
	@vals = @{$vals[0]};
    }

    my $ref;
    throw('incomplete','no parameter to statement') unless $st;
    $st = "select * ".$st if $st !~/^\s*select\s/i;

#    warn "SQL: $st (@vals)\n"; ### DEBUG
    my $sth = $self->dbh->prepare( $st );
    $sth->execute( @vals ) or croak "$st (@vals)\n";
    $ref =  $sth->fetchrow_hashref
	or throw('dbi',$st."(@vals)\nFound ".$sth->rows()." rows\n");
    $sth->finish;

    return $ref;
}

#######################################################################

=head2 select_possible_record

  Perl: $dbix->select_possible_record($statement, @vals)
  Tmpl: select_possible_record(statement, val1, val2, ... )

Executes the $statement, substituting all '?' within with the values.

The C<select *> part of the statement can be left out.

=head3 Template example

  [% user = select_record('from user where uid = ?', uid) %]
  [% IF user %]
     <p>[% user.name ] is [% user.age %] years old
  [% END %]

=head3 Returns

a ref to the first hash record or C<undef> if no record was found

=head3 Exceptions

dbi : DBI returned error

=cut

sub select_possible_record
{
    my( $self, $statement, @vals ) = @_;
    #
    # Return list or records

    if( ref $vals[0] eq 'ARRAY' )
    {
	@vals = @{$vals[0]};
    }

    my $ref;
    throw('incomplete','no parameter to statement') unless $statement;
    $statement = "select * ".$statement if $statement !~/^\s*select\s/i;

    my $sth = $self->dbh->prepare( $statement )
	or croak $statement;
    $sth->execute( @vals );
    $ref =  $sth->fetchrow_hashref;
    $sth->finish;

    return $ref;
}


#######################################################################

=head2 select_key

  Perl: $dbix->select_key($field, $statement, @vals)
  Tmpl: select_key(field, statement, val1, val2, ... )

Executes the $statement, substituting all '?' within with the values.
$field should be the primary key or have unique values.

The C<select *> part of the statement can be left out.

=head3 Template example

  [% user = select_key('uid', 'from user') %]
  [% FOREACH id = user.keys %]
     <p>$id: [% user.$id.name ] is [% user.$id.age %] years old
  [% END %]

=head3 Returns

The result is indexed on $field.  The records are returned as a ref to
a indexhash och recordhashes.

Each index will hold the last record those $field holds that value.

=head3 Exceptions

dbi : DBI returned error

=cut

sub select_key
{
    my( $self, $keyf, $st, @vals ) = @_;
    #
    # Return ref to hash of records

    if( ref $vals[0] eq 'ARRAY' )
    {
	@vals = @{$vals[0]};
    }

    $st = "select * ".$st if $st !~/^\s*select\s/i;

    my $sth = $self->dbh->prepare( $st );
    $sth->execute( @vals );
    my $rh = {};
    while( my $r = $sth->fetchrow_hashref )
    {
	$rh->{$r->{$keyf}} = $r;
    }
    $sth->finish;

    return $rh;
}


sub new
{
    my( $class, $params ) = @_;

    $params ||= {};

    my $dbix = bless {}, $class;

    Para::Frame->add_global_tt_params({
	'select_list'              => sub{ $dbix->select_list(@_) },
	'select_record'            => sub{ $dbix->select_record(@_) },
	'select_key'               => sub{ $dbix->select_key(@_) },
	'select_possible_record'   => sub{ $dbix->select_possible_record(@_) },
    });

    if( my $connect = $params->{'connect'} )
    {
	$connect = [$connect] unless ref $connect eq 'ARRAY';

	# Default DBI options
	$connect->[3] ||= 
	{
	    RaiseError => 1,
	    ShowErrorStatement => 1,
	    PrintError => 0,
	    AutoCommit => 0,
	};

	$dbix->{'connect'} = $connect;
    }

    $dbix->{'bind_dbh'} = $params->{'bind_dbh'};


    Para::Frame->add_hook('done', sub
			  {
			      $dbix->commit;
			  });

    Para::Frame->add_hook('before_switch_req', sub
			  {
			      $dbix->commit;
			  });

    # I tried to just setting InactiveDestroy. But several processes
    # can't share a dbh. Multiple requests/multiple forsk may/will
    # result in errors like "message type 0x43 arrived from server
    # while idle" and "message type 0x5a arrived from server while
    # idle". Solve this by reconnecting in forks. TODO: reconnect on
    # demand instead of always

    Para::Frame->add_hook('on_fork', sub
			  {
			      debug(0,"Do not destroy DBH in child");
			      $dbix->dbh->{'InactiveDestroy'} = 1;
			      $dbix->connect();
			  });

    Para::Frame->add_hook('on_error_detect', sub
			  {
			      my( $typeref, $inforef ) = @_;

			      if( $Para::Frame::FORK )
			      {
				  die "In DBIx error hook during FORK\n";
			      }
				      
#				      confess("-- rollback...");

			      if( $dbix->dbh->err() )
			      {
				  $$inforef .= "\n". $dbix->dbh->errstr();
				  $$typeref ||= 'dbi';
			      }
			      elsif( DBI->err() )
			      {
				  $$inforef .= "\n". DBI->errstr();
				  $$typeref ||= 'dbi';
			      }
				      
			      debug(0,"ROLLBACK DB");

			      eval
			      {
				  $dbix->rollback();
			      } or do
			      {
				  debug(0,"FAILED ROLLBACK!");
				  debug $@;
				  debug $dbix->dbh->errstr;
			      };
			  });


    # Use the on_startup hook
    # $dbix->connect;

    return $dbix;
}

sub connect
{
    my( $dbix ) = @_;

    my $connect = $dbix->{'connect'} or return 0;

    eval
    {
	$dbix->{'dbh'} = DBI->connect(@$connect);
	debug(1,"Connected to DB $connect->[0]");
    };
    if( $@ )
    {
	debug(0,"Problem connecting to DB using @$connect[0..1]");
	throw( $@ );
    }

    if( $dbix->{'bind_dbh'} )
    {
	${ $dbix->{'bind_dbh'} } = $dbix->{'dbh'};
	debug(2,"  Bound dbh");
    }

    Para::Frame->run_hook( $Para::Frame::REQ, 'after_db_connect', $dbix);

    return 1;
}

sub commit
{
    my( $dbix ) = @_;

    Para::Frame->run_hook( $Para::Frame::REQ, 'before_db_commit', $dbix);
    $dbix->dbh->commit;
}

sub rollback
{
    my( $dbix ) = @_;

    $dbix->dbh->rollback;
    Para::Frame->run_hook( $Para::Frame::REQ, 'after_db_rollback', $dbix);
}

sub dbh { $_[0]->{'dbh'} }

sub get_nextval
{
    my( $self, $seq ) = @_;

    my $sth = $self->dbh->prepare( "select nextval(?)" );
    $sth->execute( $seq ) or croak "Faild to get next from $seq\n";
    my( $id ) = $sth->fetchrow_array;
    $sth->finish;

    $id or throw ('sql', "Failed to get nextval\n");
}

sub equals
{
    return $_[0] eq $_[1];
}

sub save_record
{
    my( $dbix, $param ) = @_;

    my $rec_new = $param->{'rec_new'} or die;
    my $types = $param->{'types'} || {};
    my $rec_old = $param->{'rec_old'};
    my $table = $param->{'table'} or die;
    my $key = $param->{'key'} || $table;
    my $keyval = $param->{'keyval'} or die;
    my $fields_to_check = $param->{'fields_to_check'} || [keys %$rec_new];
    my $on_update = $param->{'on_update'} || undef;

    $key = [$key] unless ref $key;
    $keyval = [$keyval] unless ref $keyval;


    my( @fields, @values );
    my %fields_added;

    foreach my $field ( @$fields_to_check )
    {
	my $type = $types->{$field} || 'string';

	if( $type eq 'string' )
	{
	    if( ($rec_new->{ $field }||'') ne ($rec_old->{ $field }||'') )
	    {
		$fields_added{ $field } ++;
		push @fields, $field;
		push @values, $rec_new->{ $field };
		debug(1,"  field $field differ");
	    }
	}
	elsif( $type eq 'boolean' )
	{
	    if( pgbool($rec_new->{ $field }) ne pgbool($rec_old->{ $field }) )
	    {
		$fields_added{ $field } ++;
		push @fields, $field;
		push @values, pgbool( $rec_new->{ $field } );
		debug(1,"  field $field differ");
	    }
	}
	elsif( $type eq 'date' )
	{
	    # Dates can be written in many formats. We will assume that if
	    # the date has changed from what the DB returns, it's not the
	    # same date. That keeps us from bothering about the format

	    if( ($rec_new->{ $field }||'') ne ($rec_old->{ $field }||'') )
	    {
		$fields_added{ $field } ++;
		push @fields, $field;
		push @values, date( $rec_new->{ $field } )->cdate;
		debug(1,"  field $field differ");
	    }
	}
	else
	{
	    throw('action', "Type $type not recoginzed");
	}
    }

    if( @fields )
    {
	if( $on_update )
	{
	    foreach my $field ( keys %$on_update )
	    {
		next if $fields_added{ $field };
		push @fields, $field;
		push @values, $on_update->{$field};		
	    }
	}

	my $where = join ' and ', map "$_=?", @$key;

	my $statement = "update $table set ".
	    join( ', ', map("$_=?", @fields)) .
	    " where $where";
	debug(4,"Executing statement $statement");
	my $sth = $dbix->dbh->prepare( $statement );
	$sth->execute( @values, @$keyval );
    }

    return scalar @fields; # The number of changes
}


############ functions

sub pgbool
{
    return 'f' unless $_[0];
    return 'f' if $_[0] eq 'f';
    return 't';
}

#########################

1;

=head1 SEE ALSO

L<Para::Frame>, L<DBI>

=cut
