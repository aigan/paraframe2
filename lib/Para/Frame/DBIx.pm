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
use Carp qw( carp croak shortmess );
use Data::Dumper;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug timediff package_to_module );
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
    my( $dbix, $st, @vals ) = @_;
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
	my $sth = $dbix->dbh->prepare( $st );
	$sth->execute($dbix->format_value_list(@vals));
	$ref =  $sth->fetchall_arrayref({});
	$sth->finish;
    };
    report_error("Select list",\@vals);
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
    my( $dbix, $st, @vals ) = @_;
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
	my $sth = $dbix->dbh->prepare( $st );
	$sth->execute( $dbix->format_value_list(@vals) ) or croak "$st (@vals)\n";
	$ref =  $sth->fetchrow_hashref
	    or die "Found ".$sth->rows()." rows\nSQL: $st";
	$sth->finish;
    };
    report_error("Select record",\@vals);
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
    my( $dbix, $statement, @vals ) = @_;
    #
    # Return list or records

    if( ref $vals[0] eq 'ARRAY' )
    {
	@vals = @{$vals[0]};
    }

    my $ref;
    throw('incomplete','no parameter to statement') unless $statement;
    $statement = "select * ".$statement if $statement !~/^\s*select\s/i;

    eval
    {
	my $sth = $dbix->dbh->prepare( $statement );
	$sth->execute( $dbix->format_value_list(@vals) );
	$ref =  $sth->fetchrow_hashref;
	$sth->finish;
    };
    report_error("Select possible record",\@vals);
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
    my( $dbix, $keyf, $st, @vals ) = @_;
    #
    # Return ref to hash of records

    if( ref $vals[0] eq 'ARRAY' )
    {
	@vals = @{$vals[0]};
    }

    $st = "select * ".$st if $st !~/^\s*select\s/i;
    my $rh = {};

    eval
    {
	my $sth = $dbix->dbh->prepare( $st );
	$sth->execute( $dbix->format_value_list(@vals) );
	while( my $r = $sth->fetchrow_hashref )
	{
	    $rh->{$r->{$keyf}} = $r;
	}
	$sth->finish;
    };
    report_error("Select key",\@vals);
    return $rh;
}


sub new
{
    my( $class, $params ) = @_;

    $params ||= {};

    my $dbix = bless {}, $class;

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

    if( $params->{'import_tt_params'} )
    {
	debug "Adding global params for dbix $dbix->{connect}[0]";
	Para::Frame->add_global_tt_params({
	    'select_list'              => sub{ $dbix->select_list(@_) },
	    'select_record'            => sub{ $dbix->select_record(@_) },
	    'select_key'               => sub{ $dbix->select_key(@_) },
	    'select_possible_record'   => sub{ $dbix->select_possible_record(@_) },
	});
    }

    $dbix->{'bind_dbh'} = $params->{'bind_dbh'};


    $dbix->{'datetime_formatter'} =
	$params->{'datetime_formatter'} ||
	'DateTime::Format::Pg';
    my $formatter_module = package_to_module($dbix->{'datetime_formatter'});
    require $formatter_module;

   

    Para::Frame->add_hook('done', sub
			  {
			      $dbix->commit;
			  });

    Para::Frame->add_hook('before_switch_req', sub
			  {
			      $dbix->commit;
			  });

    Para::Frame->add_hook('before_render_output', sub
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
			      debug(2,"Do not destroy DBH in child");
			      $dbix->dbh->{'InactiveDestroy'} = 1;
			      $dbix->connect();
			  });

    Para::Frame->add_hook('on_error_detect', sub
			  {
			      my( $typeref, $inforef ) = @_;

			      if( $Para::Frame::FORK )
			      {
				  debug "In DBIx error hook during FORK\n";
				  return;
			      }

			      $typeref ||= \ "";
				      
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
	debug(2,"Connected to DB $connect->[0]");
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
    my( $dbix, $seq ) = @_;

    my $sth = $dbix->dbh->prepare( "select nextval(?)" );
    $sth->execute( $seq ) or croak "Faild to get next from $seq\n";
    my( $id ) = $sth->fetchrow_array;
    $sth->finish;

    $id or throw ('sql', "Failed to get nextval\n");
}

sub equals
{
    return $_[0] eq $_[1];
}

sub format_datetime
{
    my( $dbix, $time ) = @_;
    return undef unless $time;
    $time = Para::Frame::Time->get( $time );
    return $dbix->{'datetime_formatter'}->format_datetime($time);
}

sub update
{
    my( $dbix, $table, $set, $where ) = @_;

    die "expected hashref" unless ref $set and ref $where;

    my( @set_fields, @where_fields, @values );

    foreach my $key ( keys %$set )
    {
	push @set_fields, $key;
	push @values, $dbix->format_value( undef, $set->{$key} );
    }

    foreach my $key ( keys %$where )
    {
	push @where_fields, $key;
	push @values, $dbix->format_value( undef, $where->{$key} );
    }

    my $setstr   = join ",", map "$_=?", @set_fields;
    my $wherestr = join ",", map "$_=?", @where_fields;
    my $st = "update $table set $setstr where $wherestr";
    my $sth;

    eval
    {
	$sth = $dbix->dbh->prepare($st);
	$sth->execute( @values );
	debug "SQL: $st\nValues: ".join ", ",map defined($_)?"'$_'":'<undef>', @values;
	$sth->finish;
	die "Nothing updated" unless $sth->rows;
    };
    report_error("Update",\@values);
    return $sth->rows;
}

=head2 insert

  $dbix->insert( $table, \%rec )
  $dbix->insert( \%params )

Insert a row in a table in $dbix

Params are:
  table = name of table
  rec   = hashref of field/value pairs
  types = definition of field types

The values will be automaticly formatted for the database. types, if
existing, helps in this formatting.

Returns numer of rows inserted

=cut

sub insert
{
    my( $dbix, $table, $rec ) = @_;

    my $types;

    unless($rec)
    {
	my $p = $table;

	$table = $p->{'table'};
	$rec   = $p->{'rec'};
	$types = $p->{'types'};
    }

    $types ||= {};

    die "expected hashref" unless ref $rec;

    my( @fields, @places, @values );

    foreach my $key ( keys %$rec )
    {
	push @fields, $key;
	push @places, '?';
	push @values, $dbix->format_value( $types->{$key}, $rec->{$key} );
    }

    my $fieldstr = join ",", @fields;
    my $placestr = join ",", @places;
    my $st = "insert into $table ($fieldstr) values ($placestr)";
    my $sth;

    eval
    {
	$sth = $dbix->dbh->prepare($st);
	$sth->execute( @values );
	$sth->finish;
    };
    report_error("Insert",\@values);
    return $sth->rows;
}

=head2 insert_wrapper

High level for adding a record

=cut

sub insert_wrapper
{
    my( $dbix, $params ) = @_;

    my $rec_in  = $params->{'rec'} || {};
    my $map     = $params->{'map'} || {};
    my $parser  = $params->{'parser'} || {};
    my $types   = $params->{'types'} || {};
    my $table   = $params->{'table'} or croak "table missing";
    my $uexists = $params->{'unless_exists'};
    my $rfield  = $params->{'return_field'};

    $rfield = $map->{$rfield} || $rfield;
    
    my $rec = {};
    foreach my $key ( keys %$rec_in )
    {
	my $field = $map->{$key} || $key;
	my $value = $rec_in->{$key};
	if( my $parser = $parser->{ $field } )
	{
	    debug "Value for $field is $value";
	    $value = &$parser( $value );
	}
	if( my $type = $types->{$field} )
	{
#	    unless( validate($value, $type) )
#	    {
#		throw 'validation', "Param $param doesn't match $type";
#	    }
	}

	# Be careful of multiple settings due to mapping

	$rec->{$field} = $value;
    }

    if( $uexists )
    {
	my( @fields, @values );
	$uexists = [$uexists] unless ref $uexists;
	foreach my $key (@$uexists)
	{
	    my $field = $map->{$key} || $key;
	    push @fields, $field;
	    push @values, $rec->{$field};
	}
	my $where_str = join " and ",map "$_=?",@fields;
	my $st = "from $table where $where_str";
	if( my $orec = $dbix->select_possible_record($st,@values) )
	{
	    if( $rfield )
	    {
		debug 3, "Returning field $rfield: $orec->{$rfield}";
		return $orec->{$rfield};
	    }
	    return 0;
	}
    }

    $dbix->insert({
	table => $table,
	rec   => $rec,
	types => $types,
    });

    if( $rfield )
    {
	debug 3, "Returning field $rfield: $rec->{$rfield}";
	return $rec->{$rfield};
    }
    return 1;
}



=head2 update_wrapper

High level for updating a record

=cut

sub update_wrapper
{
    my( $dbix, $params ) = @_;

    my $rec_in    =
	$params->{'rec'} ||
	$params->{'rec_new'} or croak "rec_new missing";
    my $rec_old   =
	$params->{'rec_old'} or croak "rec_old missing";
    my $map       = $params->{'map'} || {};
    my $parser    = $params->{'parser'} || {};
    my $types     = $params->{'types'} || {};
    my $table     = $params->{'table'} or croak "table missing";
    my $key       = $params->{'key'} or croak "key missing";
    my $on_update = $params->{'on_update'};
    my $copy_data = $params->{'copy_data'};
    
    my $rec_new = {};
    foreach my $key ( keys %$rec_in )
    {
	my $field = $map->{$key} || $key;
	my $value = $rec_in->{$key};
	if( my $parser = $parser->{ $field } )
	{
	    debug "Value for $field is $value";
	    $value = &$parser( $value );
	}
	if( my $type = $types->{$field} )
	{
#	    unless( validate($value, $type) )
#	    {
#		throw 'validation', "Param $param doesn't match $type";
#	    }
	}

	# Be careful of multiple settings due to mapping

	$rec_new->{$field} = $value;
    }

    my $res = $dbix->save_record({
	rec_new => $rec_new,
	rec_old => $rec_old,
	table => $table,
	key => $key,
	types => $types,
	on_update => $on_update,
    });

    if( $res and $copy_data )
    {
	foreach my $field ( keys %$rec_new )
	{
	    $copy_data->{$field} = $rec_new->{$field};
	    debug 4, "Setting $field to $rec_new->{$field}";
	}
    }

    return $res;
}



sub format_value_list
{
    my( $dbix ) = shift;

    my @res;
    foreach(@_)
    {
	debug 4, "Formatting ".(defined($_)?$_:'<undef>');
	if( not ref $_ )
	{
	    push @res, $_;
	}
	elsif( $_->isa('DateTime') )
	{
	    push @res, $dbix->format_datetime( $_ );
	}
	elsif( $_->can('id') )
	{
	    push @res, $_->id;
	}
	else
	{
	    push @res, "$_"; # Stringify
	}
    }
    return @res;
}


sub format_value
{
    my( $dbix, $type, $val ) = @_;

    my $valstr = defined $val?$val:'<undef>';

    if( $type )
    {
	debug 2, "Formatting $type $valstr";

	if( $type eq 'string' )
	{
	    if( not ref $val )
	    {
		return $val;
	    }
	}
	elsif( $type eq 'boolean' )
	{
	    return pgbool( $val );
	}
	elsif( $type eq 'date' )
	{
	    return $dbix->format_datetime( $val );
	}
	else
	{
	    throw 'validation', "Type $type not handled";
	}
	throw 'validation', "Value $valstr not a $type";
    }
    else
    {
	debug 3, "Formatting $valstr";

	if( not ref $val )
	{
	    return $val;
	}
	elsif( $val->isa('DateTime') )
	{
	    return $dbix->format_datetime( $val );
	}
	elsif( $val->can('id') )
	{
	    return $val->id;
	}
	else
	{
	    debug "Trying to stringify $valstr";
	    return "$val"; # Stringify
	}
    }
}


sub save_record
{
    my( $dbix, $param ) = @_;

    my $rec_new = $param->{'rec_new'} or croak "rec_new missing";
    my $types = $param->{'types'} || {};
    my $rec_old = $param->{'rec_old'} or croak "rec_old missing";
    my $table = $param->{'table'} or croak "table missing";
    my $key = $param->{'key'} || $table;
    my $keyval = $param->{'keyval'};
    my $fields_to_check = $param->{'fields_to_check'} || [keys %$rec_new];
    my $on_update = $param->{'on_update'} || undef;

    my $req = $Para::Frame::REQ;

    if( ref $key eq 'HASH' )
    {
	my $keyhash = $key;
	$key = [];
	$keyval = [];
	foreach my $f ( keys %$keyhash )
	{
	    push @$key, $f;
	    push @$keyval, $keyhash->{$f};
	}
    }
    else
    {
	$keyval or croak "keyval missing";

	$key = [$key] unless ref $key;
	$keyval = [$keyval] unless ref $keyval;
    }

    my( @fields, @values );
    my %fields_added;

    foreach my $field ( @$fields_to_check )
    {
	my $type = $types->{$field} || 'string';
	my $new = $rec_new->{ $field };
	my $old = $rec_old->{ $field };
	next if not $new and not $old;

	debug(3, "Checking field $field ($type)");

	if( $type eq 'string' )
	{
#	    my $new = $dbix->format_value( undef, $rec_new->{ $field } );
#	    my $old = $dbix->format_value( undef, $rec_old->{ $field } );

	    if( (defined $new and not defined $old) or
		(defined $old and not defined $new) or
		( $new ne $old ) )
	    {
		$fields_added{ $field } ++;
		push @fields, $field;
		push @values, $new;
		$new = '<undef>' unless defined $new;
		$old = '<undef>' unless defined $old;
		debug(1,"  field $field differ: '$new' != '$old'");
	    }
	}
	elsif( $type eq 'integer' )
	{
	    # We can usually use type string for integers
	    $new = int($new) if $new;

	    if( (defined $new and not defined $old) or
		(defined $old and not defined $new) or
		( $new != $old )
		)
	    {
		$fields_added{ $field } ++;
		push @fields, $field;
		push @values, $new;
		$new = '<undef>' unless defined $new;
		$old = '<undef>' unless defined $old;
		debug(1,"  field $field differ: '$new' != '$old'");
	    }
	}
	elsif( $type eq 'float' )
	{
	    # We can usually use type string for floats

	    if( (defined $new and not defined $old) or
		(defined $old and not defined $new) or
		( $new != $old ) )
	    {
		$fields_added{ $field } ++;
		push @fields, $field;
		push @values, + $new;
		debug(1,"  field $field differ");
	    }
	}
	elsif( $type eq 'boolean' )
	{
	    if( pgbool($new) ne pgbool($old) )
	    {
		$fields_added{ $field } ++;
		push @fields, $field;
		push @values, pgbool( $new );
		$new = '<undef>' unless defined $new;
		$old = '<undef>' unless defined $old;
		debug(1,"  field $field differ: '$new' != '$old'");
	    }
	}
	elsif( $type eq 'date' )
	{
	    $new = date( $new ) if $new;
	    $old = date( $old ) if $old;
	    
	    if( (defined $new and not defined $old) or
		(defined $old and not defined $new) or
		( not $new->equals( $old ) )
		)
	    {
		$fields_added{ $field } ++;
		my $val = $dbix->format_datetime( $rec_new->{ $field } );
		push @fields, $field;
		push @values, $val;
		debug(1,"  field $field differ. New is $val");
	    }
	}
	elsif( $type eq 'email' )
	{
	    eval
	    {
		$new ||= '';
		if( $new and not ref $new )
		{
		    $new = Para::Frame::Email::Address->parse( $new );
		}
		
		$old ||= '';
		if( $old and not ref $old )
		{
		    $old = Para::Frame::Email::Address->parse( $old );
		}
		
		if( $new ne $old )
		{
		    $fields_added{ $field } ++;
		    push @fields, $field;
		    push @values, $new->as_string;
		    debug(1,"  field $field differ");
		}
	    };
	    if( $@ )
	    {
		if( $req->is_from_client )
		{
		    die $@;
		}
		else
		{
		    debug $@;
		}
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
		my $type = $types->{$field};
		my $value = $dbix->format_value($type, $on_update->{$field});
		push @fields, $field;
		push @values, $value;
	    }
	}

	my $where = join ' and ', map "$_=?", @$key;

	my $statement = "update $table set ".
	    join( ', ', map("$_=?", @fields)) .
	    " where $where";
	debug(4,"Executing statement $statement");
	eval
	{
	    my $sth = $dbix->dbh->prepare( $statement );
	    $sth->execute( @values, @$keyval );
	};
	report_error("Save record",[@values,@$keyval]);
    }

    return scalar @fields; # The number of changes
}


############ functions

# TODO: Replace pgbool with dbbool, dependant on the db used

sub report_error
{
    my( $title, $vals ) = @_;
    if( $@ )
    {
	debug(0,"DBIx $title error");
	$@ =~ s/ at \/.*//;
	my $error = catch($@);
	my $info = $error->info;
	chomp $info;
	my $at = "...".shortmess();
	my $values = join ", ",map defined($_)?"'$_'":'<undef>', @$vals;
	throw('dbi', "$info\nValues: $values\n$at");
    }
}

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
