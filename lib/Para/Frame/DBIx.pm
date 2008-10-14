#  $Id$  -*-cperl-*-
package Para::Frame::DBIx;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2008 Jonas Liljegren.  All Rights Reserved.
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
use Carp qw( carp croak shortmess longmess confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug timediff package_to_module get_from_fork datadump );
use Para::Frame::Time qw( date );
use Para::Frame::List;
use Para::Frame::DBIx::Table;
use Para::Frame::DBIx::State;


our $STATE_RECONNECTING; # Special temporary dbix state


=head1 DESCRIPTION

C<Para::Frame::DBIx> is an optional module.  It will not be used unless
the application calls it.

The application should initiate the connection and store the object in
a global or site variable.

Multipple connections are supported.

On error, an 'dbi' exception is thrown.

The object will blessed into a subclass via L</rebless>, if availible.

=head2 Exported TT functions

=over

=item L</cached_select_list>

=item L</select_list>

=item L</select_record>

=item L</select_possible_record>

=item L</select_key>

=back

=head1 METHODS

=cut


#######################################################################

=head2 new

  Para::Frame::DBIx->new( \%params )

Param C<connect> can be a string or a ref to a list with up to four
values. Those values will be passed to L<DBI/connect>. Those will be
$data_source, $username, $password and \%attr.

A C<connect> data_source must be given. If username or password is not
given or undef, the DBI default will be used.

If the C<connect> attr is not given the paraframe will use the default
of:
  RaiseError         => 1,
  ShowErrorStatement => 1,
  PrintError         => 0,
  AutoCommit         => 0,

If param C<import_tt_params> is true, the TT select functions will be
globaly exported, connected to this database. Alternatively, you could
export the $dbix object as a TT variable globaly or for a particular
site. That would allow you to access all methods. Only one dbix should
import_tt_params.

The default for C<import_tt_params> is false.

The param C<bind_dbh> can be used to bind the $dbh object (returned by
L<DBI/connect>) to a specific variable, that will be updated after
each connection. Example: C<bind_dbh =E<gt> \ $MyProj::dbh,>

The object uses the hooks L<Para::Frame/on_fork> for reconnecting to
the database on forks.

It uses hook L<Para::Frame/on_error_detect> to retrieve error
information from exceptions and L</rollback> the database.

It uses hook L<Para::Frame/done>, L<Para::Frame/before_switch_req> and
L<Para::Frame/gefore_render_output> for times to L</commit>.

The constructor will not connect to the database, since we will
probably fork after creation. But you may want to, after you have the
object, use L<Para::Frame/on_startup>.

Returns a object that inherits from L<Para::Frame::DBIx>.

Calls C<init> method in the subclass.

Example:

  $MyProj::dbix = Para::Frame::DBIx ->
	new({
	     connect            => ['dbi:Pg:dbname=myproj'],
	     import_tt_params   => 1,
	});
  Para::Frame->add_hook('on_startup', sub
			  {
			      $MyProj::dbix->connect;
			  });

=cut

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
	    pg_enable_utf8 => 1,
	};

	$dbix->{'connect'} = $connect;
    }

    $dbix->rebless;


    if( $params->{'import_tt_params'} )
    {
	debug "Adding global params for dbix $dbix->{connect}[0]";
	Para::Frame->add_global_tt_params({
	    'cached_select_list'       => sub{ $dbix->cached_select_list(@_) },
	    'select_list'              => sub{ $dbix->select_list(@_) },
	    'select_record'            => sub{ $dbix->select_record(@_) },
	    'select_key'               => sub{ $dbix->select_key(@_) },
	    'select_possible_record'   => sub{ $dbix->select_possible_record(@_) },
	});
    }

    $dbix->{'bind_dbh'} = $params->{'bind_dbh'};


    Para::Frame->add_hook('done', sub
			  {
			      $dbix->commit;
			  });

    Para::Frame->add_hook('before_switch_req', sub
			  {
#			      debug 1, sprintf "From %s to %s\n%s", ($Para::Frame::REQ ? $Para::Frame::REQ->id : '-'), ($_[0] ? $_[0]->id : '-'), "";
			      $dbix->commit;
			  });

    # Since the templare may look up things from DB and some things
    # may only be written after on_commit has been triggered.
    #
    Para::Frame->add_hook('before_render_output', sub
			  {
			      $dbix->commit;
			  });

    # I tried to just setting InactiveDestroy. But several processes
    # can't share a dbh. Multiple requests/multiple forks may/will
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

			      if( $dbix->dbh and $dbix->dbh->err() )
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

    $dbix->init( $params );

    return $dbix;
}

#######################################################################

=head2 init

  $dbix->init(\%args);

This may be implemented in subclasses.

The param C<datetime_formatter> should hold the module name to use to
format dates for this database. The default is based on the DB driver.
It's used by L</format_datetime>. The module will be required during
object construction.

C<datetime_formatter> defaults to L<DateTime::Format::Pg> which uses
SQL standard C<ISO 8601> (2003-01-16T23:12:01+0200), which should work
for most databases.

=cut

sub init
{
    my( $dbix, $args ) = @_;

    $args ||= {};

    $dbix->{'datetime_formatter'} =
      $args->{'datetime_formatter'} ||
	'DateTime::Format::Pg';
    my $formatter_module = package_to_module($dbix->{'datetime_formatter'});
    require $formatter_module;


}


#######################################################################

=head2 cached_select_list

See L</select_list>

Stores the result in the session or uses the previously stored result.

=cut

sub cached_select_list
{
    my $dbix = shift;

    my $req = $Para::Frame::REQ;
    if( my $id = $req->q->param('use_cached') )
    {
	return $req->user->session->list($id);
    }

    my $list = $dbix->select_list( @_ );
    $list->store;

    return $list;
}



#######################################################################

=head2 cached_forked_select_list

See L</select_list>

Stores the result in the session or uses the previously stored result.

Does the actual select in a fork.

=cut

sub cached_forked_select_list
{
    my $dbix = shift;

    my $req = $Para::Frame::REQ;
    if( my $id = $req->q->param('use_cached') )
    {
	return $req->user->session->list($id);
    }

    my @data = @_; # Copies before virtual sub
    my $list = Para::Frame::List->new(get_from_fork(sub{$dbix->select_list(@data)}));

    $list->store;

    return $list;
}


#######################################################################

=head2 select_list

  Perl: $dbix->select_list($statement, @vals)
  Tmpl: select_list(statement, val1, val2, ... )

Executes the $statement, substituting all '?' within with the values.

The C<select *> part of the statement can be left out.

Template example:

  [% FOREACH select_list('from user where age > ?', agelimit) %]
     <li>[% name ] is [% age %] years old
  [% END %]

Template example:

  [% FOREACH rec IN select_list('from user where age > ?', agelimit) %]
     <li>[% rec.name ] is [% rec.age %] years old
  [% END %]

Returns:

a L<Para::Frame::List> with the hash records

Exceptions:

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
    } or return $dbix->report_error(\@vals, $st,@vals);
    return Para::Frame::List->new($ref);
}


#######################################################################

=head2 select_record

  Perl: $dbix->select_record($statement, @vals)
  Tmpl: select_record(statement, val1, val2, ... )

Executes the $statement, substituting all '?' within with the values.

The C<select *> part of the statement can be left out.

Template example:

  [% user = select_record('from user where uid = ?', uid) %]
  <p>[% user.name ] is [% user.age %] years old

Returns:

a ref to the first hash record

Exceptions:

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
    } or return $dbix->report_error(\@vals, $st, @vals);
    return $ref;
}

#######################################################################

=head2 select_possible_record

  Perl: $dbix->select_possible_record($statement, @vals)
  Tmpl: select_possible_record(statement, val1, val2, ... )

Executes the $statement, substituting all '?' within with the values.

The C<select *> part of the statement can be left out.

Template example:

  [% user = select_record('from user where uid = ?', uid) %]
  [% IF user %]
     <p>[% user.name ] is [% user.age %] years old
  [% END %]

Returns:

a ref to the first hash record or C<undef> if no record was found

Exceptions:

dbi : DBI returned error

=cut

sub select_possible_record
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
	$sth->execute( $dbix->format_value_list(@vals) );
	$ref =  $sth->fetchrow_hashref;
	$sth->finish;
    } or return $dbix->report_error(\@vals, $st,@vals);
    return $ref;
}


#######################################################################

=head2 select_key

  Perl: $dbix->select_key($field, $statement, @vals)
  Tmpl: select_key(field, statement, val1, val2, ... )

Executes the $statement, substituting all '?' within with the values.
$field should be the primary key or have unique values.

The C<select *> part of the statement can be left out.

Template example:

  [% user = select_key('uid', 'from user') %]
  [% FOREACH id = user.keys %]
     <p>$id: [% user.$id.name ] is [% user.$id.age %] years old
  [% END %]

Returns:

The result is indexed on $field.  The records are returned as a ref to
a indexhash och recordhashes.

Each index will hold the last record those $field holds that value.

Exceptions:

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
    } or return $dbix->report_error(\@vals, $keyf, $st, @vals);
    return $rh;
}


#######################################################################

=head2 delete

  Perl: $dbix->delete($statement, @vals)

Executes the $statement, substituting all '?' within with the values.

Exceptions:

dbi : DBI returned error

=cut

sub delete
{
    my( $dbix, $st, @vals ) = @_;
    #
    # Return list or records

    throw('incomplete','no parameter to statement') unless $st;
    $st = "delete ".$st if $st !~/^\s*delete\s/i;

    eval
    {
	$dbix->dbh->do($st,{},@vals);
    } or return $dbix->report_error(\@vals, $st, @vals);
    return 1;
}

#######################################################################

=head2 connect

  $dbix->connect()

Connects to the database and runs hook L<Para::Frame/after_db_connect>.

The constructor adds ha hook for on_fork that will reconnect to dhe
database in the child.

Returns true or throws an 'dbi' exception.

=cut

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


#######################################################################

=head2 disconnect

  $dbix->disconnect()

Disconnect from the DB

=cut

sub disconnect
{
    my( $dbix ) = @_;

    return $dbix->{'dbh'}->disconnect;
}


#######################################################################

=head2 commit

  $dbix->commit()

Runs the hook L<Para::Frame/before_db_commit>.

Returns the result of L<DBI/commit>

=cut

sub commit
{
    my( $dbix ) = @_;

    Para::Frame->run_hook( $Para::Frame::REQ, 'before_db_commit', $dbix);
    $dbix->dbh->commit;
#    warn "DB comitted\n";
}


#######################################################################

=head2 rollback

  $dbix->rollback()

Starts by doing the rollbak. Then runs the hook
L<Para::Frame/after_db_rollback>.

Calls L<Para::Frame::Change/reset>

Returns the change object

=cut

sub rollback
{
    my( $dbix ) = @_;

    $dbix->dbh->rollback;
    Para::Frame->run_hook( $Para::Frame::REQ, 'after_db_rollback', $dbix);
    if( my $req = $Para::Frame::REQ )
    {
	$req->change->rollback;
    }
    return 1;
}


#######################################################################

=head2 dbh

  $dbix->dbh()

Returns the $dbh object, as returned by L<DBI/connect>.

Example:

  $dbix->dbh->do("update mytable set a=?, b=? where c=?", {}, $a, $b, $c);

=cut

sub dbh { $_[0]->{'dbh'} }


#######################################################################

=head2 get_nextval

  $dbix->get_nextval($seq)

This is done by the SQL query C<"select nextval(?)"> that doesn't work
with mysql. Use L</get_lastval>.

Example:

  my $id = $dbix->get_nextval('person_id_sequence');

Returns:

The id

Exceptions:

dbi : Failed to get nextval

=cut

sub get_nextval
{
    my( $dbix, $seq ) = @_;

    my $sth = $dbix->dbh->prepare( "select nextval(?)" );
    $sth->execute( $seq ) or croak "Faild to get next from $seq\n";
    my( $id ) = $sth->fetchrow_array;
    $sth->finish;

    $id or throw ('sql', "Failed to get nextval\n");
}


#######################################################################

=head2 get_lastval

  $dbix->get_lastval

  $dbix->get_lastval($sequence)

For MySQL, this retrieves the C<AUTOINCREMENT> value from
mysql_insertid that corresponds to mysql_insert_id().

If given a sequence, it retrieves the value with C<"select currval(?)">.

=cut

sub get_lastval
{
    my( $dbix, $seq ) = @_;

    $seq or croak "param sequence not given in get_lastval";

    my $sth = $dbix->dbh->prepare( "select currval(?)" );
    $sth->execute( $seq ) or croak "Faild to get current from $seq\n";
    my( $id ) = $sth->fetchrow_array;
    $sth->finish;
    return $id or throw ('sql', "Failed to get currval\n");
}


#######################################################################

=head2 equals

  $dbix1->equals( $dbix2 )

Returns true is they are the same object.

=cut

sub equals
{
    return $_[0] eq $_[1];
}


#######################################################################

=head2 parse_datetime

  $dbix->parse_datetime( $time, $class )

This uses the C<datetime_formatter> property of $dbix (as set on
construction).

L<$class> defaults to L<Para::Frame::Time>. Can be used to set the
class to a suitable subclass to L<Para::Frame::Time>.

Should be a litle more efficiant than using L<Para::Frame::Time/get>
directly.

Returns: a L<Para::Frame::Time> object

=cut

sub parse_datetime
{
    my( $dbix, $time, $class ) = @_;
    return undef unless $time;

    $class ||= 'Para::Frame::Time';
    my $dt = $dbix->{'datetime_formatter'}->parse_datetime($time);
    return bless $dt, $class;
}


#######################################################################

=head2 format_datetime

  $dbix->format_datetime( $time )

This uses the C<datetime_formatter> property of $dbix (as set on
construction) for returning the time to a format suitable for
the database.

It will parse most formats using L<Para::Frame::Time/get>. Especially
if C<$time> already is a L<Para::Frame::Time> object.

Returns:

The formatted string

Exceptions:

validation : "Time format '$time' not recognized"

=cut

sub format_datetime
{
    my( $dbix, $time ) = @_;
    return undef unless $time;
    return $dbix->{'datetime_formatter'}->
	format_datetime(Para::Frame::Time->get( $time ));
}


#######################################################################

=head2 update

  $dbix->update( $table, \%set, \%where )

C<$table> is the name of the table as a string

C<\%set> is a hashref of key/value pairs where the C<key> is the field
name and C<value> is the new value of the field. The value will be
formatted by L</format_value> with type C<undef>.

C<\%where> is a hashref of key/value pars where the C<key> is the
field name and C<value> is the value that field should have.

Returns: The number of rows updated

Exceptions:

dbi : ... full explanation ...

Example:

  $dbix->update( 'my_users', { email => $new_email }, { user_id => $u->id })

=cut

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
    my $wherestr = join " and ", map "$_=?", @where_fields;
    my $st = "update $table set $setstr where $wherestr";
    my $sth;

    eval
    {
	$sth = $dbix->dbh->prepare($st);
	$sth->execute( @values );
	debug "SQL: $st\nValues: ".join ", ",map defined($_)?"'$_'":'<undef>', @values;
	$sth->finish;
	die "Nothing updated" unless $sth->rows;
    } or return $dbix->report_error(\@values, $table, $set, $where);
    return $sth->rows;
}


#######################################################################

=head2 insert

  $dbix->insert( $table, \%rec )
  $dbix->insert( \%params )

Insert a row in a table in $dbix

  Params are:
  table = name of table
  rec   = hashref of field/value pairs
  types = definition of field types

The values will be automaticly formatted for the database. types, if
existing, helps in this formatting. L</format_value> is used for this.

Returns number of rows inserted.

Example:

  $dbix->insert({
	table => 'person',
	rec   =>
        {
          id      => 12,
          name    => 'Gandalf'
          updated => now(),
        },
	types =>
        {
          id      => 'string',
          name    => 'string',
          updated => 'boolean',
        },
  });

Exceptions:

dbi : ... full explanation ...

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
    } or return $dbix->report_error(\@values, $table, $rec);
    return $sth->rows;
}


#######################################################################

=head2 insert_wrapper

  $dbix->insert_wrapper( \%params )

High level for adding a record.

  Params are:
  rec    = hashref of name/value pairs for fields to update
  map    = hashref of translation map for interface to fieldname
  parser = hashref of fieldname/coderef for parsing values
  types  = hashref of fieldname/type
  table  = name of table
  unless_exists = listref of fields to check before inserting
  return_field  = what field value to return

Example:

  our %FIELDMAP =
  (
    id   => 'pid',                 # The DB field is named pid
    name => 'username',            # The DB field is named username
  );

  our %FIELDTYPES =
  (
    updated => 'date',             # Parse this as an date and format
  );

  our %FIELDPARSER =               # The coderef returns the object
  (                                # and the object has a id() method
    project => sub{ MyProj::Project->get(shift) },
  );

  ...

  my $rec =
  {
    id      => 12,
    name    => 'Gandalf',
    updated => now(),              # From Para::Frame::Time
    project => 'Destroy the Ring', # The db field holds the project id
  };
  my $newperson = MyProj::Person->insert($rec);

  ...

  sub insert
  {
    my( $class, $rec ) = @_;
    return MyProj::Person->get_by_id(
	       $Para::dbix->insert_wrapper({
	           rec    => $rec,
		   map    => \%FIELDMAP,
		   types  => \%FIELDTYPE,
                   parser => \%FIELDPARSER,
		   table  => 'person',
		   unless_exists => ['name'], # Avoid duplicates
		   return_field => 'id',      # used by get_by_id()
	       }));
  }

C<rec> is the field/value pairs. Each field name may be translated by
C<map>. Defaults to an empty record.

C<map> is used for the case there the name of the object property
doesn't match the DB field name. We may want use opne naming scheme
for field names and another naming scheme for object properties. One
or the other may change over time.

C<parser> is used for special translation of the given value to the
value that should be inserted in the database.  One good usage for
this is for foreign keys there the field holds the key of a record in
another table. The parser should return the related object. The
L</format_value> method will be used to get the actual C<id> by
calling the objects method C<id>.

C<types> helps L</format_value>.

C<table> is the name of the table. This is the only param that must be
given.

C<unless_exists> is a field name or a ref to a list of field names. If
a record is found with those fields having the values from the
C<$rec>, no new record will be created.

C<return_field> will return the value of this field if defined. If
C<unless_exists> find an existing record, the value of thats records
field will be returned. May be used as in the example, for returning
the id.

Returns the number of records inserted, unless C<return_field> is
used. If C<unless_exists> finds an existing record, the number of
records inserted is 0.

The usage of %FIELDTYPES, et al, in the example, demonstrates how each
table should have each own Perl class set up in its own file as a
module. The fields could be defined globaly for the class and used in
each method dealing with the DB.

Validation of the data has not yet been integrated...

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


#######################################################################

=head2 update_wrapper

  $dbix->update_wrapper( \%params )

High level for updating a record. This will compare two records to
detect if anything has changed.

  Params are:
  rec_new = hashref of name/value pairs for fields to update
  rec_old = hashref of the record to be updated
  map     = hashref of translation map for interface to fieldname
  parser  = hashref of fieldname/coderef for parsing values
  types   = hashref of fieldname/type
  table   = name of table
  key     = hashref of field/value pairs to use as the record key
  on_update = hashref of field/value pairs to be set on update
  copy_data = obj to be updated with formatted values if any change

This is similar to L</insert_wrapper> but most of the job is done by
L</save_record>.

Returns the number of fields changed.

C<copy_data> will take each field from the translated fields from
$rec_new and their corresponding formatted value, and place them in
the given object or hashref.  The point is to update the object with
the given changes.

Example:

  my $changes = $dbix->update_wrapper({
    rec_new         => $rec,
    rec_old         => $me->get( $person->id ),
    types           => \%FIELDTYPE,
    table           => 'person',
    key =>
    {
        id => $person->id,
    },
    on_update =>
    {
        updated => now(),
    },
    fields_to_check => [values %FIELDMAP],
    map             => \%FIELDMAP,
    copy_data       => $person,
    });

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


#######################################################################

=head2 format_value_list

  $dbix->format_value_list(@value_list)

Returns a list of formatted values

Plain scalars are not modified

DateTime objects are formatted

Objects with an id method uses the id

Other objects are stringyfied.

=cut

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


#######################################################################

=head2 format_value

  $dbix->format_value( $type, $value )

  $dbix->format_value( undef, $value )

If type is undef, uses L</format_value_list>.

Returns the formatted value

Handled types are C<string>, C<boolean> and C<date>.

Exceptions:

validation : Type $type not handled

validation : Value $valstr not a $type

=cut

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
	    return $dbix->bool( $val );
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

	return $dbix->format_value_list( $val );
    }
}


#######################################################################

=head2 save_record

  $dbix->save_record( \%params )

High level for saving a record.

  Params are:
  rec_new = hashref of name/value pairs for fields to update
  rec_old = hashref of the record to be updated
  table   = name of table
  on_update = hashref of field/value pairs to be set on update
  key     = hashref of field/value pairs to use as the record key
  keyval  = alternative to give all in key param
  fields_to_check = which fields to check

Returns the number of changes.

If any changes are made, determined by formatting the values and
comparing rec_new with rec_old, those fields are updated for the
record in the table.

The types handled are C<string>, C<integer>, C<float>, C<boolean>,
C<date> and C<email>.

Exceptions:

action : Type $type not recoginzed

=cut

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
	    if( $dbix->bool($new) ne $dbix->bool($old) )
	    {
		$fields_added{ $field } ++;
		push @fields, $field;
		push @values, $dbix->bool( $new );
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
	} or return $dbix->report_error([@values, @$keyval], $param);
    }

    return scalar @fields; # The number of changes
}


#######################################################################

=head2 report_error

  $dbix->report_error( \@values, @params )

If $@ is true, throws a C<dbi> exception, adding the calles sub name
and the list of values. Those should be the values given to dbh for
the SQL query.

If the connection may have been lost, tries to reestablish it and
recalls the method with statement and values.

=cut

sub report_error
{
    my( $dbix, $valref ) = (shift, shift);
    if( $@ )
    {
	my( $subroutine ) = (caller(1))[3];
	$subroutine =~ s/.*:://;

	my $state = $dbix->state;

	debug(0,"DBIx $subroutine error");
	$@ =~ s/ at \/.*//;
	my $error = catch($@);
	my $info = $error->info;
	chomp $info;

	my $state_desc = $state->desc;

	debug "Error number: $DBI::err";
	debug "Status: $DBI::state";

	# Should be redundant, but may not be
	if( $DBI::state eq '26000' )
	{
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
	}


	unless( $STATE_RECONNECTING or $dbix->dbh->ping )
	{
	    $STATE_RECONNECTING = 1;
	    debug "Ping failed. Should reconnect";
	    debug "Called from $subroutine";

	    debug "Reconnecting to DB";
	    eval
	    {
		$dbix->connect;
	    } or do
	    {
		debug "Still no connection!";
		debug "I'll try to restart the server";
		Para::Frame->do_hup;
		die $@;
	    };

	    if( @_ )
	    {
		debug "REPEATING COMMAND \$dbix->$subroutine(@_)";
		my $res = $dbix->$subroutine(@_);
		$STATE_RECONNECTING = 0;
		return $res;
	    }
	}

	my $msg = "$state_desc\n$info\n";
	if( @$valref )
	{
	    my $values = join ", ",map defined($_)?"'$_'":'<undef>', @$valref;
	    $msg .= "Values: $values\n";
	}
	$msg .= "...".longmess();
	throw('dbi', $msg);
    }
}


#######################################################################

=head2 rebless

  $dbix->rebless

Checks if there exists a Para::Frame::DBIx::... module matching the
connection, for customized interface.

=cut

sub rebless
{
    my( $scheme, $driver ) = DBI->parse_dsn($_[0]->{connect}[0]);

    $scheme or confess "Invalid connect string: $_[0]->{connect}[0]";

    my $package = "Para::Frame::DBIx::$driver";
    my $module = package_to_module($package);
    debug "DBIx uses package $package";

    if( eval{ require $module } )
    {
	debug "Reblessing dbix into $package";
	bless $_[0], $package;
    }

    return $_[0];
}


#######################################################################

=head2 table

  $dbix->table( $name )

Returns: a L<Para::Frame::DBIx::Table> object or C<undef> if not
existing.

Must be implemented for the DB driver.

=cut

sub table
{
    die "method table() not implemented";
}


#######################################################################

=head2 tables

  $dbix->tables()

Returns: A L<Para::Frame::List> object of L<Para::Frame::DBIx::Table>
objects.

Must be implemented for the DB driver.

=cut

sub tables
{
    die "method table() not implemented";
}


#######################################################################

=head2 bool

  $dbix->bool($value)

Returns: a boolean true/false value fore use in SQL statements for the
DB.

=cut

sub bool
{
    die "bool not implemented";
}



#######################################################################

=head2 state

  $dbix->state

Returns: a L<Para::Frame::DBIx::State> object representing the current state.

=cut

sub state
{
    return Para::Frame::DBIx::State->new($_[0]);
}


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<DBI>

=cut
