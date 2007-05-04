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
    };

    my $content = $args->{'content'};
    unless( UNIVERSAL::isa($content, 'SCALAR') )
    {
	confess "Content param must be a scalar ref";
    }

    $rend->{'content'} = $content;

    return $rend;
}


#######################################################################

=head2 render_output

  $p->render_output( $outref )

Burns the page and stores the result.

If the rendering failes, may change the template and URL. The new URL
can be used for another call to this method.

This method is called by L<Para::Frame::Request/after_jobs>.

Returns: True on success and 0 on failure

=cut

sub render_output
{
    my( $rend, $outref ) = @_;

    $$outref = ${$rend->{'content'}};

    return 1;
}

#######################################################################

=head2 content_type_string

=cut

sub content_type_string
{
    return "text/html";
}

#######################################################################


1;

=head1 SEE ALSO

L<Para::Frame>

=cut

