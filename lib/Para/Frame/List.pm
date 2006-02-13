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


#########################################################################
################################  Constructors  #########################

=head2 Constructors

These can be called with the class name or any List object.

=cut

#######################################################################

=head3 new

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


#########################################################################
################################  Accessors  ############################

=head2 Accessors

=cut

#######################################################################

=head2 from_page

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
	delete $session->{list}{$id - 1};

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

=cut

sub id
{
    my( $l ) = @_;

    my $obj = $OBJ{$l};

    return $obj->{'stored_id'};
}

#######################################################################

=head2 pages

=cut

sub pages
{
    my( $l ) = @_;

    my $obj = $OBJ{$l};

    return int( (scalar(@$l) - 1) / $obj->{page_size} ) + 1;
}

#######################################################################

=head2 pagelist

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
#	$out .= "Först";
    }
    else
    {
	$out .= forward("<", $me, {use_cached=>$id, page => ($pagenum-1), href_class=>"paraframe_previous"});
#	$out .= forward("Först", $me, {use_cached=>$id, page => 1});
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

=cut

sub page_size
{
    return $OBJ{$_[0]}{page_size};
}


######################################################################

=head2 set_page_size

=cut

sub set_page_size
{
    return $OBJ{$_[0]}{page_size} = $_[1];
}


#######################################################################

=head2 display_pages

=cut

sub display_pages
{
    return $OBJ{$_[0]}{display_pages};
}


#######################################################################

=head2 display_pages

=cut

sub set_display_pages
{
    return $OBJ{$_[0]}{display_pages} = $_[1];
}


#######################################################################

=head2 defined

Yes.

=cut

sub defined {1}


#######################################################################

=head3 sth

=cut

sub sth
{
    return $OBJ{$_[0]}{sth};
}

#######################################################################

=head3 as_string

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

=head3 size

=cut

sub size
{
#    my $size = scalar @{$_[0]};
#    warn "Size is $size\n";
#    return $size;

    return scalar @{$_[0]};
}

#######################################################################

=head3 limit

  $list->limit()

  $list->limit( $limit )

  $list->limit( 0 )

Limit the number of elements in the list. Returns the first C<$limit>
items.

Default C<$limit> is 10.  Set the limit to 0 to get all items.

=head4 Returns

A List with the first C<$limit> items.

=cut

sub limit
{
    my( $list, $limit ) = @_;

    $limit = 10 unless defined $limit;
    return $list if $limit < 1;
    return $list if $list->size <= $limit;
    return $list->new( [@{$list}[0..($limit-1)]] );
}

#########################################################################
################################  Public methods  #######################


=head2 Public methods

=cut


#######################################################################

=head3 contains

  $list->contains( $node )

  $list->contains( $list2 )


Returns true if the list contains all mentioned items supplied as a
list, list objekt or single item.

=cut

sub contains
{
    my( $list, $tmpl ) = @_;

    if( ref $tmpl )
    {
	if( ref $tmpl eq 'Rit::Base::List' )
	{
	    foreach my $val (@{$tmpl->as_list})
	    {
		return 0 unless $list->contains($val);
	    }
	    return 1;
	}
	elsif( ref $tmpl eq 'ARRAY' )
	{
	    foreach my $val (@$tmpl )
	    {
		return 0 unless $list->equals($val);
	    }
	    return 1;
	}
	elsif( ref $tmpl eq 'HASH' )
	{
	    die "Not implemented: $tmpl";
	}
    }

    # Default for simple values and objects:

    foreach my $node ( @{$list->as_list} )
    {
	return $node if $node->equals($tmpl);
    }
    return undef;
}


#######################################################################

=head3 contains_any_of

  $list->contains_any_of( $node )

  $list->contains_any_of( $list2 )


Returns true if the list contains at least one of the mentioned items
supplied as a list, list objekt or single item.

=cut

sub contains_any_of
{
    my( $list, $tmpl ) = @_;

    my $DEBUG = 0;

    if( debug > 1 )
    {
	debug "Checking list with content:";
	foreach my $node ( $list->nodes )
	{
	    debug sprintf "  * %s", $node->sysdesig;
	}
    }

    if( ref $tmpl )
    {
	if( ref $tmpl eq 'Rit::Base::List' )
	{
	    foreach my $val (@{$tmpl->as_list})
	    {
		debug 2, sprintf "  check list item %s", $val->sysdesig;
		return 1 if $list->contains_any_of($val);
	    }
	    debug 2, "    failed";
	    return 0;
	}
	elsif( ref $tmpl eq 'ARRAY' )
	{
	    foreach my $val (@$tmpl )
	    {
		debug 2, sprintf "  check array item %s", $val->sysdesig;
		return 1 if $list->contains_any_of($val);
	    }
	    debug 2, "    failed";
	    return 0;
	}
	elsif( ref $tmpl eq 'HASH' )
	{
	    die "Not implemented: $tmpl";
	}
    }

    # Default for simple values and objects:

    foreach my $node ( @{$list->as_list} )
    {
	debug 2, sprintf "  check node %s", $node->sysdesig;
	debug 2, sprintf "  against %s", $tmpl->sysdesig;
	return $node if $node->equals($tmpl);
    }
    debug 2,"    failed";
    return undef;
}


#######################################################################

=head3 has_value

=cut

# TODO: Shouldn't this do the same as Node->has_value() ???

sub has_value
{
    shift->find({value=>shift});
}

#######################################################################

=head3 as_list

Returns a referens to a list. Not a List object. The list content are
materialized.

=cut

sub as_list
{
    # As decribed in Template::Iterator for use in FOREACH

#    warn "List is $_[0]\n"; ### THIS WILL RECUSE TO DEATH

#    confess $_[0] unless ref $_[0] eq 'Rit::Base::List';

    my @list;

    # Object can contain nodes or id's of nodes
    if( ref $_[0]->[0] )
    {
	@list = @{$_[0]};
	return \@list;
    }

    # Materialize
    foreach my $id ( @{$_[0]} )
    {
#	unless( $id =~ /^\d+$/ )
#	{
#	    die Dumper @_;
#	}
	push @list, Rit::Base::Node->get( $id );
    }
#    warn "Returning list: @list\n";
    return \@list;
}

#######################################################################

=head3 desig

Return a SCALAR string with the elements designation concatenated with
C<' / '>.

=cut

sub desig
{
#    warn "Stringifies object ".ref($_[0])."\n"; ### DEBUG
    return join ' / ', map $_->desig, $_[0]->nodes;
}

######################################################################

=head2 is_list

This is not a list.

=head3 Returns

0

=cut

sub is_list
{
    return 1;
}


#######################################################################

=head3 first

=cut

sub first
{
    return $_[0][0];
}

#########################################################################
################################  Private methods  ######################

sub flatten_list
{
    my( $list_in, $seen ) = @_;

    $list_in  ||= [];
    $seen     ||= {};

    my @list_out;

    foreach my $elem ( @$list_in )
    {
	if( ref $elem )
	{
	    if( ref $elem eq 'Rit::Base::List' )
	    {
		push @list_out, @{ flatten_list($elem, $seen) };
	    }
	    else
	    {
		unless( $seen->{ $elem->syskey } ++ )
		{
		    push @list_out, $elem;
		}
	    }
	}
	else
	{
	    unless( $seen->{ $elem } ++ )
	    {
		push @list_out, $elem;
	    }
	}
    }
    return \@list_out;
}

1;

=head1 SEE ALSO

L<Para::Frame>, L<DBI>

=cut
