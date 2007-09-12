#  $Id$  -*-cperl-*-
package Para::Frame::Renderer::Custom;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Custom Renderer
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Renderer::Custom - Present custom pages

=cut

use strict;
use Carp qw( confess );
#use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );

#######################################################################


# TODO: differ RENDERING from SENDING


=head2 new

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    $args ||= {};

    my $rend = bless
    {
     'content'        => undef,
    }, $class;

    my $content = $args->{'content'} ||= \ "";
    unless( UNIVERSAL::isa($content, 'SCALAR') )
    {
	confess "Content param must be a scalar ref";
    }

    $rend->{'content'} = $content;

    return $rend;
}


#######################################################################

=head2 render_output

  $resp->render_output()

Burns the page and stores the result.

If the rendering failes, may change the template and URL. The new URL
can be used for another call to this method.

This method is called by L<Para::Frame::Request/after_jobs>.

Returns: the self, as a sender object

=cut

sub render_output
{
    my( $rend ) = @_;

    return $rend;
}

#######################################################################

=head2 set_ctype

  $rend->set_ctype( $ctype )

Defaults to C<text/html> and charset C<UTF-8>

=cut

sub set_ctype
{
    $_[1]->set("text/plain; charset=UTF-8");
}

#######################################################################


1;

=head1 SEE ALSO

L<Para::Frame>

=cut

