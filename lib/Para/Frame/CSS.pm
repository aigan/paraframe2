package Para::Frame::CSS;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::CSS - Represents a page CSS configuration

=cut

use 5.012;
use warnings;

use Carp qw( croak cluck );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Time qw( now );


##############################################################################

=head2 new

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    # Colours
    my $css_params =
    {
     body_background => '#FFFFFF',
     main_background => '#FFFFFF',
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

##############################################################################

=head2 params

=cut

sub params
{
    return $_[0]->{'params'};
}



##############################################################################

=head2 updated

Returns the time of the latest modification of the CSS parameters. It
initiates to the time of the start of the server.

=cut

sub updated
{
    return Para::Frame::Time->get($_[0]->{'modified'});
}



##############################################################################

=head2 header

  header( \%attrs )
  header( $url )
  header( 'none' )

Draws a css header.

Paths not beginning with / are relative to the site home.

The specieal css 'none' disables the css header.

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
      persistent => [ "css/default.css_tt" ],
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

#    debug 1, "Choosing a css config";

    if ( $p )
    {
#	debug 2, "  Got css from tt param: ".datadump($p);
        unless( ref $p )
        {
            if ( $p eq 'none' )
            {
                return "";
            }

            $p =
            {
             'persistent' => [ $p ],
            };
        }
    }
    else
    {
#        debug "Looking in ".datadump($css,2);

        if ( $css->{'persistent'} or $css->{'alternate'} )
        {
#            debug 1, "Got css from site css";
            $p = $css;
        }
        elsif ( $Para::Frame::CFG->{'css'}{'persistent'} or
                $Para::Frame::CFG->{'css'}{'alternate'} )
        {
#            debug 1, "Got css from main config";
            $p = $Para::Frame::CFG->{'css'};
        }
        else
        {
#            debug 1, "Falling back to default css";
            $p =
            {
             'persistent' => ['pf/css/paraframe.css_tt',
                              'pf/css/default.css_tt'],
            };
        }
    }

    my $default = $Para::Frame::U->style || $p->{'default'} || 'default';
    my $persistent = $p->{'persistent'} || [];
    my $alternate = $p->{'alternate'} || {};
    $persistent = [$persistent] unless ref $persistent;

    unless ( $alternate->{$default} )
    {
        $default = $p->{'default'};
    }

    if ( not $default )
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
        $out .= "<link rel=\"Stylesheet\" href=\"$style\" type=\"text/css\">\n";
    }

    if ( $default )
    {
        foreach my $style ( @{$alternate->{$default}} )
        {
            $style = &$style($req) if UNIVERSAL::isa($style,'CODE');
            $style =~ s/^([^\/])/$home\/$1/;
            $out .= "<link rel=\"Stylesheet\" title=\"$default\" href=\"$style\" type=\"text/css\">\n";
        }
    }

    foreach my $title ( keys %$alternate )
    {
        next if $title eq $default;
        foreach my $style ( @{$alternate->{$title}} )
        {
            $style = &$style($req) if UNIVERSAL::isa($style,'CODE');
            $style =~ s/^([^\/])/$home\/$1/;
            $out .= "<link rel=\"alternate stylesheet\" title=\"$title\" href=\"$style\" type=\"text/css\">\n";
        }
    }

#    debug "Returning: $out";

    return $out;
}


##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
