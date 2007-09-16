#  $Id$  -*-cperl-*-
package Para::Frame::Renderer::HTML_Fallback;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework HTML Fallback Renderer
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Renderer::HTML_Fallback - Renders an error page

=cut

use strict;
use Carp qw( croak confess cluck );
use CGI;
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
     'resp'           => undef,
     'req'            => undef,
     'params'         => undef,
    }, $class;

    $rend->{'resp'} = $args->{'resp'}
      or confess "resp param missing";

    $rend->{'req'} = $args->{'req'}
      or confess "req param missing";

#    $rend->{'params'} = {%$Para::Frame::PARAMS};

    return $rend;
}


#######################################################################

=head2 render_output

  $p->render_output( $outref )

Burns the page and stores the result.

This method is called by L<Para::Frame::Request/after_jobs>.

Returns: a scalar ref to the content

Should not ever fail

=cut

sub render_output
{
    my( $rend ) = @_;

    my $req = $rend->{'req'};
    my $resp = $rend->{'resp'};
    my $out = "";
    $out .= "<p>500: Failure to render failure page\n";
    $out .= "<pre>\n";
    $out .= CGI->escapeHTML($req->logging->debug_data)."\n\n";
    $out .= "</pre>\n";
    if( my $backup = $req->site->backup_host )
    {
	my $path = $resp->page->url_path;
	$out .= "<p>Try to get the page from  <a href=\"http://$backup$path\">$backup</a> instead</p>\n"
	}


    return \ $out;
}

#######################################################################

=head2 set_ctype

=cut

sub set_ctype
{
    my( $rend, $ctype ) = @_;

    $ctype->set("text/html; charset=UTF-8")
}


#######################################################################


1;

=head1 SEE ALSO

L<Para::Frame>

=cut
