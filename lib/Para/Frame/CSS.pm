#  $Id$  -*-cperl-*-
package Para::Frame::CSS;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework CSS class
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

Para::Frame::CSS - Represents a page CSS configuration

=cut

use strict;
use Carp qw( croak cluck );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Time qw( now );

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    # Colours
    my $css_params =
    {
     body_background => '#CCB195',
     main_background => '#ECD3B8',
     border => '#784825',
     button => '#E1CA9C',
    };

    $args ||= {};
    my $css = bless {%$args}, $class;

    $Para::Frame::CFG->{'css'}{'params'} ||= {};

    foreach my $param ( keys %{$Para::Frame::CFG->{'css'}{'params'}} )
    {
	$css->{'params'}{$param}
	  ||= $Para::Frame::CFG->{'css'}{'params'}{$param};
    }

    $css->{'params'} ||= {};
    foreach my $param ( keys %$css_params )
    {
	$css->{'params'}{$param}
	  ||= $css_params->{$param};
    }

    $css->{'modified'} = now();

#    debug "Returning ".datadump($css);

    return $css;
}

#######################################################################

=head2 params

=cut

sub params
{
    return $_[0]->{'params'};
}



#######################################################################

=head2 updated

Returns the time of the latest modification of the CSS parameters. It
initiatyes to the time of the start of the server.

=cut

sub updated
{
    return Para::Frame::Time->get($_[0]->{'modified'});
}



#######################################################################

=head2 header

  header( \%attrs )
  header( $url )

Draws a css header.

Paths not beginning with / are relative to the site home.

The style may be given by using L<Para::Frame::Template::Meta/css> or
by setting a TT param either for the site or globaly.

The persistant styles will always be used and is a ref to list of URLs.

The alternate can be switched between using the browser, or via
javascript, and is a ref to ha hash of stylenames and listrefs holding
the URLs. The default points to which of the alternate styles to use
if no special one is selected.

The persitant and alternate list items may be coderefs. The code will
be run with req as first param. They should return the paths for the
stylefiles. Those may be translated as above.

Example:
    $attrs =
     {
      persistent => [ "css/default.css" ],
      alternate =>
      {
       light => [ "css/light.css" ],
       blue => [ sub{"css/blue.css"} ],
      },
      default => 'blue',
     };

=cut

sub header
{
    my( $css, $p ) = @_;

    my $req = $Para::Frame::REQ;
    my $home = $req->site->home_url_path;

#    debug "Choosing a css config";

    if( $p )
    {
#	debug "  Got css from tt param: ".datadump($p);
	unless( ref $p )
	{
	    $p =
	    {
	     'persistent' => [ $p ],
	    };
	}
    }
    else
    {
	if( $css->{'persisten'} or $css->{'alternate'} )
	{
#	    debug "Got css from site css";
	    $p = $css;
	}
	elsif( $Para::Frame::CFG->{'css'}{'persistent'} or
	       $Para::Frame::CFG->{'css'}{'alternate'} )
	{
#	    debug "Got css from main config";
	    $p = $Para::Frame::CFG->{'css'};
	}
	else
	{
#	    debug "Falling back to default css";
	    $p =
	    {
	     'persistent' => ['pf/css/paraframe.css',
			      'pf/css/default.css'],
	    };
	}
    }

    my $default = $Para::Frame::U->style || $p->{'default'} || 'default';
    my $persistent = $p->{'persistent'} || [];
    my $alternate = $p->{'alternate'} || {};
    $persistent = [$persistent] unless ref $persistent;

    unless( $alternate->{$default} )
    {
	$default = $p->{'default'};
    }

    if( not $default )
    {
	# Just take any of them as a default
	foreach my $key ( keys %$alternate )
	{
	    $default = $key;
	    last;
	}
    }

    my $out = "";

    foreach my $style_in ( @$persistent )
    {
	my $style = $style_in;
	$style = &$style($req) if UNIVERSAL::isa($style,'CODE');
	$style =~ s/^([^\/])/$home\/$1/;
	$out .= "<link rel=\"Stylesheet\" href=\"$style\" type=\"text/css\" />\n";
    }

    if( $default )
    {
	foreach my $style ( @{$alternate->{$default}} )
	{
	    $style = &$style($req) if UNIVERSAL::isa($style,'CODE');
	    $style =~ s/^([^\/])/$home\/$1/;
	    $out .= "<link rel=\"Stylesheet\" title=\"$default\" href=\"$style\" type=\"text/css\" />\n";
	}
    }

    foreach my $title ( keys %$alternate )
    {
	next if $title eq $default;
	foreach my $style ( @{$alternate->{$title}} )
	{
	    $style = &$style($req) if UNIVERSAL::isa($style,'CODE');
	    $style =~ s/^([^\/])/$home\/$1/;
	    $out .= "<link rel=\"alternate stylesheet\" title=\"$title\" href=\"$style\" type=\"text/css\" />\n";
	}
    }

#    debug "Returning: $out";

    return $out;
}


1;

=head1 SEE ALSO

L<Para::Frame>

=cut