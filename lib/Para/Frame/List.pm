package Para::Frame::List;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2014 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::List - Methods for list manipulation

=cut

use 5.010;
use strict;
use warnings;
use base qw( Template::Iterator );

use Carp qw( carp croak shortmess confess cluck );
use List::Util;
use Template::Constants;
use Scalar::Util qw(blessed reftype looks_like_number);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug timediff datadump );
use Para::Frame::Widget qw( forward );

# bool overload should use get_next_raw to find

use overload
  '@{}' => 'as_arrayref_by_overload',
#  'bool' => sub{carp "* Bool"; $_[0]->size},
  'bool' => sub{$_[0]->size},
  '!'    => sub{! $_[0]->size },
  '""' => 'stringify_by_overload',
  '.' => 'concatenate_by_overload',
  'fallback' => 0;

our $AUTOLOAD;


=head2 SYNOPSIS

# The right way:

  my $list = Para::Frame::List->new( \@biglist );
  my( $value, $error ) = $list->get_first;
  while(! $error )
  {
    # ... my code
  }
  continue
  {
    ( $value, $error ) = $list->get_next;
  }


# The risky way, for lists that doesn't contain false values:

  my $list = Para::Frame::List->new( \@biglist );
  $list->reset; # if used before...
  while( my $value = $list->get_next_nos )
  {
    # ... my code
  }


# The lazy way:

  my $list = Para::Frame::List->new( \@biglist );
  foreach my $value ( $list->as_array )
  {
    # ... my code
  }


=head2 DESCRIPTION

LOOK! REDEFINES shift, push, pop, unshift, splice, join, index


The object is overloaded to be used as a ref to the list it
contains. All list operations can be used as usual. Example:

  my $l = Para::Frame::List->new( \@biglist );
  my $first_element = $l->[0];
  my $last_element = pop @$l;

The iteration methods is compatible with (and inherits from)
L<Template::Iterator>. (The iterator status codes are taken from
L<Template::Constants>.)

CGI query parameters reserved for use with some methods are:

  order
  direction
  table_page


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

##############################################################################

=head2 new

  $l = $class->new( \@list )

  $l = $class->new( \@list, \%params )

Availible params are:

  page_size      (default is 20 )
  display_pages  (default is 10 )
  limit_pages    (default is 0 == unlimited)
  limit          (default is 0 == unlimited)
  limit_display  (default is 0 == unlimited)
  materializer   (default is undef == list is material)
  type           (default is undef)
  allow_undef    (default is undef)

The first argument may be a L<Para::Frame::List> object, in which case
it's content is copied to this new list.

If the first argument is undef, the list is marked as unpopulated

See also: L</set_materializer>

Compatible with L<Template::Iterator/new>.

Returns:

A an object blessed in C<$class>

=cut

sub new
{
    my( $this, $data_in, $args ) = @_;
    my $class = ref($this) || $this;

    if ( blessed $data_in and $data_in->isa("Para::Frame::List") )
    {
        if ( ref $data_in eq $class )
        {
            return $data_in;
        }

        # Creating new arrayref
        $data_in = [$data_in->as_array];
    }

#    debug "New list created with args ".datadump($args);

    my $data;
    my $l = bless
    {
     'INDEX'         => -1,     # Before first element
     'materialized'  => 0, # 1 for partly and 2 for fully materialized
     'materializer'  => undef,
     '_DATA'         => undef,
     'populated'     => 0,    # 1 for partly and 2 for fully populated
     '_OBJ'          => undef, # the corresponding list of materalized elements
    }, $class;

    if ( $args )
    {
        $l->{'allow_undef'} = $args->{'allow_undef'};
        $l->{'limit'} = $args->{'limit'};
        $l->{'limit_display'} = $args->{'limit_display'};
        $l->{'page_size'} = $args->{'page_size'};
        $l->{'display_pages'} = $args->{'display_pages'};
        $l->{'limit_pages'} = $args->{'limit_pages'};
        $l->{'sorted_on'} = $args->{'sorted_on'};
        $l->{'sorted_on_key'} = $args->{'sorted_on_key'};
    }


    if ( $data_in )
    {
        my $limit = $l->{'limit'};
        my $size = scalar(@$data_in);

        # Removes other things like overload
        if ( ref $data_in eq 'ARRAY' )
        {

            if ( $limit and ($limit < $size) )
            {
                $l->{'original_size'} = $size;
                # TODO: Is this effective for large lists?
                $data = [ @{$data_in}[0..($limit-1)] ];
            }
            else
            {
                $data = $data_in;
            }
        }
        else
        {
            unless ( eval{ $data_in->isa("ARRAY") } )
            {
                my $type = ref $data_in;
                die "$type is not an array ref";
            }

            if ( $limit and ($limit < $size) )
            {
                $l->{'original_size'} = $size;
                $data = [ @{$data_in}[0..($limit-1)] ];
            }
            else
            {
                $data = [ @{$data_in} ];
            }
        }
#	debug "Placing DATA in listobj ".datadump($data);

        $l->{'_DATA'} = $data;
    }

    $args ||= {};
    $l->init( $args );

    if ( my $mat_in =  $args->{'materializer'} )
    {
        # After the init
        $l->set_materializer( $mat_in );
    }

    if ( $l->{'_DATA'} )
    {
        # After the init
        $l->on_populate_all;
    }

    return $l;
}

##############################################################################

=head2 new_any

  $l = $class->new( $any )

  $l = $class->new( $any, \%params )

The same as L</new> but accepts more forms of lists.

If C<$any> is a L<Para::Frame::List> object, or an array ref, it will
be sent to the L</new> constructor.

For all other defined values of L<$any>, it will be taken as a list of
that single element and sent to L</new> as C<[$any]>.

If C<$any> is undef, the constructor L</new_empty> will be used.

=cut

sub new_any
{
    my( $this, $data_in, $args ) = @_;
    my $class = ref($this) || $this;

    if ( defined $data_in )
    {
        if ( blessed $data_in )
        {
            if ( $data_in->isa("Para::Frame::List") )
            {
                return $class->new( $data_in, $args );
            }
        }
        elsif ( reftype $data_in )
        {
            if ( reftype $data_in eq "ARRAY")
            {
                return $class->new( $data_in, $args );
            }
        }

        return $class->new( [$data_in], $args );
    }

    return $class->new_empty();
}


##############################################################################

=head2 new_empty

  $l = $class->new_empty()

This is an optimized form of L</new> that is faster and more memory
efficient than L</new> but should behave in the same way.

=cut

sub new_empty
{
    my( $this ) = @_;
    my $class = ref($this) || $this;

    my $l = bless
    {
     'INDEX'         => -1,     # Before first element
     'materialized'  => 2, # 1 for partly and 2 for fully materialized
     'materializer'  => undef,
     '_DATA'         => [],
     'populated'     => 2,    # 1 for partly and 2 for fully populated
#     '_OBJ'          => [], # the corresponding list of materalized elements
#     'limit'         => 0,
#     'limit_display' => 0,
#     'page_size'     => 0,
#     'display_pages' => 0,
#     'limit_pages'   => 0,
#     'stored_id'     => undef,
#     'stored_time'   => undef,
    }, $class;

    $l->{'_OBJ'} = $l->{'_DATA'};

    return $l;
}


##############################################################################

=head2 init

  $l->init

Called by L</new> for additional initializing. Subclasses can use this
for filling the list with data or adding more properties.

=cut

sub init
{
    # Reimplement this
}


##############################################################################

=head2 set_materializer

  $l->set_materializer( $materializer )

The materializer can be used to format an element before it's returned
from the list.  This can be used for turning a record id to an object.
With a materializer, the objectification or formatting of the data can
be done on demand which will save a lot of computation in the case of
large lists like search results.

C<$materializer> should be a subref that takes the params C<$l, $i>
where C<$i> is the index of the element to materialize.  The
materializer sub should return the materialized form of the element.

See L</materialize_all> and L</new>.

Returns:

The given C<$materializer> subref.

=cut

sub set_materializer
{
    my( $l, $mat_in ) = @_;

    $l->{'materializer'} = $mat_in;

    $l->{'_OBJ'} = [];

    return $l->{'materializer'};
}


##############################################################################

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
    unless ( $_[0]->{'materialized'} > 1 )
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

    unless ( $_[0]->{'materialized'} > 1 )
    {
        return $_[0]->materialize_all;
    }
#    carp "* OVERLOAD arrayref for list obj used";
    return $_[0]->{'_OBJ'};
}


##############################################################################

=head2 concatenate

implemented concatenate_by_overload()

=cut

sub concatenate_by_overload
{
    my( $l, $str, $is_rev ) = @_;
    carp "* OVERLOAD concatenate for list obj used";

    my $lstr = $l->stringify_by_overload();
    if ( $is_rev )
    {
        return $str.$lstr;
    }
    else
    {
        return $lstr.$str;
    }
}

##############################################################################

=head2 stringify

stringify_by_overload() method defined

=cut

sub stringify_by_overload
{
    return ref($_[0])."=".Scalar::Util::refaddr($_[0]);
}

##############################################################################

=head2 as_raw_arrayref

  $l->as_arrayref()

Returns the internal arrayref to the unmaterialized elements.

=cut

sub as_raw_arrayref
{
    unless ( $_[0]->{'populated'} > 1 )
    {
        return $_[0]->populate_all;
    }
    return $_[0]->{'_DATA'};
}



##############################################################################

=head2 as_list

  $l->as_list()

Compatible with L<Template::Iterator>.

See also L</get_all> and L</elements>.

Returns:

A ref to the internal list of elements returned by
L</materialize_all>.

=cut

sub as_list
{
    unless ( $_[0]->{'materialized'} > 1 )
    {
        return $_[0]->materialize_all;
    }
    return $_[0]->{'_OBJ'};
}


########################################################################

=head2 as_listobj

  $l->as_listobj()

Retruns: the object itself

=cut

sub as_listobj
{
    return $_[0];
}


######################################################################

=head2 as_array

  $l->as_array()

Similar to L<List::Object/array> and L<IO::Handle/getlines>. See also
L</get_all> and L</as_list>.

Returns:

The list as a list. (Not a ref) (And not realy an array either...)

=cut

sub as_array
{
    unless ( $_[0]->{'materialized'} > 1 )
    {
        $_[0]->materialize_all;
    }
    return @{$_[0]->{'_OBJ'}};
}


##############################################################################

=head2 as_raw_array

  $l->as_raw_array()

Returns the unmaterialized list as a list of elements (not ref).

=cut

sub as_raw_array
{
    unless ( $_[0]->{'populated'} > 1 )
    {
        $_[0]->populate_all;
    }
    return @{$_[0]->{'_DATA'}};
}


##############################################################################

=head2 populate_all

  $l->populate_all()

Reimplement this if the content should be set on demand in a subclass.

Returns:

The raw data listref of unmateralized elements.

=cut

sub populate_all
{
    unless ( $_[0]->{'populated'} > 1 )
    {
        $_[0]->{'_DATA'} = [];
        $_[0]->on_populate_all;
    }

    return $_[0]->{'_DATA'};
}

##############################################################################

=head2 on_populate_all

  $l->on_populate_all()

=cut

sub on_populate_all
{
    my( $l ) = @_;

    $l->{'_DATA'} ||= [];       # Should have been defined
    $l->{'populated'} = 2;      # Mark as fully populated

    if ( my $lim = $l->{'limit'} )
    {
        if ( $lim < scalar(@{$l->{'_DATA'}}) )
        {
            debug "LIMITING DATA SIZE TO $lim";
            CORE::splice @{$l->{'_DATA'}}, $lim;
        }
    }

    unless ( $l->{'materializer'} and $l->size )
    {
#	debug "**** OBJ=DATA for ".datadump($l); ### DEBUG
        $l->{'materialized'} = 2;
        return $l->{'_OBJ'} = $l->{'_DATA'} ||= []; # Should have been defined
    }
    return  $l->{'_DATA'};
}

##############################################################################

=head2 materialize_all

  $l->materialize_all()

If L</materializer> is set, calls it for each unmaterialized element
and returns a ref to an array of the materialized elements

In no materialization is needed, just returns the existing data as an
array ref.

=cut

sub materialize_all
{
    if ( my $level = $_[0]->{'materialized'} < 2 )
    {
        my( $l ) = @_;
        $l->populate_all;
        if ( my $mat = $l->{'materializer'} )
        {
            my $max = $l->max();

            if ( $max >= 1000 )
            {
                $Para::Frame::REQ->note(sprintf "Materializing %d nodes", $max+1);
            }

            if ( $level < 1 )   # Nothing initialized
            {
                my @objs;
                for ( my $i=0; $i<=$max; $i++ )
                {
                    CORE::push @objs, &{$mat}( $l, $i );
                    unless( ($i+1) % 1000 )
                    {
                        $Para::Frame::REQ->note(sprintf "%5d", $i+1);
                        $Para::Frame::REQ->may_yield;
                    }
                }
                $l->{'_OBJ'} = \@objs;
            }
            else                # partly initialized
            {
                my $objs = $l->{'_OBJ'};
                for ( my $i=0; $i<=$max; $i++ )
                {
                    unless( ($i+1) % 1000 )
                    {
                        $Para::Frame::REQ->note(sprintf "%5d", $i+1);
                        $Para::Frame::REQ->may_yield;
                    }

                    next if defined $objs->[$i];
                    $objs->[$i] = &{$mat}( $l, $i );
                }
            }

            $l->{'materialized'} = 2;
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

##############################################################################

=head2 from_page

  $l->from_page( $pagenum )
  $l->from_page

Returns a ref to a list of elements corresponding to the given
C<$page> based on the L</page_size>. If no C<$pagenum>
is given, takes the value from query param table_page or 1.

... I have looked at Array::Window but will not use it.

=cut

sub from_page
{
    my( $l, $page ) = @_;

    $page ||= $Para::Frame::REQ->q->param('table_page') || 1;

#    @pagelist = ();

    my $page_size = $l->page_size;
    if ( $page_size < 1 )
    {
        return $l;
    }

    my $start = $page_size * ($page-1);
    my $end = List::Util::max( $start,
                               List::Util::min(
                                               $start + $page_size,
                                               $l->size_limited,
                                              ) -1,
                             );

    debug 2, "From $start to $end";

    my $res;
    if ( $end - $start >= 0 )
    {
        $res = $l->slice($start, $end);
    }
    else
    {
        $res = $l->new_empty();
    }

    return $res;
}

##############################################################################

=head2 slice

  $l->slice( $start )
  $l->slice( $start, $end )
  $l->slice( $start, $end, \%args )

Similar to L<Class::DBI::Iterator/slice>.

If C<%args> is not given, clones the args of C<$l>.

Uses L</set_index> and L</get_next_raw> and L</index>.

Returns:

A L<Para::Frame::List> created with the same L</type>,
L</allow_undef> and L</materializer> args.

=cut

sub slice
{
    my( $l, $start, $end, $args ) = @_;

    my $class = ref $l;
    $start ||= 0;
    $args ||= $l->clone_props;

#    carp "Slicing $l at $start with ".datadump($args);
    unless ( $args->{'materializer'} )
    {
#	debug "Coming from ".datadump( $l ); ### DEBUG
    }

    if ( $l->{'populated'} > 1 )
    {
        $end ||= $l->max;
        if ( $l->{'materialized'} > 1 )
        {
            undef $args->{'materializer'}; # Already done
            my $data = [@{$l->{'_OBJ'}}[$start..$end]];
            return  $class->new($data, $args);
        }

        my $data = [@{$l->{'_DATA'}}[$start..$end]];
        my $slize =  $class->new($data, $args);

        if ( $l->{'materialized'} == 1 ) # partly
        {
            $slize->{'_OBJ'} = [@{$l->{'_OBJ'}}[$start..$end]];
            $slize->{'materialized'} = 1;
        }

        return $slize;
    }
    else
    {
        my @data;
        $l->set_index( $start - 1 );

        $end ||= $l->{'limit'};
        if ( $end )
        {
            while ( my $raw = $l->get_next_raw() )
            {
                CORE::push @data, $raw;
                last if $l->index >= $end;
            }
        }
        else
        {
            while ( my $raw = $l->get_next_raw() )
            {
                CORE::push @data, $raw;
            }
        }

        return $class->new(\@data, $args);
    }
}

##############################################################################

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

    if ( $pos < -1 )
    {
        throw('out_of_range', "Position $pos invalid");
    }

    my $max = $l->max;

    if ( $pos > $max + 1 )
    {
        throw('out_of_range', "Position $pos invalid");
    }

    if ( $pos == -1 )
    {
        $l->reset;
        return -1;
    }

    return $l->{'INDEX'} = $pos;
}


##############################################################################

=head2 store

  $l->store

Stores the object in the session for later retrieval by
L<Para::Frame::Session/list>

=cut

sub store
{
    my( $l ) = @_;

    unless ( $l->{'stored_id'} )
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

#	debug "storing list $id";
    }

    return "";
}

######################################################################

=head2 id

DEPRECATED

  $l->id

Returns the C<id> given to this object from L</store> in the
L<Para::Frame::Session>.

=cut

sub id
{
    my( $l ) = @_;

    cluck "DEPRECATED CALL to list->id()";

    return undef;
#    return $l->{'stored_id'};
}

######################################################################

=head2 list_id

  $l->list_id

Returns the C<id> given to this object from L</store> in the
L<Para::Frame::Session>.

=cut

sub list_id
{
    my( $l ) = @_;

    return $l->{'stored_id'};
}

##############################################################################

=head2 pages

  $l->pages

Returns the number of pages this list will take given L</page_size>.

=cut

sub pages
{
    my( $l ) = @_;

    my $page_size = $l->page_size;
    if ( $page_size < 1 )
    {
        return 1;
    }

    my $pages = int( $l->max_limited / $page_size ) + 1;

#    debug "page_size = ".$page_size;
#    debug "max_limited = ".$l->max_limited;
#    debug "pages = ".$pages;

    if ( my $lim = $l->limit_pages )
    {
        return List::Util::min( $lim, $pages );
    }

    return $pages;
}

##############################################################################

=head2 page_size

  $l->page_size

Returns the C<page_size> set for this object.

=cut

sub page_size
{
    return $_[0]->{'page_size'} ||= 20;
}

##############################################################################

=head2 pagelist

  $l->pagelist( $pagenum )
  $l->pagelist

Returns a widget for navigating between the pages. If no C<$pagenum>
is given, takes the value from query param table_page or 1.

If only one page, returns an empty string.

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

    $pagenum ||= $l->pagenum;

#    debug "Creating pagelist for $l";

    my $dpages = $l->display_pages;
    my $pages = $l->pages;

    if ( $pages <= 1 )
    {
        return "";
    }

    my $startpage = List::Util::max( $pagenum - $dpages/2, 1);
    my $endpage = List::Util::min( $pages, $startpage + $dpages - 1);

#    debug "From $startpage -> $endpage";

    # If 0, the caller should have taken care of caching in another way
    my $id = $l->list_id || 0;

    my $page = $req->page;
    my $me = $page->url_path;

    my $out = "<span class=\"paraframe_pagelist\">";

    if ( $pagenum == 1 )
    {
#	$out .= "First";
    }
    else
    {
        $out .= forward("<", $me, {use_cached=>$id, table_page => ($pagenum-1), tag_attr=>{class=>"paraframe_previous"}});
#	$out .= forward("First", $me, {use_cached=>$id, page => 1});
        $out .= " ";
    }
    if ( $startpage != 1 )
    {
        $out .= forward(1, $me, {use_cached=>$id, table_page => 1});
        $out .= " ...";
    }

    foreach my $p ( $startpage .. $endpage )
    {
        if ( $p == $pagenum )
        {
            $out .= " <span class=\"selected\">$p</span>";
        }
        else
        {
            $out .= " ";
            $out .= forward($p, $me, {use_cached=>$id, table_page => $p});
        }
    }

    if ( $endpage != $pages )
    {
        $out .= " ... ";
        $out .= forward($pages, $me, {use_cached=>$id, table_page => $pages});
    }

    if ( $pagenum == $pages )
    {
#	$out .= "  Sist";
    }
    else
    {
        $out .= " ";
#	$out .= forward("Sist", $me, {use_cached=>$id, page => $pages});
        $out .= forward(">", $me, {use_cached=>$id, table_page => ($pagenum+1), tag_attr=>{class=>"paraframe_next"}});
    }

    return $out . "</span>";
}


######################################################################

=head2 pagenum

  $l->pagenum

Returns the current page number, as given by the query param C<table_page>.

=cut

sub pagenum
{
    return $Para::Frame::REQ->q->param('table_page') || 1;
}


######################################################################

=head2 set_page_size

  $l->set_page_size( $page_size )

Sets the given C<$page_size>. Returns the same list.

=cut

sub set_page_size
{
    $_[0]->{'page_size'} = int($_[1]);
    return $_[0];
}


##############################################################################

=head2 display_pages

  $l->display_pages

Returns how many pages that should be listed by L</pagelist>.

=cut

sub display_pages
{
    return $_[0]->{'display_pages'} ||= 10;
}


##############################################################################

=head2 set_display_pages

Sets and returns the given L</display_pages>.

=cut

sub set_display_pages
{
    $_[0]->{'display_pages'} = int($_[1]);
    return "";
}


##############################################################################

=head2 set_limit_pages

Sets and returns the given L</limit_pages>.

=cut

sub set_limit_pages
{
    $_[0]->{'limit_pages'} = int($_[1]);
    return "";
}


##############################################################################

=head2 limit_pages

  $l->limit_pages

Returns the last page number that should be listed by L</pagelist>.

=cut

sub limit_pages
{
    return $_[0]->{'limit_pages'} || 0;
}


##############################################################################

=head2 limit_display

  $l->limit_display

Returns how many results that will be shown then listed as pages

=cut

sub limit_display
{
    return $_[0]->{'limit_display'} || 0;
}


##############################################################################

=head2 set_limit_display

Sets and returns the given L</limit_display>.

=cut

sub set_limit_display
{
    $_[0]->{'limit_display'} = int($_[1]);
    return "";
}


##############################################################################

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

    if ( $#$list )              # More than one element
    {
        for ( my $i = 0; $i<= $#$list; $i++)
        {
            $val .= "* ";
            if ( ref $list->[$i] )
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
        if ( ref $list->[0] )
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


##############################################################################

=head2 set_limit

  $l->set_limit( $limit )

Limit the number of elements in the list.

A limit of C<$limit> or C<undef> means no limit.

Setting a limit smaller than the original length will make the
elements beyond the limit unavailible, if they already was populated.
Later setting a larger limit will not make more of the elements
availible.

The limit is applied directly.

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

    if ( $limit )
    {
        if ( $limit < $l->size )
        {
            if ( $l->{'populated'} > 1 )
            {
                # Changes the array size
                $#{$l->{'_DATA'}} = ($limit-1);

                if ( $l->{'materialized'} )
                {
                    $#{$l->{'_OBJ'}} = ($limit-1);
                }
            }
        }
    }

    return $l->{'limit'} = $limit || 0;
}


##############################################################################

=head2 limit

  $l->limit()

Returns:

The current limit set by L</set_limit>

=cut

sub limit
{
    return $_[0]->{'limit'} ||= 0;
}


##############################################################################

=head2 get_first

  $l->get_first

The first record is returned, if defined, along with the STATUS_OK
value.  If there is no target data, or the data is an empty set, then
undef is returned with the STATUS_DONE value as the second element in
the return list.

Compatible with L<Template::Iterator>. Similar to
L<List::Object/first> and L<Class::DBI::Iterator/first>.  Not the same
as ouer L</first>.

Calls L</reset> if the iterator index isn't at the start (at -1).



=cut

sub get_first
{
    my( $l ) = @_;

#    debug "GETTING first element of list";

    if ( $l->{'INDEX'} > -1 )
    {
        $l->reset;
    }

    # Should only return all values from get_next
    return( $l->get_next );
}



##############################################################################

=head2 get_first_nos

  $l->get_first_nos

The same as L</get_first> except that it only returns ONE value, that
may be undef.

=cut

sub get_first_nos
{
    return(($_[0]->get_first)[0]);
}



##############################################################################

=head2 get_last

  $l->get_last

The last record is returned, if defined, along with the STATUS_OK
value.  If there is no target data, or the data is an empty set, then
undef is returned with the STATUS_DONE value as the second element in the return list.

Similar to L<List::Object/last>.  Not the same as ouer L</last>.


=cut

sub get_last
{
    my( $l ) = @_;

    $l->{'INDEX'} = $l->max + 1;
    return $l->get_prev;
}



##############################################################################

=head2 get_last_nos

  $l->get_last_nos

The same as L</get_last> except that it only returns ONE value, that
may be undef.

=cut

sub get_last_nos
{
    return( ($_[0]->get_last)[0] );
}



##############################################################################

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


##############################################################################

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

The next element and a status as the two elements in the return list

=cut

sub get_next
{
    my( $l ) = @_;

    my( $elem, $status ) = $l->get_next_raw;

    if ( $status )
    {
#	debug "GET_NEXT got a status $status";
        return( $elem, $status );
    }

    my $i = $l->{'INDEX'};

    if ( my $mat = $l->{'materializer'} )
    {
        $l->{'materialized'} ||= 1;
        return $l->{'_OBJ'}[ $i ] ||= &{$mat}( $l, $i );
    }
    else
    {
        return $elem;
    }
}

##############################################################################

=head2 get_next_nos

  $l->get_next_nos()

The same as L</get_next> except that it only returns ONE value, that
may be undef. (Get Next with NO Status)

=cut

sub get_next_nos
{
    return( ($_[0]->get_next)[0] );
}

##############################################################################

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

    if ( $i > $max )
    {
        # Compatible with Template::Iterator
        return(undef, Template::Constants::STATUS_DONE); ## RETURN ##
    }

    unless ( $l->{'populated'} > 1 )
    {
        $l->populate_all;
    }

    return $l->{'_DATA'}[$i];   # Error val undef = no error
}


##############################################################################

=head2 get_prev

  $l->get_prev()

May be called after calling L</get_last>.

Similar to L<Array::Iterator::BiDirectional/getPrevious>,
L<Tie::Array::Iterable/prev> and Java C<previous()>.

See also L</prev>.

This method is implemented with L</get_prev_raw> and L</materialize>.

Returns

The prev element and a status as the two elements in the return list

=cut

sub get_prev
{
    my( $l ) = @_;

    my( $elem, $status ) = $l->get_prev_raw;

    if ( $status )
    {
        return( $elem, $status );
    }

    my $i = $l->{'INDEX'};
    if ( my $mat = $l->{'materializer'} )
    {
        $l->{'materialized'} ||= 1;
        return $l->{'_OBJ'}[ $i ] ||= &{$mat}( $l, $i );
    }
    else
    {
        return $elem;
    }
}

##############################################################################

=head2 get_prev_nos

  $l->get_prev_nos()

The same as L</get_prev> except that it only returns ONE value, that
may be undef.

=cut

sub get_prev_nos
{
    return( ($_[0]->get_prev)[0] );
}

##############################################################################

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

    if ( $i < 0 )
    {
        # Compatible with Template::Iterator
        return(undef, Template::Constants::STATUS_DONE); ## RETURN ##
    }

    unless ( $l->{'populated'} > 1 )
    {
        $l->populate_all;
    }

    return $l->{'_DATA'}[$i];
}


##############################################################################

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
    if ( $index < $max )
    {
        $l->materialize_all;

        $index++;
        my @data = @{ $l->{'_OBJ'} }[ $index .. $max ];
        $l->{'INDEX'} = $max;

        return \@data;          ## RETURN ##
    }
    else
    {
        # Compatible with Template::Iterator
        return (undef, Template::Constants::STATUS_DONE); ## RETURN ##
    }
}


##############################################################################

=head2 size

  $l->size()

Similar to L<List::Object/count>, L<Array::Iterator/getLength>,
L<Class::DBI::Iterator/count>,
L<Class::MakeMethods::Template::Generic/count> and java C<getSize()>.

Compatible with L<Template::Iterator/size> and L<Template::Manual::VMethods/List Virtual Methods>

Returns:

The number of elements in this list

=cut

sub size
{
#    carp "* Fetching size of List";
    unless ( $_[0]->{'populated'} > 1 )
    {
        $_[0]->populate_all;
    }

    return scalar @{$_[0]->{'_DATA'}};
}


##############################################################################

=head2 size_limited

  $l->size_limited()

Returns: the L</size>, constraining to given L</limit_display>

=cut

sub size_limited
{
    unless ( $_[0]->{'populated'} > 1 )
    {
        $_[0]->populate_all;
    }

    if ( my $lim = $_[0]->{'limit_display'} )
    {
        return List::Util::min( $lim, scalar(@{$_[0]->{'_DATA'}}));
    }

    return scalar(@{$_[0]->{'_DATA'}});
}


##############################################################################

=head2 original_size

=cut

sub original_size
{
    return $_[0]->{'original_size'} ||= $_[0]->size;
}


##############################################################################

=head2 max

  $l->max

Returns the maximum index number (i.e. the index of the last element)
which is equivalent to size() - 1.

Compatible with L<Template::Iterator/max> and
L<Template::Manual::VMethods/List Virtual Methods>

=cut

sub max
{
    unless ( $_[0]->{'populated'} > 1 )
    {
        $_[0]->populate_all;
    }

    return $#{$_[0]->{'_DATA'}};
}


##############################################################################

=head2 max_limited

  $l->max_limited()

Returns: the L</max>, constraining to given L</limit_display>

=cut

sub max_limited
{
    unless ( $_[0]->{'populated'} > 1 )
    {
        $_[0]->populate_all;
    }

    if ( my $lim = $_[0]->{'limit_display'} )
    {
        return List::Util::min( ($lim-1), $#{$_[0]->{'_DATA'}});
    }

    return $#{$_[0]->{'_DATA'}};
}


##############################################################################

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



##############################################################################

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


##############################################################################

=head2 first

  $l->first

Returns a boolean value to indicate if the iterator is currently on
the first iteration of the set. Ie, index C<0>.

Compatible with L<Template::Iterator/first> and
L<Template::Manual::VMethods/List Virtual Methods>

.

Similar to L<Array::Iterator::Circular/isStart> and
L<Tie::Array::Iterable/at_start>.

See also L</get_first>.

=cut

sub first
{
    return $_[0]->{'INDEX'} == 0 ? 1 : 0;
}

##############################################################################

=head2 last

  $l->last

Returns a boolean value to indicate if the iterator is currently on
the last iteration of the set.

Compatible with L<Template::Iterator/last> and L<Template::Manual::VMethods/List Virtual Methods>


Similar to L<Array::Iterator::Circular/isEnd>,
L<Iterator/is_exhausted>, L<Tie::Array::Iterable/at_end> and
L<IO::Seekable/eof>.

See also L</get_last>.

=cut

sub last
{
    return $_[0]->{'INDEX'} >= $_[0]->max ? 1 : 0;
}

##############################################################################

=head2 prev

  $l->prev

Returns the previous item in the data set, or undef if the iterator is
on the first item.

This does B<not> change the iterator index.

Compatible with L<Template::Iterator/prev>.

Similar to L<Array::Iterator::BiDirectional/lookBack>.

See also L</get_prev>.

=cut

sub prev
{
    return $_[0]->get( $_[0]->{'INDEX'} - 1 );
}

##############################################################################

=head2 next

  $l->next

Returns the next item in the data set or undef if the iterator is on
the last item.

This does B<not> change the iterator index.

Compatible with L<Template::Iterator/next>.

=cut

sub next
{
    return $_[0]->get( $_[0]->{'INDEX'} + 1 );
}


##############################################################################

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


##############################################################################

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

##############################################################################

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

##############################################################################

=head2 get_by_index

  $l->get_by_index( $index )

Similar to L<List::Object/get>.

Implemented with L</set_index> and L</get_next>.

Returns:

The element (materialized) at C<$index>.  (First element has index 0).

Or undef

=cut

sub get_by_index
{
    $_[0]->set_index( $_[1] - 1 );
    return $_[0]->get_next_nos();
}

##############################################################################

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


##############################################################################

=head2 obj_as_string

=cut

sub obj_as_string
{
    carp "Returning a stringification of a list";
    return "A Para::Frame::List obj";
}


##############################################################################

=head2 randomized

  $l->randomized

Doesn't modify the object

Returns:

A new list with the content in random order, but with the same properties

=cut

sub randomized
{
    my( $l ) = @_;

    my $apply_limit;
    unless ( $l->{'populated'} > 1 )
    {
        # Apply limit AFTER randomization
        debug "    populating";
        $apply_limit = $l->{'limit'};
        $l->{'limit'} = 0;
        $l->populate_all;
    }

    my $args = $l->clone_props;
    my $data = $l->{'_DATA'};

    if ( $l->{'materialized'} > 1 )
    {
#	debug "    using materialized list";
        undef $args->{'materializer'}; # Already done
        $data = $l->{'_OBJ'};
    }

    if ( $apply_limit )
    {
        $l->set_limit( $apply_limit );
    }

#    debug "Returning randomized list";
    return $l->new([List::Util::shuffle(@$data)], $args);
}


##############################################################################


sub test
{
    my( $l ) = @_;

    debug "The obj: ".$l;
}


##############################################################################

=head2 set_type

The class or datatype of all the content in the list

 TODO: Validate content with this

=cut

sub set_type
{
    return $_[0]->{'type'} = $_[1];
}



##############################################################################

=head2 clone_props

=cut

sub clone_props
{
    my( $l ) = @_;

    my $args =
    {
     'type'          => $l->{'type'},
     'allow_undef'   => $l->{'allow_undef'},
     'materializer'  => $l->{'materializer'},
     'page_size'     => $l->{'page_size'},
     'display_pages' => $l->{'display_pages'},
     'limit'         => $l->{'limit'},
     'limit_pages'   => $l->{'limit_pages'},
     'limit_display' => $l->{'limit_display'},
    };

    return $args;
}

##############################################################################
# LOOK! REDEFINES shift, push, pop, unshift, splice, join

=head2 shift

=cut

sub shift
{
    my($l) = @_;

    my $element = $l->get_first;

    CORE::shift( @{$l->{'_OBJ'}} );
    if ( $l->{'_OBJ'} ne $l->{'_DATA'} )
    {
        CORE::shift( @{$l->{'_DATA'}} );
    }

    return $element;
}


##############################################################################

=head2 pop

=cut

sub pop
{
    my($l) = @_;

    my $element = $l->get_last;

    CORE::pop( @{$l->{'_OBJ'}} );
    if ( $l->{'_OBJ'} ne $l->{'_DATA'} )
    {
        CORE::pop( @{$l->{'_DATA'}} );
    }

    return $element;
}


##############################################################################

=head2 unshift

=cut

sub unshift
{
    my $l = CORE::shift(@_);

    $l->reset;
    CORE::unshift( @{$l->{'_DATA'}}, @_ );
    if ( $l->{'_OBJ'} ne $l->{'_DATA'} )
    {
        if ( my $mat = $l->{'materializer'} )
        {
            if ( $l->{'materialized'} > 0 )
            {
                # Insert undef values
                CORE::unshift( @{$l->{'_OBJ'}}, map{undef} @_ );

                my $objs = $l->{'_OBJ'};
                for ( my $i=0; $i<=$#_; $i++ )
                {
                    $objs->[$i] = &{$mat}( $l, $i );
                }
            }
        }
    }

    return scalar(@_);
}


##############################################################################

=head2 push

  $l->push( @elements )

Returns: The number of elements added

=cut

sub push
{
    my $l = CORE::shift(@_);

    $l->populate_all;
    my $pos = $l->max + 1;

    CORE::push( @{$l->{'_DATA'}}, @_ );
    if ( $l->{'_OBJ'} ne $l->{'_DATA'} )
    {
        if ( my $mat = $l->{'materializer'} )
        {
            if ( $l->{'materialized'} > 0 )
            {
                my $objs = $l->{'_OBJ'};
                my $max = $l->max;
                for ( my $i=$pos; $i<=$max; $i++ )
                {
                    $objs->[$i] = &{$mat}( $l, $i );
                }
            }
        }
        else
        {
            CORE::push( @{$l->{'_OBJ'}}, @_ );
        }
    }

    return scalar(@_);
}


##############################################################################

=head2 push_uniq

  $l->push_uniq( @elements )

Only add elements not already in the list

Returns: The number of elements added

=cut

sub push_uniq
{
    my $l = CORE::shift(@_);

    $l->materialize_all;
    my @new;

    while ( my $target = CORE::shift )
    {
        my $found=0;
        my( $value, $error ) = $l->get_first;
        while (! $error )
        {
            if ( $value eq $target )
            {
                $found++;
                last;
            }
        }
        continue
        {
            ( $value, $error ) = $l->get_next;
        }
        ;

        unless( $found )
        {
            CORE::push @new, $target;
        }
    }

    if ( @new )
    {
        $l->push( @new );
    }

    return scalar( @new );
}


##############################################################################

=head2 unshift_uniq

  $l->unshift_uniq( @elements )

Only add elements not already in the list

Returns: The number of elements added

=cut

sub unshift_uniq
{
    my $l = CORE::shift(@_);

    $l->materialize_all;
    my @new;

    while ( my $target = CORE::shift )
    {
        my $found=0;
        my( $value, $error ) = $l->get_first;
        while (! $error )
        {
            if ( $value eq $target )
            {
                $found++;
                last;
            }
        }
        continue
        {
            ( $value, $error ) = $l->get_next;
        }
        ;

        unless( $found )
        {
            CORE::push @new, $target;
        }
    }

    if ( @new )
    {
        $l->unshift( @new );
    }

    return scalar( @new );
}


##############################################################################

=head2 join

  $l->join()

  $l->join($separator)

C<$separator> defaults to the empty string.

Returns: A scalar string of all elements concatenated

Compatible with L<Template::Manual::VMethods/List Virtual Methods>

=cut

sub join
{
    my( $l, $sep ) = @_;

    $l->materialize_all;

    $sep ||= "";

    return CORE::join($sep, @{$l->{'_OBJ'}});
}


##############################################################################

=head2 complement

  $l->complement($l2)

Returns a list with the elements from $l not found in $l2

=cut

sub complement
{
    my( $l, $l2 ) = @_;
    my $class = ref $l;

#    debug "l2=".$l2;

    my %keys;
    my( $val2, $err2 ) = $l2->get_first;
    while (! $err2 )
    {
        $keys{$val2}++;
    }
    continue
    {
        ( $val2, $err2 ) = $l2->get_next;
    }
    $l2->reset;

#    debug datadump(\%keys,1);

    my @new;
    my( $val, $err ) = $l->get_first;
    while (! $err )
    {
#	debug "  looking at $val";
        next if $keys{$val};
#	debug "    added";
        CORE::push @new, $val;
    }
    continue
    {
        ( $val, $err ) = $l->get_next;
    }
    $l->reset;

    return $class->new(\@new, $l->clone_props);
}


##############################################################################

=head2 uniq

  $l->uniq()

Returns a list with multiple list items filtered out. Operates on the
unmaterialized items. If nothing filtered, returns the same object.

=cut

sub uniq
{
    my $l = CORE::shift(@_);

    my %seen;
    my @new;

    if ( $l->{'INDEX'} > -1 )
    {
        $l->reset;
    }

    my( $value, $error ) = $l->get_next_raw;
    while (! $error )
    {
        next if $seen{$value};
        $seen{$value} ++;
        CORE::push @new, $value;
    }
    continue
    {
        ( $value, $error ) = $l->get_next_raw;
    }
    ;

    if ( $#new < $l->max )
    {
        my $args = $l->clone_props;
        return $l->new(\@new, $args);
    }
    else
    {
        $l->reset;
        return $l;
    }
}


##############################################################################

=head2 merge

  $l->merge( $list2, $list3, ... )


Returns a list composed of zero or more other lists. The original
lists are not modified. Filters out parametrs that are not
lists. Always returns a new list, even if it has the same content as
the calling list.

Uses the cloned args of the calling list.

Compatible with L<Template::Manual::VMethods/List Virtual Methods>

=cut

sub merge
{
    my $l = CORE::shift(@_);
    my $args = $l->clone_props;

    # There are a couple of different possibilities. The lists could
    # have different materializers. But only materializers for
    # non-empty lists matter.

    my @new;
    my $materialize = 0;

    foreach my $l2 ( $l, @_ )
    {
        # First iteration compares args with itself
        unless( $materialize )
        {
            # If there are different materializers, materialize the
            # list we got so far and materialize the rest as we go
            # along.
            # TODO: test with lists with different materializers

            if ( my $mat2 = $l2->{'materializer'} )
            {
                if ( my $mat1 = $args->{'materializer'} )
                {
                    if ( $mat1 ne $mat2 )
                    {
                        $materialize = 1;
                        my $n = $l->new(\@new, $args);
                        my @objs = ();
                        for ( my $i=0; $i<=$#new; $i++ )
                        {
                            CORE::push @objs, &{$mat1}( $n, $i );
                        }
                        @new = @objs;
                        $args->{'materializer'} = undef;
                    }
                }
                else
                {
                    $args->{'materializer'} = $mat2;
                }
            }
        }

        if ( UNIVERSAL::isa($l2, 'Para::Frame::List' ) )
        {
            if ( $l2->{'INDEX'} > -1 )
            {
                $l2->reset;
            }

            if ( $materialize )
            {
                my( $value, $error ) = $l2->get_next;
                while (! $error )
                {
                    CORE::push @new, $value;
                }
                continue
                {
                    ( $value, $error ) = $l2->get_next;
                }
                ;
            }
            else
            {
                my( $value, $error ) = $l2->get_next_raw;
                while (! $error )
                {
                    CORE::push @new, $value;
                }
                continue
                {
                    ( $value, $error ) = $l2->get_next_raw;
                }
                ;
            }
        }
        elsif ( UNIVERSAL::isa($l2, 'ARRAY' ) )
        {
            CORE::push @new, @$l2;
        }
        # else ignore...
    }

    return $l->new(\@new, $args);
}


##############################################################################

=head2 reverse

  $l->reverse()


Returns a list composed of the items in reverse order.

Uses the cloend args of the calling list.

Compatible with L<Template::Manual::VMethods/List Virtual Methods>

=cut

sub reverse
{
    my $l = CORE::shift(@_);
    my $args = $l->clone_props;

    my @new;
    my @newobj;

    $l->populate_all;

    if ( $l->{'_OBJ'} eq $l->{'_DATA'} )
    {
        return $l->new([CORE::reverse @{$l->{'_OBJ'}}], $args);
    }
    elsif ( $l->{'materialized'} )
    {
        my $oidx = $#{$l->{'_OBJ'}};
        my $didx = $#{$l->{'_DATA'}};

        if ( $oidx != $didx )
        {
            for ( my $i=$oidx+1; $i <= $didx; $i++ )
            {
                $l->{'_OBJ'}[$i] = undef;
            }
        }

        my $new = $l->new([CORE::reverse @{$l->{'_DATA'}}], $args);
        $new->{'_OBJ'} = [ CORE::reverse @{$l->{'_OBJ'}} ];
        $new->{'materialized'} = $l->{'materialized'};
        return $new;
    }
    else
    {
        return $l->new([CORE::reverse @{$l->{'_DATA'}}], $args);
    }
}


##############################################################################

=head2 flatten

  $l->flatten()

Creates a new list with any list elements flatten to it's
elements. Recursively. Flattens L<Para::Frame::List> objs and
unblessed arrayrefs.

Always returns a new list object of the same class and with the same
properties.

TODO: Make this a materializer function, to handle large lists

=cut

sub flatten
{
    my( $list_in, $seen ) = @_;

    my @list_out;

    foreach my $elem ( @$list_in )
    {
        if ( ref $elem )
        {
            if ( UNIVERSAL::isa $elem, 'Para::Frame::List' )
            {
                CORE::push @list_out, $elem->flatten()->as_array;
            }
            elsif ( ref $elem eq 'ARRAY' )
            {
                CORE::push @list_out, @$elem;
            }
            else
            {
                CORE::push @list_out, $elem;
            }
        }
        else
        {
            CORE::push @list_out, $elem;
        }
    }

    return $list_in->new( \@list_out, $list_in->clone_props );
}


##############################################################################

=head2 sorted_on


=cut

sub sorted_on
{
    return $_[0]->{'sorted_on'};
}


##############################################################################

=head2 resort

  $list->resort( ... )

Same as L</sorted>, but modifies the existing object, rather than
creating a new object.

If no params given, the cgi params C<order> and C<direction> will be
used.

Will not resort if the object sortkey property is the same

Returns:

The same list object

=cut

sub resort
{
    my( $list, $sortargs, $dir ) = @_;

    unless( $list->size )
    {
        return $list->new_empty();
    }

    if ( my $q = $Para::Frame::REQ->q )
    {
        $sortargs ||= $q->param('order');
        unless( ref $sortargs )
        {
            $dir ||= $q->param('direction');
        }
    }

    my( $sort_str, $sort_key );
    ( $sortargs, $sort_str, $sort_key ) =
      $list->parse_sortargs( $sortargs, $dir );

#    debug "Resorting list ".Scalar::Util::refaddr($list);
#    debug "sort_key: $sort_key";
#    debug "prev key: ".($list->{'sorted_on_key'}||'');

    if ( $sort_key eq ($list->{'sorted_on_key'}||'') )
    {
        debug "SAME SORT";
        return $list;
    }

    my $new = $list->sorted($sortargs,
                            {
                             sort_str => $sort_str,
                             sort_key => $sort_key,
                             dir => $dir,
                            });

    $list->{'index'} = -1;
    $list->{'materialized'} = $new->{'materialized'};
    $list->{'materializer'} = $new->{'materializer'};
    $list->{'populated'}    = $new->{'populated'};
    $list->{'_DATA'}        = $new->{'_DATA'};
    $list->{'_OBJ'}         = $new->{'_OBJ'};
    $list->{'sorted_on'}    = $new->{'sorted_on'};
    $list->{'sorted_on_key'}= $new->{'sorted_on_key'};

    return $list;
}


##############################################################################

=head2 sysdesig

  $l->sysdesig

Return a SCALAR string with the elements sysdesignation concatenated with
C<' / '>.

=cut

sub sysdesig
{
#    warn "Stringifies object ".ref($_[0])."\n"; ### DEBUG
    return CORE::join ' / ', map
    {
        UNIVERSAL::can($_, 'sysdesig') ?
            $_->sysdesig($_[1]) :
              $_;
    } $_[0]->as_array;
}


##############################################################################

=head2 sum

  $l->sum

=cut

sub sum
{
    my( $l ) = @_;
    my $sum = 0;
    my( $val, $err ) = $l->get_first;
    while (! $err )
    {
        unless( looks_like_number $val )
        {
            die "Tried to sum with value $val";
        }
        $sum += $val;
    }
    continue
    {
        ( $val, $err ) = $l->get_next;
    }

    return $sum;
}


##############################################################################

=head2 sorted

  $list->sorted()

  $list->sorted( $attr )

  $list->sorted( $attr, $dir, $type )

  $list->sorted( [$attr1, $attr2, ...] )

  $list->sorted( [$attr1, $attr2, ...], $dir, $type )

  $list->sorted( { on => $attr, dir => $dir, type => $type } )

  $list->sorted( [{ on => $attr1, dir => $dir1, type => $type1 },
                  { on => $attr2, dir => $dir2, type => $type2 },
                  ...
                 ] )

Returns a list of object, sorted by the selected proprty of the
object.

This method assumes that the list only contains objects and that all
of them has a similar interface.

The default sorting attribute is the stringification of the object (or
the string itself if it's not an object).

C<$dir> is the direction of the sort.  It can be C<asc> or C<desc>.

C<$attr> can be of the form C<a1.a2.a3> which translates to an attribute
lookup in several steps.  For example; C<$list->sorted('email.host')>

The sorting will be done as strings with <cmp>. You can get a string
sort by using C<$type numeric>.

Examples:

Loop over the name arcs of a node, sorted by firstly on the is_of_language
code and secondly on the weight in reverse order:

  [% FOREACH arc IN n.arc_list('name').sorted(['obj.is_of_language.code',{on='obj.weight' dir='desc'}]) %]

Returns:

A List object with 0 or more elements.

Exceptions:

Dies if given faulty parameters.

=cut

#sub sorted
#{
#    my( $list, $sortargs, $dir ) = @_;
#
#    my $DEBUG = 0;
#
#    my $args = {};
#
#    $sortargs ||= 'desig';
#
#    unless( ref $sortargs and ( ref $sortargs eq 'ARRAY' or
#			    ref $sortargs eq 'Rit::Base::List' )
#	  )
#    {
#	$sortargs = [ $sortargs ];
#    }
#
#    if( $dir )
#    {
#	unless( $dir =~ /^(asc|desc)$/ )
#	{
#	    die "direction '$dir' out of bound";
#	}
#
#	for( my $i = 0; $i < @$sortargs; $i++ )
#	{
#	    unless( ref $sortargs->[$i] eq 'HASH' )
#	    {
#		$sortargs->[$i] =
#		{
#		 on => $sortargs->[$i],
#		 dir => $dir,
#		};
#	    }
#	}
#    }
#
#    $list->materialize_all; # for sorting on props
#
#    my @sort;
#    for( my $i = 0; $i < @$sortargs; $i++ )
#    {
##	debug "i: $i";
##	debug sprintf("sortargs: %d\n", scalar @$sortargs);
#	unless( ref $sortargs->[$i] eq 'HASH' )
#	{
#	    $sortargs->[$i] =
#	    {
#		on => $sortargs->[$i],
#	    };
#	}
#
#	$sortargs->[$i]->{'dir'} ||= 'asc';
#
#	# Find out if we should do a numeric or literal sort
#	#
#	my $on =  $sortargs->[$i]->{'on'};
#	if( ref $on )
#	{
#	    die "not implemented ($on)";
#	}
#	$on =~ /([^\.]+)$/; #match last part
#	my $pred_str = $1;
#	my $cmp = 'cmp';
#
#	# Silently ignore dynamic props (that isn't preds)
#	if( my $pred = Rit::Base::Pred->find_by_anything( $pred_str,
#						       {
#							%$args,
#							return_single_value=>1,
#						       }))
#	{
#	    my $coltype = $pred->coltype;
#	    $sortargs->[$i]->{'coltype'} = $coltype;
#
#	    if( ($coltype eq 'valfloat') or ($coltype eq 'valdate') )
#	    {
#		$cmp = '<=>';
#	    }
#	}
#
#	$sortargs->[$i]->{'cmp'} = $cmp;
#
#	if( $sortargs->[$i]->{'dir'} eq 'desc')
#	{
##	    push @sort, "\$b->[$i] cmp \$a->[$i]";
#	    push @sort, "\$props[$i][\$b] $cmp \$props[$i][\$a]";
#	}
#	else
#	{
##	    push @sort, "\$a->[$i] cmp \$b->[$i]";
#	    push @sort, "\$props[$i][\$a] $cmp \$props[$i][\$b]";
#	}
#    }
#    my $sort_str = join ' || ', @sort;
#
##    debug "--- SORTING: $sort_str";
#
#    my @props;
#    foreach my $item ( $list->as_array )
#    {
##	debug 2, sprintf("  add item %s", $item->sysdesig);
#	for( my $i=0; $i<@$sortargs; $i++ )
#	{
#	    my $method = $sortargs->[$i]{'on'};
##	    debug sprintf("    arg $i: %s", $sortargs->[$i]{'on'});
#	    my $val = $item;
#	    foreach my $part ( split /\./, $method )
#	    {
#		$val = $val->$part;
##		debug sprintf("      -> %s", $val);
#	    }
#
#	    my $coltype = $sortargs->[$i]->{'coltype'} || '';
#	    if( $coltype eq 'valfloat' )
#	    {
#		if( UNIVERSAL::isa $val, 'Rit::Base::List' )
#		{
#		    $val = List::Util::min( $val->as_array );
#		}
#
#		# Make it an integer
#		$val ||= 0;
#	    }
#	    elsif( $coltype eq 'valdate' )
#	    {
#		if( UNIVERSAL::isa $val, 'Rit::Base::List' )
#		{
#		    $val = List::Util::min( $val->as_array );
#		}
#
#		# Infinite future date
#		use DateTime::Infinite;
#		$val ||= DateTime::Infinite::Future->new;
#		#debug "Date value is $val";
#	    }
#	    elsif( $coltype eq 'valtext' )
#	    {
#		if( UNIVERSAL::isa $val, 'Rit::Base::List' )
#		{
#		    $val = $val->loc;
#		}
#
#		$val ||= '';
#	    }
#
##	    debug sprintf("      => %s", $val);
#
#	    push @{$props[$i]}, $val;
##	    push @{$props[$i]}, $item->$method;
#	}
#    }
#
#    if( debug>2 )
#    {
#	debug "And the props is: \n";
#	for( my $i=0; $i<=$#$list; $i++ )
#	{
#	    my $out = "  ".$list->[$i]->desig.": ";
#	    for( my $x=0; $x<=$#props; $x++ )
#	    {
#		$out .= $props[$x][$i] .' - ';
#	    }
#	    debug $out;
#	}
#    }
#
#    # The Schwartzian transform:
#    # This method should be fast and efficient. Read up on it
#    my @new = @{$list}[ eval qq{ sort { $sort_str } 0..$#$list } ];
#    die "Sort error for '$sort_str': $@" if $@; ### DEBUG
#
#    return $list->new( \@new );
#}
#
##############################################################################

=head1 AUTOLOAD

  $l->$method( @args )


=cut

AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
    my $method = $AUTOLOAD;
    my $l = CORE::shift;

    $l->materialize_all;

    my @templist = ();
    foreach my $elem ( @{$l->{'_OBJ'}} )
    {
        next unless $elem;
        my $res = $elem->$method(@_);
        if ( UNIVERSAL::isa( $res, 'Para::Frame::List' ) )
        {
            CORE::push @templist, $res->as_array;
        }
        else
        {
            CORE::push @templist, $res;
        }
    }

    return $l->new(\@templist);
}


##############################################################################

  1;

=head1 SEE ALSO

L<Para::Frame>, L<DBI>

=cut
