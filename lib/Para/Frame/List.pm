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
use Carp qw( carp croak shortmess );
use Data::Dumper;
use List::Util qw( min max );

use base qw( Tie::Array );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug timediff package_to_module );
use Para::Frame::Widget qw( forward );

our %OBJ; # Store obj info


=head2 DESCRIPTION

The object is a ref to the list it contains. All list operations can
be used as usual. Example:

  my $l = Para::Frame::List->new( \@biglist );
  my $first_element = $l->[0];
  my $last_element = pop @$l;

The object also has the following methods.

=cut

#######################################################################

=head2 new

  $l = Para::Frame::List->new( \@list )

  $l = Para::Frame::List->new( \@list, \%params )

Availible params are:

  page_size      (default is 20 )
  display_pages  (default is 10 )

=cut

sub new
{
    my( $this, $listref, $p ) = @_;
    my $class = ref($this) || $this;

    $listref ||= [];

    my $l = bless $listref, $class;

    debug "Adding list obj $l";

    $p ||= {};

    $p->{page_size} ||= 20;
    $p->{display_pages} ||= 10;

    $OBJ{$l} = $p;

    return $l;
}

sub DESTROY
{
    my( $l ) = @_;

    debug "Removing list obj $l";
    delete $OBJ{$l};

    return 1;
}


#######################################################################

=head2 from_page

  $l->from_page( $pagenum )

Returns a ref to a list of elements corresponding to the given
C<$page> based on the L</page_size>.

=cut

sub from_page
{
    my( $l, $page ) = @_;

    $page ||= 1;

#    @pagelist = ();

    my $obj = $OBJ{$l};

    my $start = $obj->{page_size} * ($page-1);
    my $end = min( $start + $obj->{page_size} - 1, scalar(@$l));

    return [ @{$l}[$start..$end] ];

}

#######################################################################

=head2 store

  $l->store

Stores the object in the session for later retrieval by
L<Para::Frame::Session/list)

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

    return int( (scalar(@$l) - 1) / $obj->{page_size} ) + 1;
}

#######################################################################

=head2 pagelist

  $l->pagelist( $pagenum )

Returns a widget for navigating between the pages.

Example:

  [% USE Sorted_table('created','desc') %]
  [% usertable = cached_select_list("from users order by $order $direction") %]
  <table>
    <tr>
      <th>[% sort("Skapad",'created','desc') %]</th>
      <th>[% sort("Namn",'username') %]</th>
    </tr>
    <tr><th colspan="2">[% usertable.size %] users</th></tr>
    <tr><th colspan="2"> [% usertable.pagelist(page) %]</th></tr>
  [% FOREACH user IN usertable %]
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

    $pagenum ||= 1;

    my $obj = $OBJ{$l};

    debug "Creating pagelist for $l";

    my $dpages = $obj->{display_pages};
    my $pages = $l->pages;

    my $startpage = max( $pagenum - $dpages/2, 1);
    my $endpage = min( $pages, $startpage + $dpages - 1);

    my $id = $l->id;

    my $req = $Para::Frame::REQ;
    my $page = $req->page;
    my $me = $page->url_path_full;

    my $out = "<span class=\"paraframe_pagelist\">";

    if( $pagenum == 1 )
    {
#	$out .= "F�rst";
    }
    else
    {
	$out .= forward("<", $me, {use_cached=>$id, page => ($pagenum-1), href_class=>"paraframe_previous"});
#	$out .= forward("F�rst", $me, {use_cached=>$id, page => 1});
	$out .= " ";
    }

    if( $startpage != 1 )
    {
	$out .= forward(1, $me, {use_cached=>$id, page => 1});
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
	    $out .= forward($p, $me, {use_cached=>$id, page => $p});
	}
    }

    if( $endpage != $pages )
    {
	$out .= " ... ";
	$out .= forward($pages, $me, {use_cached=>$id, page => $pages});
    }

    if( $pagenum == $pages )
    {
#	$out .= "  Sist";
    }
    else
    {
	$out .= " ";
#	$out .= forward("Sist", $me, {use_cached=>$id, page => $pages});
	$out .= forward(">", $me, {use_cached=>$id, page => ($pagenum+1), href_class=>"paraframe_next"});
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
    return $OBJ{$_[0]}{page_size} = $_[1];
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
    return $OBJ{$_[0]}{display_pages} = $_[1];
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


1;

=head1 SEE ALSO

L<Para::Frame>, L<DBI>

=cut