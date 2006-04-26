#  $Id$  -*-perl-*-
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
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::List - Methods for list manipulation

=cut

use strict;
use Carp qw( carp croak shortmess confess );
use Data::Dumper;
use List::Util;
use Template::Constants;


BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug timediff package_to_module );
use Para::Frame::Widget qw( forward );

our %OBJ; # Store obj info

use base qw( Template::Iterator );

=head2 DESCRIPTION

The object is a ref to the list it contains. All list operations can
be used as usual. Example:

  my $l = Para::Frame::List->new( \@biglist );
  my $first_element = $l->[0];
  my $last_element = pop @$l;

The iteration methods is compatible with L<Template::Iterator>. The
iterator status codes are taken from L<Template::Constants>.

NB! The method max 

The object also has the following methods.

=cut

#######################################################################

=head2 new

  $l = Para::Frame::List->new( \@list )

  $l = Para::Frame::List->new( \@list, \%params )

Availible params are:

  page_size      (default is 20 )
  display_pages  (default is 10 )

Extra info about the object is stored in a class variable. Objects
returned from a hash has to be recreated to register the object in the
class variable. This will reset all the metadata.

  $l = Para::Frame::List->new( $l )

=cut

sub new
{
    my( $this, $listref, $p ) = @_;
    my $class = ref($this) || $this;

    $listref ||= [];

    if( UNIVERSAL::isa($listref, "Para::Frame::List") )
    {
	# For recreating an object returned from a fork
	return $listref if $OBJ{$listref};
    }

    # Removes other things like overload
    unless( ref $listref eq 'ARRAY' )
    {
	unless( UNIVERSAL::isa($listref, "ARRAY") )
	{
	    my $type = ref $listref;
	    die "$type is not an array ref";
	}

	$listref = [@$listref];
    }

    my $l = bless $listref, $class;

    debug 3, "Adding list obj $l";

    $p ||= {};

    $p->{page_size} ||= 20;
    $p->{display_pages} ||= 10;

    $OBJ{$l} = $p;

    $l->init;

    return $l;
}

sub DESTROY
{
    my( $l ) = @_;

    debug 3, "Removing list obj $l";
    delete $OBJ{$l};

    return 1;
}


#######################################################################

=head2 init

  $l->init

Called by L</new> for additional initializing. Subclasses can use this
for filling the list with data or adding more properties. The object
is an array ref of the actual list. All other properties resides in
$Para::Frame::List::OBJ{$l}

=cut

sub init
{
    # Reimplement this
}


#######################################################################

=head2 hashref

  $l->hashref

Returns $Para::Frame::List::OBJ{$l}

=cut

sub hashref
{
    return $OBJ{$_[0]};
}


#######################################################################

=head2 as_list

  $l->as_list

Same as $l in itself, except that it returns a list rather than a listref if wantarray.

=cut

sub as_list
{
    return wantarray ? @{$_[0]} : $_[0];
}


#######################################################################

=head2 from_page

  $l->from_page( $pagenum )
  $l->from_page

Returns a ref to a list of elements corresponding to the given
C<$page> based on the L</page_size>. If no C<$pagenum>
is given, takes the value from query param table_page or 1.

=cut

sub from_page
{
    my( $l, $page ) = @_;

    $page ||= $Para::Frame::REQ->q->param('table_page') || 1;

#    @pagelist = ();

    my $obj = $OBJ{$l};

    if( $obj->{page_size} < 1 )
    {
	return $l;
    }

    my $start = $obj->{page_size} * ($page-1);
    my $end = List::Util::min( $start + $obj->{page_size}, scalar(@$l))-1;

    debug 2, "From $start to $end";

    return [ @{$l}[$start..$end] ];

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

    my $obj = $OBJ{$l};

    unless( $obj->{'stored_id'} )
    {
	my $session =  $Para::Frame::REQ->user->session;
	my $id = $session->{'listid'} ++;

	# Remove previous from cache
	if( my $prev = delete $session->{list}{$id - 1} )
	{
#	    debug "Removed $prev (".($id-1).")";
	}

	$obj->{'stored_id'} = $id;
	$obj->{stored_time} = time;
#	$obj->{expire_time} = time + 60*5;

	$session->{list}{$id} = $l;

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

    my $obj = $OBJ{$l};

    return $obj->{'stored_id'};
}

#######################################################################

=head2 pages

  $l->pages

Returns the number of pages this list will take given L</page_size>.

=cut

sub pages
{
    my( $l ) = @_;

    my $obj = $OBJ{$l};

    if( $obj->{page_size} < 1 )
    {
	return 1;
    }

    return int( (scalar(@$l) - 1) / $obj->{page_size} ) + 1;
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

    my $obj = $OBJ{$l};

#    debug "Creating pagelist for $l";

    my $dpages = $obj->{display_pages};
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
    my $me = $page->url_path_full;

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
    return $OBJ{$_[0]}{page_size};
}


######################################################################

=head2 set_page_size

  $l->set_page_size( $page_size )

Sets and returns the given C<$page_size>

=cut

sub set_page_size
{
    $OBJ{$_[0]}{page_size} = int($_[1]);
    return "";
}


#######################################################################

=head2 display_pages

  $l->display_pages

Returns how many pages that should be listed by L</pagelist>.

=cut

sub display_pages
{
    return $OBJ{$_[0]}{display_pages};
}


#######################################################################

=head2 display_pages

Sets and returns the given L</display_pages>.

=cut

sub set_display_pages
{
    $OBJ{$_[0]}{display_pages} = int($_[1]);
    return "";
}


#######################################################################

=head2 sth

=cut

sub sth
{
    return $OBJ{$_[0]}{sth};
}

#######################################################################

=head2 as_string

  $l->as_string

Returns a string representation of the list. Using C<as_string> for
elements that isn't plain scalars.

=cut

sub as_string
{
    my ($self) = @_;

    unless( ref $self )
    {
#	warn "  returning $self\n";
	return $self;
    }

    my $list = $self->as_list;

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
	if( ref $self->[0] )
	{
	    $val .= $self->[0]->as_string;
	}
	else
	{
	    $val .= $self->[0];
	}
    }

    return $val;
}


#######################################################################

=head2 size

  $l->size

Returns the number of elements in this list.

=cut

sub size
{
#    my $size = scalar @{$_[0]};
#    warn "Size is $size\n";
#    return $size;

    return scalar @{$_[0]};
}

#######################################################################

=head2 limit

  $l->limit()

  $l->limit( $limit )

  $l->limit( 0 )

Limit the number of elements in the list. Returns the first C<$limit>
items.

Default C<$limit> is 10.  Set the limit to 0 to get all items.

Returns: A List with the first C<$limit> items.

=cut

sub limit
{
    my( $list, $limit ) = @_;

    $limit = 10 unless defined $limit;
    return $list if $limit < 1;
    return $list if $list->size <= $limit;
    return $list->new( [@{$list}[0..($limit-1)]] );
}


#######################################################################

=head2 get_first

  $l->get_first

Initialises the object for iterating through the target data set.  The
first record is returned, if defined, along with the STATUS_OK value.
If there is no target data, or the data is an empty set, then undef
is returned with the STATUS_DONE value.

=cut

sub get_first
{
    my( $l ) = @_;
    my $obj = $OBJ{$l};

    my $size = scalar @$l;
    my $index = 0;

    return (undef, Template::Constants::STATUS_DONE) unless $size;

    # initialise various counters, flags, etc.
    @$obj{ qw( SIZE INDEX COUNT FIRST LAST ) }
      = ( $size, $index, 1, 1, $size > 1 ? 0 : 1, undef );
    @$obj{ qw( PREV NEXT ) } = ( undef, $l->[ $index + 1 ]);

    return $l->[ $index ];
}



#######################################################################

=head2 get_next

  $l->get_next

Called repeatedly to access successive elements in the data set.
Should only be called after calling get_first() or a warning will
be raised and (undef, STATUS_DONE) returned.

=cut

sub get_next
{
    my( $l ) = @_;
    my $obj = $OBJ{$l};

    my( $index ) = $obj->{INDEX};

    # warn about incorrect usage
    unless( defined $index )
    {
        my ($pack, $file, $line) = caller();
        warn("iterator get_next() called before get_first() at $file line $line\n");
        return( undef, Template::Constants::STATUS_DONE );   ## RETURN ##
    }

    # if there's still some data to go...
    if( $index < $#$l )
    {
        # update counters and flags
        $index++;
        @$obj{ qw( INDEX COUNT FIRST LAST ) }
	  = ( $index, $index + 1, 0, $index == $#$l ? 1 : 0 );
        @$obj{ qw( PREV NEXT ) } = @$l[ $index - 1, $index + 1 ];
        return $l->[ $index ];                           ## RETURN ##
    }
    else
    {
        return (undef, Template::Constants::STATUS_DONE);   ## RETURN ##
    }
}


#######################################################################

=head2 get_all

  $l->get_all

Method which returns all remaining items in the iterator as a Perl list
reference.  May be called at any time in the life-cycle of the iterator.
The get_first() method will be called automatically if necessary, and
then subsequent get_next() calls are made, storing each returned
result until the list is exhausted.

=cut

sub get_all
{
    my( $l ) = @_;
    my $obj = $OBJ{$l};

    my($index) = $obj->{INDEX}||0;
    my @data;

    debug "get_all - index $index max $#$l";

    # if there's still some data to go...
    if ($index < $#$l)
    {
        $index++;
        @data = @{ $l }[ $index..$#$l ];

        # update counters and flags
        @$obj{ qw( INDEX COUNT FIRST LAST ) }
	  = ( $#$l, $#$l + 1, 0, 1 );

        return \@data;                                      ## RETURN ##
    }
    else
    {
        return (undef, Template::Constants::STATUS_DONE);   ## RETURN ##
    }
}



#######################################################################

=head2 max

  $l->max

Returns the maximum index number (i.e. the index of the last element)
which is equivalent to size() - 1.

=cut

sub max
{
    my( $l ) = @_;

    return $#$l;
}



#######################################################################

=head2 index

  $l->index

Returns the current index number which is in the range 0 to max().

=cut

sub index
{
    return $OBJ{$_[0]}{INDEX};
}



#######################################################################

=head2 count

  $l->count

Returns the current iteration count in the range 1 to size().  This is
equivalent to index() + 1.

=cut

sub count
{
    return $OBJ{$_[0]}{COUNT};
}


#######################################################################

=head2 first

  $l->first

Returns a boolean value to indicate if the iterator is currently on
the first iteration of the set.

=cut

sub first
{
    return $OBJ{$_[0]}{FIRST};
}

#######################################################################

=head2 last

  $l->last

Returns a boolean value to indicate if the iterator is currently on
the last iteration of the set.

=cut

sub last
{
    return $OBJ{$_[0]}{LAST};
}

#######################################################################

=head2 prev

  $l->prev

Returns the previous item in the data set, or undef if the iterator is
on the first item.

=cut

sub prev
{
    return $OBJ{$_[0]}{PREV};
}

#######################################################################

=head2 next

  $l->next

Returns the next item in the data set or undef if the iterator is on
the last item.

=cut

sub next
{
    return $OBJ{$_[0]}{NEXT};
}



our$AUTOLOAD;
sub AUTOLOAD
{
    my $list = shift;
    my $item = $AUTOLOAD;
    $item =~ s/.*:://;
    return if $item eq 'DESTROY';

    if( $item =~ /^\d+$/ )
    {
	return $list->[$item];
    }

    confess("Method $item not recognized");
}



1;

=head1 SEE ALSO

L<Para::Frame>, L<DBI>

=cut
