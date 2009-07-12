package Para::Frame::Renderer::Static;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Renderer::Static - Renders a Static page

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( croak confess cluck );
use Template::Exception;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch );
use Para::Frame::L10N qw( loc );
use Scalar::Util qw(weaken);


# Used in set_ctype. Defaults to given ctype and charset UTF-8
our %TYPEMAP =
  (
   'html' =>
   {
    type => 'text/html',
   },
  );


##############################################################################

=head1 Constructors

=cut

##############################################################################

=head2 new

  Para::Frame::Renderer::TT->new( \%args )

args:

  umask
  page
  template
  template_root

C<template_root> is the root of the template used, if not the site
root.  Include files will be search for between the root and the
template dir.

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    $args ||= {};

    my $rend = bless
    {
     'page'           => undef,
    };


    my $page = $rend->{'page'} = $args->{'page'}
      or confess "page param missing";

    debug "=======> Created renderer for page ".$page->url_path;

    return $rend;
}


##############################################################################

=head2 render_output

  $p->render_output()

Burns the page and stores the result.

If the rendering failes, may change the template and URL. The new URL
can be used for another call to this method.

This method is called by L<Para::Frame::Request/after_jobs>.

Returns:

  True on success (the content as a scalar-ref or sender object)

  False on failure

=cut

sub render_output
{
    my( $rend ) = @_;

#    # Maby we have a page generated already
#    return 1 if $resp->{'content'};

#    # Don't burn if this is a HEAD request
#    return 1 if $req->header_only;

    my $out = "";
    my $outref = \$out;

    ### Output page
    my $page = $rend->page;
    unless( $page )
    {
	confess "No page ".datadump($rend,2);
    }


    debug "Getting '$page' as a static page";
    $rend->get_static( $page, $outref ) or return 0;

    return $outref;
}



##############################################################################

=head2 get_static

  $rend->get_static( $in, $pageref )

C<$pageref> must be a scalar ref.

C<$in> must be a L<IO::File> or a filename to be sent to
L<IO::File/new>.

Places the content of the file in C<$pageref>.

Returns: C<$pageref>

=cut

sub get_static
{
    my( $page, $in, $pageref ) = @_;

    $pageref or die "No pageref given";
    my $out = "";

    unless( ref $in )
    {
	$in = IO::File->new( $in );
    }


    if( ref $in eq 'IO::File' )
    {
	$out .= $_ while <$in>;
    }
    else
    {
	warn "in: $in\n";
	die "What can I do";
    }

    my $length = length($out);
    debug "Returning page with $length bytes";

    # Use the same scalar thingy
    return $$pageref = $out;
}


##############################################################################

=head2 page

=cut

sub page
{
    return $_[0]->{'page'};
}


##############################################################################

=head2 set_ctype

=cut

sub set_ctype
{
    my( $rend, $ctype ) = @_;

    my $page = $rend->page;
    if( my $ext = $page->suffix )
    {
	$ext =~ s/_tt$//; # Use the destination ext

#	debug "  ext $ext";
	my( $type, $charset );
	if( my $def = $TYPEMAP{ $ext } )
	{
	    $type = $def->{'type'};
	    $charset = $def->{'charset'};
#	    debug "  type $type";
#	    debug "  charset $charset";
	}

	$charset ||= $ctype->charset || 'UTF-8';

	# Will keep previous value if non given here
	if( $type )
	{
	    $ctype->set_type($type);
	}

	$ctype->set_charset($charset);
    }

    return $ctype;
}

##############################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    my( $rend ) = @_;

    return datadump($rend,2);
}

##############################################################################


1;

=head1 SEE ALSO

L<Para::Frame>

=cut
