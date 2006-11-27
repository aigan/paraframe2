#  $Id$  -*-cperl-*-
package Para::Frame::List;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework List class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::List - Methods for list manipulation

=cut

use strict;
use Carp qw( carp croak shortmess confess cluck );
use Data::Dumper;
use List::Util;
use Template::Constants;
use Scalar::Util;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug timediff datadump );
use Para::Frame::Widget qw( forward );

use overload
  '@{}' => 'as_arrayref_by_overload',
  'bool' => sub{carp "* Bool"; $_[0]->size},
  '""' => 'stringify_by_overload',
  '.' => 'concatenate_by_overload',
#  '.' => sub{$_[0]}, # No change!
#  '.=' => sub{$_[0]}, # No change!
  'fallback' => 0;

use base qw( Template::Iterator );

=head2 DESCRIPTION

The object is overloaded to be used as a ref to the list it
contains. All list operations can be used as usual. Example:

  my $l = Para::Frame::List->new( \@biglist );
  my $first_element = $l->[0];
  my $last_element = pop @$l;

The iteration methods is compatible with (and inherits from)
L<Template::Iterator>. (The iterator status codes are taken from
L<Template::Constants>.)

=head2 BACKGROUND

Since L<Para::Frame> is built for use with L<Template>, it implements
the L<Template::Iterator> class.

But this class is extanded to provide more useful things. Primarely:

 * Iteration
 * Initialize list elements on demand
 * Split list into pages
 * Access metadata about the list
 * Modify the list

There are a large amount of diffrent implementation of iterators and
List classes.  I will try to keep the method names clear and mention
choises from other modules.

This module is subclassable.

We should implement all methods in a way that allow subclasses to only
initiate and hold the specified used parts in memory, maby by using
tie.


TODO: Implement the rest of the array modification methods()

TODO: Use a tied array var for overload, in order to update metadata
on change.


Subclasses that don't want to load the whole list in memory should
implement:

  max()
  size()
  get_next_raw()
  get_prev_raw()

Subclasses that want to construct the list on demand should implement:

  populate_all()

=cut

#######################################################################

=head2 new

  $l = $class->new( \@list )

  $l = $class->new( \@list, \%params )

Availible params are:

  page_size      (default is 20 )
  display_pages  (default is 10 )

Compatible with L<Template::Iterator/new>.

Returns:

A an object blessed in C<$class>

=cut

sub new
{
    my( $this, $data_in, $args ) = @_;
    my $class = ref($this) || $this;

    if( $data_in and UNIVERSAL::isa($data_in, "Para::Frame::List") )
    {
	return $data_in;
    }

#    carp "New search list WITH ".datadump($data_in);

    my $data;
    $args ||= {};
    my $l = bless
    {
     'INDEX'         => -1,    # Before first element
     'materialized'  => 0,     # 1 for partly and 2 for fully materialized
     'materializer'  => undef,
     '_DATA'         => undef,
     'populated'     => 0,     # 1 for partly and 2 for fully populated
     '_OBJ'          => undef, # the corresponding list of materalized elements
     'limit'         => 0,
     'page_size'     => ($args->{'page_size'} || 20 ),
     'display_pages' => ($args->{'display_pages'} || 10),
     'stored_id'     => undef,
     'stored_time'   => undef,
    }, $class;

    if( $data_in )
    {
	# Removes other things like overload
	if( ref $data_in eq 'ARRAY' )
	{
	    $data = $data_in;
	}
	else
	{
	    unless( UNIVERSAL::isa($data_in, "ARRAY") )
	    {
		my $type = ref $data_in;
		die "$type is not an array ref";
	    }

	    $data = [@$data_in];
	}
#	debug "Placing DATA in listobj ".datadump($data);


	$l->{'_DATA'} = $data;
    }

    $l->init( $args );

    if( my $mat_in =  $args->{'materializer'} )
    {
	# After the init
	$l->set_materializer( $mat_in );
    }

    if( $l->{'_DATA'} )
    {
	# After the init
	$l->on_populate_all;
    }

    return $l;
}


#######################################################################

=head2 new_empty

=cut

sub new_empty
{
    my( $this ) = @_;
    my $class = ref($this) || $this;

    my $l = bless
    {
     'INDEX'         => -1,    # Before first element
     'materialized'  => 2,     # 1 for partly and 2 for fully materialized
     'materializer'  => undef,
     '_DATA'         => [],
     'populated'     => 2,     # 1 for partly and 2 for fully populated
     '_OBJ'          => [], # the corresponding list of materalized elements
     'limit'         => 0,
     'page_size'     => 0,
     'display_pages' => 0,
     'stored_id'     => undef,
     'stored_time'   => undef,
    }, $class;

    return $l;
}


#######################################################################

=head2 init

  $l->init

Called by L</new> for additional initializing. Subclasses can use this
for filling the list with data or adding more properties.

=cut

sub init
{
    # Reimplement this
}


#######################################################################

=head2 set_materializer

=cut

sub set_materializer
{
    my( $l, $mat_in ) = @_;

    $l->{'materializer'} = $mat_in;

    $l->{'_OBJ'} = [];

    return $l->{'materializer'};
}


#######################################################################

=head2 as_arrayref

  $l->as_arrayref()

See also L</get_all> and L</as_list>.  Most other modules misses a
comparable method.

This method is used by the array dereferencing overload.

Returns:

A ref to the internal list of elements returned by
L</materialize_all>.

=cut

sub as_arrayref
{
    unless( $_[0]->{'materialized'} > 1 )
    {
	return $_[0]->materialize_all;
    }
    return $_[0]->{'_OBJ'};
}

sub as_arrayref_by_overload
{
    unless( UNIVERSAL::isa($_[0],'HASH') ) ### DEBUG
    {
	confess "Wrong type ".datadump($_[0]);
    }

    unless( $_[0]->{'materialized'} > 1 )
    {
	return $_[0]->materialize_all;
    }
    carp "* OVERLOAD arrayref for list obj used";
    return $_[0]->{'_OBJ'};
}


#######################################################################

=head2 concatenate

implemented concatenate_by_overload()

=cut

sub concatenate_by_overload
{
    my( $l, $str, $is_rev ) = @_;
    carp "* OVERLOAD concatenate for list obj used";

    my $lstr = $l->stringify_by_overload();
    if( $is_rev )
    {
	return $str.$lstr;
    }
    else
    {
	return $lstr.$str;
    }
}

#######################################################################

=head2 stringify

stringify_by_overload() method defined

=cut

sub stringify_by_overload
{
    return ref($_[0])."=".Scalar::Util::refaddr($_[0]);
}

#######################################################################

=head2 as_raw_arrayref

  $l->as_arrayref()

Returns the internal arrayref to the unmaterialized elements.

=cut

sub as_raw_arrayref
{
    unless( $_[0]->{'populated'} > 1 )
    {
	return $_[0]->populate_all;
    }
    return $_[0]->{'_DATA'};
}



#######################################################################

=head2 as_list

  $l->as_list()

Compatible with L<Template::Iterator>.

See also L</get_all> and L</elements>.

Returns:

Returns:

A ref to the internal list of elements returned by
L</materialize_all>.

=cut

sub as_list
{
    unless( $_[0]->{'materialized'} > 1 )
    {
	return $_[0]->materialize_all;
    }
    return $_[0]->{'_OBJ'};
}


#######################################################################

=head2 as_array

  $l->as_array()

Similar to L<List::Object/array> and L<IO::Handle/getlines>. See also
L</get_all> and L</as_list>.

Returns:

The list as a list. (Not a ref) (And not realy an array either...)

=cut

sub as_array
{
    unless( $_[0]->{'materialized'} > 1 )
    {
	return $_[0]->materialize_all;
    }
    return @{$_[0]->{'_OBJ'}};
}


#######################################################################

=head2 as_raw_array

  $l->as_raw_array()

Returns the unmaterialized list as a list of elements (not ref).

=cut

sub as_raw_array
{
    unless( $_[0]->{'populated'} > 1 )
    {
	return $_[0]->populate_all;
    }
    return @{$_[0]->{'_DATA'}};
}


#######################################################################

=head2 populate_all

  $l->populate_all()

Reimplement this if the content should be set on demand in a subclass.

Returns:

The raw data listref of unmateralized elements.

=cut

sub populate_all
{
    unless( $_[0]->{'populated'} > 1 )
    {
	$_[0]->{'_DATA'} = [];
	$_[0]->on_populate_all;
    }

    return $_[0]->{'_DATA'};
}

#######################################################################

=head2 on_populate_all

  $l->on_populate_all()

=cut

sub on_populate_all
{
    my( $l ) = @_;

    $l->{'_DATA'} ||= [];  # Should have been defined
    $l->{'populated'} = 2; # Mark as fully populated

    if( my $lim = $l->{'limit'} )
    {
	if( $lim > scalar(@{$l->{'_DATA'}}) )
	{
	    splice @{$l->{'_DATA'}}, 0, $lim;
	}
    }

    unless( $l->{'materializer'} )
    {
#	debug "**** OBJ=DATA for ".datadump($l); ### DEBUG
	$l->{'materialized'} = 2;
	return $l->{'_OBJ'} = $l->{'_DATA'} ||= []; # Should have been defined
    }
    return  $l->{'_DATA'};
}

#######################################################################

=head2 materialize_all

  $l->materialize_all()

If L</materializer> is set, calls it for each unmaterialized element
and returns a ref to an array of the materialized elements

In no materialization is needed, just returns the existing data as an
array ref.

=cut

sub materialize_all
{
    if( my $level = $_[0]->{'materialized'} < 2 )
    {
	my( $l ) = @_;
	$l->populate_all;
	if( my $mat = $l->{'materializer'} )
	{
	    my $max = $l->max();
	    if( $level < 1 ) # Nothing initialized
	    {
		my @objs;
		for( my $i=0; $i<=$max; $i++ )
		{
		    push @objs, &{$mat}( $l, $i );
		}
		$l->{'_OBJ'} = \@objs;
	    }
	    else # partly initialized
	    {
		my $objs = $l->{'_OBJ'};
		for( my $i=0; $i<=$max; $i++ )
		{
		    next if defined $objs->[$i];
		    $objs->[$i] = &{$mat}( $l, $i );
		}
	    }
	}
	else
	{
#	    debug "****2 OBJ=DATA for ".datadump($l); ### DEBUG
	    $l->{'materialized'} = 2;
	    $l->{'_OBJ'} = $l->{'_DATA'} ||= []; # Should be defined beforee this
	}
    }
    return $_[0]->{'_OBJ'};
}

#######################################################################

=head2 from_page

  $l->from_page( $pagenum )
  $l->from_page

TODO: Use Array::Window

Returns a ref to a list of elements corresponding to the given
C<$page> based on the L</page_size>. If no C<$pagenum>
is given, takes the value from query param table_page or 1.

=cut

sub from_page
{
    my( $l, $page ) = @_;

    $page ||= $Para::Frame::REQ->q->param('table_page') || 1;

#    @pagelist = ();

    if( $l->{'page_size'} < 1 )
    {
	return $l;
    }

    my $start = $l->{'page_size'} * ($page-1);
    my $end = List::Util::max( $start,
			       List::Util::min(
					       $start + $l->{'page_size'},
					       $l->size,
					      ) -1,
			     );

    debug 2, "From $start to $end";

    if( $end - $start )
    {
	return $l->slice($start, $end);
    }
    else
    {
	return $l->new_empty();
    }
}

#######################################################################

=head2 slice

  $l->slice( $start )
  $l->slice( $start, $end )
  $l->slice( $start, $end, \%args )

Similar to L<Class::DBI::Iterator/slice>.

Uses L</set_index> and L</get_next_raw> and L</index>.

Returns:

A L<Para::Frame::List> created with the same L</type>,
L</allow_undef> and L</materializer> args.

=cut

sub slice
{
    my( $l, $start, $end, $args ) = @_;

    $start ||= 0;

    $args ||= {};
    $args->{'type'} ||= $l->{'type'};
    $args->{'allow_undef'} ||= $l->{'allow_undef'};
    $args->{'materializer'} ||= $l->{'materializer'};

    carp "Slicing $l at $start with ".datadump($args);
    unless( $args->{'materializer'} )
    {
	debug "Coming from ".datadump( $l ); ### DEBUG
    }

    if( $l->{'populated'} > 1 )
    {
	$end ||= $l->max;
	return Para::Frame::List->new([@{$l->{'_DATA'}}[$start..$end]], $args);
    }
    else
    {
	my @data;
	$l->set_index( $start - 1 );

	$end ||= $l->{'limit'};
	if( $end )
	{
	    while( my $raw = $l->get_next_raw() )
	    {
		push @data, $raw;
		last if $l->index >= $end;
	    }
	}
	else
	{
	    while( my $raw = $l->get_next_raw() )
	    {
		push @data, $raw;
	    }
	}

	return Para::Frame::List->new(\@data, $args);
    }
}

#######################################################################

=head2 set_index

  $l->set_index($pos)

Similar to L<Tie::Array::Iterable/set_index> and L<IO::Seekable/seek>.
Most iterator classes doesn't have a comparable method.

Valid positions range from -1 (before first element) to C<$size + 1>
(after last element).

If C<$pos> is C<-1>, calls L</reset>.

=cut

sub set_index
{
    my( $l, $pos ) = @_;

    if( $pos < -1 )
    {
	throw('out_of_range', "Position $pos invalid");
    }

    my $max = $l->max;

    if( $pos > $max + 1 )
    {
	throw('out_of_range', "Position $pos invalid");
    }

    if( $pos == -1 )
    {
	$l->reset;
	return -1;
    }

    return $l->{'INDEX'} = $pos;
}


#######################################################################

=head2 store

  $l->store

Stores the object in the session for later retrieval by
L<Para::Frame::Session/list>

=cut

sub store
{
    my( $l ) = @_;

    unless( $l->{'stored_id'} )
    {
	my $session =  $Para::Frame::REQ->user->session;
	my $id = $session->{'listid'} ++;

#	# Remove previous from cache
#	if( my $prev = delete $session->{list}{$id - 1} )
#	{
#	    debug "Removed $prev (".($id-1).")";
#	}

	$l->{'stored_id'} = $id;
	$l->{stored_time} = time;

	$session->{'list'}{$id} = $l;

	debug "storing list $id";
    }

    return "";
}

######################################################################

=head2 id

  $l->id

Returns the C<id> given to this object from L</store> in the
L<Para::Frame::Session>.

=cut

sub id
{
    my( $l ) = @_;

    return $l->{'stored_id'};
}

#######################################################################

=head2 pages

  $l->pages

Returns the number of pages this list will take given L</page_size>.

=cut

sub pages
{
    my( $l ) = @_;

    if( $l->{'page_size'} < 1 )
    {
	return 1;
    }

    return int( $l->max / $l->{'page_size'} ) + 1;
}

#######################################################################

=head2 pagelist

  $l->pagelist( $pagenum )
  $l->pagelist

Returns a widget for navigating between the pages. If no C<$pagenum>
is given, takes the value from query param table_page or 1.

Example:

  [% USE Sorted_table('created','desc') %]
  [% usertable = cached_select_list("from users order by $order $direction") %]
  <table>
    <tr>
      <th>[% sort("Skapad",'created','desc') %]</th>
      <th>[% sort("Namn",'username') %]</th>
    </tr>
    <tr><th colspan="2">[% usertable.size %] users</th></tr>
    <tr><th colspan="2"> [% usertable.pagelist %]</th></tr>
  [% FOREACH user IN usertable.from_page %]
    [% tr2 %]
      <td>[% user.created %]</td>
      <td>[% user.name %]</td>
    </tr>
  [% END %]
  </table>

This uses L<Para::Frame::Template::Plugin::Sorted_table>, L<Para::Frame::DBIx/cached_select_list>, L<Para::Frame::Template::Components/sort>, L</size>, this pagelist, L<Template::Manual::Directives/Loop Processing> and L<Para::Frame::Template::Components/tr2>.

=cut

sub pagelist
{
    my( $l, $pagenum ) = @_;

    my $req = $Para::Frame::REQ;

    $pagenum ||= $req->q->param('table_page') || 1;

#    debug "Creating pagelist for $l";

    my $dpages = $l->{'display_pages'};
    my $pages = $l->pages;

    if( $pages <= 1 )
    {
	return "";
    }

    my $startpage = List::Util::max( $pagenum - $dpages/2, 1);
    my $endpage = List::Util::min( $pages, $startpage + $dpages - 1);

#    debug "From $startpage -> $endpage";

    # If 0, the caller should have taken care of caching in another way
    my $id = $l->id || 0;

    my $page = $req->page;
    my $me = $page->url_path;

    my $out = "<span class=\"paraframe_pagelist\">";

    if( $pagenum == 1 )
    {
#	$out .= "Först";
    }
    else
    {
	$out .= forward("<", $me, {use_cached=>$id, table_page => ($pagenum-1), href_class=>"paraframe_previous"});
#	$out .= forward("Först", $me, {use_cached=>$id, page => 1});
	$out .= " ";
    }
    if( $startpage != 1 )
    {
	$out .= forward(1, $me, {use_cached=>$id, table_page => 1});
	$out .= " ...";
    }

    foreach my $p ( $startpage .. $endpage )
    {
	if( $p == $pagenum )
	{
	    $out .= " <span class=\"selected\">$p</span>";
	}
	else
	{
	    $out .= " ";
	    $out .= forward($p, $me, {use_cached=>$id, table_page => $p});
	}
    }

    if( $endpage != $pages )
    {
	$out .= " ... ";
	$out .= forward($pages, $me, {use_cached=>$id, table_page => $pages});
    }

    if( $pagenum == $pages )
    {
#	$out .= "  Sist";
    }
    else
    {
	$out .= " ";
#	$out .= forward("Sist", $me, {use_cached=>$id, page => $pages});
	$out .= forward(">", $me, {use_cached=>$id, table_page => ($pagenum+1), href_class=>"paraframe_next"});
    }

    return $out . "</span>";
}


#######################################################################

=head2 page_size

  $l->page_size

Returns the C<page_size> set for this object.

=cut

sub page_size
{
    return $_[0]->{'page_size'};
}


######################################################################

=head2 set_page_size

  $l->set_page_size( $page_size )

Sets and returns the given C<$page_size>

=cut

sub set_page_size
{
    $_[0]->{'page_size'} = int($_[1]);
    return "";
}


#######################################################################

=head2 display_pages

  $l->display_pages

Returns how many pages that should be listed by L</pagelist>.

=cut

sub display_pages
{
    return $_[0]->{'display_pages'};
}


#######################################################################

=head2 display_pages

Sets and returns the given L</display_pages>.

=cut

sub set_display_pages
{
    $_[0]->{'display_pages'} = int($_[1]);
    return "";
}


#######################################################################

=head2 as_string

  $l->as_string

Returns a string representation of the list. Using C<as_string> for
elements that isn't plain scalars.

=cut

sub as_string
{
    my ($l) = @_;

    unless( ref $l )
    {
#	warn "  returning $l\n";
	return $l;
    }

    my $list = $l->as_arrayref;

    my $val = "";

    if( $#$list ) # More than one element
    {
	for( my $i = 0; $i<= $#$list; $i++)
	{
	    $val .= "* ";
	    if( ref $list->[$i] )
	    {
		$val .= $list->[$i]->as_string;
	    }
	    else
	    {
		$val .= $list->[$i];
	    }
	    $val .= "\n";
	}
    }
    else
    {
	if( ref $list->[0] )
	{
	    $val .= $list->[0]->as_string;
	}
	else
	{
	    $val .= $list->[0];
	}
    }

    return $val;
}


#######################################################################

=head2 set_limit

  $l->set_limit( $limit )

Limit the number of elements in the list.

A limit of C<$limit> or C<undef> means no limit.

Setting a limit smaller than the original length will make the
elements beyond the limit unavailible, if they already was populated.
Later setting a larger limit will not make more of the elements
availible.

The limit is applied in L</on_populate_all>, then retrieving elements
and in L</size> and L</max>.

The number of elements before the applied limit, if known, can be
retrieved from L</original_size>.

The limit may be larger than the elements in the list.

Similar to L<IO::Seekable/truncate> except that it doesn't delete
anything. Similar to limit in SQL.

TODO: Check for limit on array change

Returns:

The limit set, or 0

=cut

sub set_limit
{
    my( $l, $limit ) = @_;

    # TODO: Validate the value
    return $l->{'limit'} = $limit || 0;
}


#######################################################################

=head2 limit

  $l->limit()

Returns:

The current limit set by L</set_limit>

=cut

sub limit
{
    return $_[0]->{'limit'} ||= 0;
}


#######################################################################

=head2 get_first

  $l->get_first

The first record is returned, if defined, along with the STATUS_OK
value.  If there is no target data, or the data is an empty set, then
undef is returned with the STATUS_DONE value.

Compatible with L<Template::Iterator>. Similar to
L<List::Object/first> and L<Class::DBI::Iterator/first>.  Not the same
as ouer L</first>.

Calls L</reset> if the iterator index isn't at the start (at -1).

=cut

sub get_first
{
    my( $l ) = @_;

#    debug "GETTING first element of list";

    if( $l->{'INDEX'} > -1 )
    {
	$l->reset;
    }

    # Should only return one value

    return( ($l->get_next)[0] );
}



#######################################################################

=head2 get_last

  $l->get_last

The last record is returned, if defined, along with the STATUS_OK
value.  If there is no target data, or the data is an empty set, then
undef is returned with the STATUS_DONE value.

Similar to L<List::Object/last>.  Not the same as ouer L</last>.


=cut

sub get_last
{
    my( $l ) = @_;

    $l->{'INDEX'} = $l->max + 1;
    return $l->get_prev;
}



#######################################################################

=head2 reset

  $l->reset()

Sets the index to C<-1>, before the first element.

Similar to L<Array::Iterator::Reusable/reset>,
L<Class::DBI::Iterator/reset>, L<Class::PObject::Iterator/reset>,
L<Tie::Array::Iterable/from_start> and L<List::Object/rewind>.

Returns:

true

=cut

sub reset
{
    $_[0]->{'INDEX'} = -1;
    return 1;
}


#######################################################################

=head2 get_next

  $l->get_next()

Called repeatedly to access successive elements in the data set. Is
usually called after calling L</get_first>.

Compatible with L<Template::Iterator/get_next>.  Most other Iterator
classes call this method C<next()>. But our L</next> is not the same.

Similar to L<List::Object/next>, L<Array::Iterator/getNext>,
L<Class::DBI::Iterator/next>, L<Class::PObject::Iterator/next>,
L<Tie::Array::Iterable/next>, L<Iterator/value>,
L<IO::Seekable/getline> and Java C<next()>.

This method is implemented with L</get_next_raw> and L</materialize>.

Returns

The next element and a status

=cut

sub get_next
{
    my( $l ) = @_;

    my( $elem, $status ) = $l->get_next_raw;

    if( $status )
    {
#	debug "GET_NEXT got a status $status";
	return( $elem, $status );
    }

    my $i = $l->{'INDEX'};
    if( my $mat = $l->{'materializer'} )
    {
	$l->{'materialized'} ||= 1;
	return $l->{'_OBJ'}[ $i ] ||= &{$mat}( $l, $i );
    }
    else
    {
	return $elem;
    }
}

#######################################################################

=head2 get_next_raw

  $l->get_next_raw()

Used as a backend for L</get_next>.

Increments the index.

Returns:

The next element and a status

=cut

sub get_next_raw
{
    my( $l ) = @_;

    my $i = ++ $l->{'INDEX'};
    my $max = $l->max;
#    debug "MAX is $max";
#    debug "INDEX is $i";

    if( $i > $max )
    {
	# Compatible with Template::Iterator
	return(undef, Template::Constants::STATUS_DONE);   ## RETURN ##
    }

    unless( $l->{'populated'} > 1 )
    {
	$l->populate_all;
    }

    return $l->{'_DATA'}[$i];
}


#######################################################################

=head2 get_prev

  $l->get_prev()

May be called after calling L</get_last>.

Similar to L<Array::Iterator::BiDirectional/getPrevious>,
L<Tie::Array::Iterable/prev> and Java C<previous()>.

See also L</prev>.

This method is implemented with L</get_prev_raw> and L</materialize>.

=cut

sub get_prev
{
    my( $l ) = @_;

    my( $elem, $status ) = $l->get_prev_raw;

    if( $status )
    {
	return( $elem, $status );
    }

    my $i = $l->{'INDEX'};
    if( my $mat = $l->{'materializer'} )
    {
	$l->{'materialized'} ||= 1;
	return $l->{'_OBJ'}[ $i ] ||= &{$mat}( $l, $i );
    }
    else
    {
	return $elem;
    }
}

#######################################################################

=head2 get_prev_raw

  $l->get_prev_raw()

Used as a backend for L</get_prev>.

Returns:

The prev element and decrement the index.

=cut

sub get_prev_raw
{
    my( $l ) = @_;

    my $i = -- $l->{'INDEX'};

    if( $i < 0 )
    {
	# Compatible with Template::Iterator
	return(undef, Template::Constants::STATUS_DONE);   ## RETURN ##
    }

    unless( $l->{'populated'} > 1 )
    {
	$l->populate_all;
    }

    return $l->{'_DATA'}[$i];
}


#######################################################################

=head2 get_all

  $l->get_all

Method which returns all remaining items in the iterator as a Perl
list reference.  May be called at any time in the life-cycle of the
iterator.  The L</get_first> method will be called automatically if
necessary, and then subsequent L</get_next> calls are made, storing
each returned result until the list is exhausted.

Compatible with L<Template::Iterator/get_all>.

Sets the index on the last element. (Not the place after the element.)

Returns:

A ref to an array of the remaining elements, materialized.

If iterator already at the last index or later, returns C<undef> as
the first value and L<Template::Constants/STATUS_DONE> as the second.

=cut

sub get_all
{
    my( $l ) = @_;

    my $index = $l->{'INDEX'};
    my $max = $l->max;

    debug "get_all - index $index max $#{$l->{_DATA}}";

    # if there's still some data to go...
    if( $index < $max )
    {
	$l->materialize_all;

        $index++;
        my @data = @{ $l->{'_OBJ'} }[ $index .. $max ];
	$l->{'INDEX'} = $max;

        return \@data;                                      ## RETURN ##
    }
    else
    {
	# Compatible with Template::Iterator
        return (undef, Template::Constants::STATUS_DONE);   ## RETURN ##
    }
}



#######################################################################

=head2 size

  $l->size()

Similar to L<List::Object/count>, L<Array::Iterator/getLength>,
L<Class::DBI::Iterator/count>,
L<Class::MakeMethods::Template::Generic/count> and java C<getSize()>.

Compatible with L<Template::Iterator/size>.

Returns:

The number of elements in this list

=cut

sub size
{
#    carp "* Fetching size of List";
    unless( $_[0]->{'populated'} > 1 )
    {
	$_[0]->populate_all;
    }

    return scalar @{$_[0]->{'_DATA'}};
}


#######################################################################

=head2 max

  $l->max

Returns the maximum index number (i.e. the index of the last element)
which is equivalent to size() - 1.

Compatible with L<Template::Iterator/max>

=cut

sub max
{
    unless( $_[0]->{'populated'} > 1 )
    {
	$_[0]->populate_all;
    }

    return $#{$_[0]->{'_DATA'}};
}


#######################################################################

=head2 index

  $l->index()

Returns the current index number which is in the range 0 to max().

L<Template::Iterator/index> has the range C<0> to L</max>.  This
module allows the range C<-1> to L</max>C<+1>.

Similar to L<Array::Iterator/currentIndex>,
L<Tie::Array::Iterable/index>, L<IO::Seekable/tell> and Java
C<getPosition>.

Heres hoping that nothing breaks...

=cut

sub index
{
    return $_[0]->{'INDEX'};
}



#######################################################################

=head2 count

  $l->count()

Returns the current iteration count in the range 1 to size().  This is
equivalent to index() + 1.

Compatible with L<Template::Iterator/count>.

=cut

sub count
{
    return $_[0]->{'INDEX'}+1;
}


#######################################################################

=head2 first

  $l->first

Returns a boolean value to indicate if the iterator is currently on
the first iteration of the set. Ie, index C<0>.

Compatible with L<Template::Iterator/first>.

Similar to L<Array::Iterator::Circular/isStart> and
L<Tie::Array::Iterable/at_start>.

See also L</get_first>.

=cut

sub first
{
    return $_[0]->{'INDEX'} == 0 ? 1 : 0;
}

#######################################################################

=head2 last

  $l->last

Returns a boolean value to indicate if the iterator is currently on
the last iteration of the set.

Compatible with L<Template::Iterator/last>.

Similar to L<Array::Iterator::Circular/isEnd>,
L<Iterator/is_exhausted>, L<Tie::Array::Iterable/at_end> and
L<IO::Seekable/eof>.

See also L</get_last>.

=cut

sub last
{
    return $_[0]->{'INDEX'} == $_[0]->max ? 1 : 0;
}

#######################################################################

=head2 prev

  $l->prev

Returns the previous item in the data set, or undef if the iterator is
on the first item.

Compatible with L<Template::Iterator/prev>.

Similar to L<Array::Iterator::BiDirectional/lookBack>.

See also L</get_prev>.

=cut

sub prev
{
    return $_[0]->get( $_[0]->{'INDEX'} - 1 );
}

#######################################################################

=head2 next

  $l->next

Returns the next item in the data set or undef if the iterator is on
the last item.

Compatible with L<Template::Iterator/next>.

=cut

sub next
{
    return $_[0]->get( $_[0]->{'INDEX'} + 1 );
}


#######################################################################

=head2 has_next

 $l->has_next

Similar to L<List::Object/has_next>, L<Array::Iterator/hasNext> and
Java C<hasNext>.

Returns:

A bool

=cut

sub has_next
{
    my( $l ) = @_;

    my( $elem, $status ) = $l->get_next_raw();
    $l->{'INDEX'} --;
    return $status ? 0 : 1;

}


#######################################################################

=head2 has_prev

 $l->has_prev

Similar to L<Array::Iterator::BiDirectional/hasPrevious> and Java
C<hasPrevious>.

Returns:

A bool

=cut

sub has_prev
{
    my( $l ) = @_;

    my( $elem, $status ) = $l->get_prev_raw();
    $l->{'INDEX'} ++;
    return $status ? 0 : 1;

}

#######################################################################

=head2 current

  $l->current()

Similar to L<Array::Iterator/current> and
L<Tie::Array::Iterable/value>.

Implemented with L</get_next>

Returns:

The element (materialized) at the current index.

=cut

sub current
{
    $_[0]->{'INDEX'} --;
    return $_[0]->get_next();
}

#######################################################################

=head2 get_by_index

  $l->get_by_index( $index )

Similar to L<List::Object/get>.

Implemented with L</set_index> and L</get_next>.

Returns:

The element (materialized) at the current index.

=cut

sub get_by_index
{
    $_[0]->set_index( $_[1] - 1 );
    return $_[0]->get_next();
}

#######################################################################

=head2 clear

  $l->clear()

Similar to L<List::Object/clear>

=cut

sub clear
{
    my( $l ) = @_;

    $l->reset;
#    debug "****3 OBJ=DATA for ".datadump($l); ### DEBUG
    $l->{'_DATA'} = $l->{'_OBJ'} = [];
    $l->{'materialized'} = 0;
    return 1;
}


#######################################################################

sub obj_as_string
{
    carp "Returning a stringification of a list";
    return "A Para::Frame::List obj";
}


#######################################################################


sub test
{
    my( $l ) = @_;


    debug "The obj: ".$l;
}


#######################################################################

=head2 set_type

The class or datatype of all the content in the list

 TODO: Validate content with this

=cut

sub set_type
{
    return $_[0]->{'type'} = $_[1];
}



#######################################################################




1;

=head1 SEE ALSO

L<Para::Frame>, L<DBI>

=cut
