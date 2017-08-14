package Para::Frame::L10N;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::L10N - framework for localization

=head1 DESCRIPTION

Objects of this class represent a specific language preference. That
preference will be extracted from the request. Each request should
create it's own object.

A request can change its language preference by methods on this
object, or by creating another object with diffrent preferences.

Exportable functions are L</loc> and L</locescape>.

=cut

use 5.012;
use warnings;
use base qw(Locale::Maketext);

use base qw( Exporter );
our @EXPORT_OK = qw( loc locescape );

use Carp qw(cluck croak carp confess shortmess );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );


##############################################################################

=head2 loc

  loc( $phrase )

  loc( $phrase, @args )

Calls L<Locale::Maketext/maketext> with the given arguments using the
request language handler set by L<Para::Frame::Request/set_language>.

This is an exportable function.

=cut

sub loc (@)
{
#    debug "Translating @_";
    confess "No req" unless $Para::Frame::REQ;
    return($_[0]) if $Para::Frame::REQ->cancelled;
    my $res = $Para::Frame::REQ->{'lang'}->maketext(@_);
#    if( utf8::is_utf8($res) )
#    {
#	debug "  UTF8   to $res";
#    }
#    else
#    {
#	debug "         to $res";
#    }
    return $res;
}


##############################################################################

=head2 locescape

  locescape( $phrase )

Escapes special symbols in the string that is going to be parsed by
MakeText L</loc>. This escapes C<[>, C<]>, and C<~>.

Returns: A scalar string

=cut

sub locescape
{
    $_ = shift;
    s/~/~~/g;
    s/\[/~[/g;
    s/\]/~]/g;
    return $_;
}

##############################################################################

=head2 set

  $class->set()

  $class->set( \@langcodes )

  $class->set( $langcode )

  $class->set( $accet_language_header_string )

This sets and returns the language handler in the context of the
Request. It is called via L<Para::Frame::Request/set_language>.

If this is a client request and no params are given, the language
priority defaults to the query param C<lang> or the cookie C<lang> or
the environment variable C<HTTP_ACCEPT_LANGUAGE> in turn.

=cut

sub set
{
    my( $this, $language_in, $args ) = @_;

    my $class = ref($this) || $this;

    debug 3, "Decide on a language";

    $args ||= {};
    my( $site, $req );
    if ( my $page = $args->{'page'} )
    {
        $site = $page->site;
    }
    else
    {
        $req = $args->{'req'} || $Para::Frame::REQ;
        $site = $req->site;
    }

    # Get site languages
    #
    my $site_languages = $site->languages;

    unless( @$site_languages )
    {
        debug 2, "  No site language specified";
        my @alternatives = 'en';
        my $lh = $this->get_handle( @alternatives );
        $lh->{'alternatives'} = \@alternatives;
        unless( UNIVERSAL::isa $lh,'Para::Frame::L10N')
        {
            croak "Lanugage obj of wrong type: ".datadump($lh);
        }
        return $lh;
    }

    # get input language
    #
    if ( $req and $req->is_from_client )
    {
        $language_in ||= $req->q->param('lang')
          ||  $req->q->cookie('lang')
          ||  $req->env->{HTTP_ACCEPT_LANGUAGE}
          ||  '';
    }
    else
    {
        $language_in ||= '';
    }
    debug 3, "  Lang prefs are $language_in";


    # Parse input languages
    #
    my @alts;
    if ( UNIVERSAL::isa($language_in, "ARRAY") )
    {
        @alts = @$language_in;
    }
    else
    {
        @alts = split /,\s*/, $language_in;
    }

    my %priority;

    foreach my $alt ( @alts )
    {
        my( $code, @info ) = split /\s*;\s*/, $alt;
        my $q;
        foreach my $pair ( @info )
        {
            my( $key, $value ) = split /\s*=\s*/, $pair;
            $q = $value if $key eq 'q';
        }
        $q ||= 1;

        push @{$priority{$q}}, $code;
    }

    my %accept = map { $_, 1 } @$site_languages;

    my @alternatives;
    foreach my $prio ( sort {$b <=> $a} keys %priority )
    {
        foreach my $lang ( @{$priority{$prio}} )
        {
            push @alternatives, $lang if $accept{$lang};
        }
    }

    ## Add default lang, if not already there
    #
    my @defaults = $site_languages->[0];


    # Select supportyed langs
    #
    foreach my $lang ( @$site_languages )
    {
        unless ( grep {$_ eq $lang} @alternatives )
        {
            push @alternatives, $lang;
        }
    }


    # Return object
    #
    my $lh = $this->get_handle( @alternatives );


    unless( UNIVERSAL::isa $lh,'Para::Frame::L10N')
    {
        croak "Lanugage obj of wrong type: ".datadump($lh);
    }

    debug 2, "Lang priority is: @alternatives";

    $lh->{'alternatives'} = \@alternatives;

    return $lh;
}


##############################################################################

=head2 get_handle

  $class->get_handle( @langcodes )

Extends L<Locale::Metatext/get_handle> to work for one lexicon in
L<Para::Frame::Site/appbase> (or L<Para::Frame::Site/appfmly>) and
then to fall back on the paraframe lexicons.

If you want more than two lexicons in the chain you have to implement
that yourself by extending L</get_handle> even more.

This extensions also works in the case there there is no site lexicon.

This works by setting the attribute C<fallback> to a paraframe lexicon
and teling L<Locale::Maketext/fail_with> to use L</fallback_maketext>.

=cut

sub get_handle
{
    my $class = shift;

    if ( $class eq "Para::Frame::L10N" )
    {
        return Para::Frame::L10N->SUPER::get_handle(@_)
          || die "Failed to get language handler";
    }

    my $lh = $class->SUPER::get_handle(@_)
      or die "Failed to get primary language handler";
    my $fallback = Para::Frame::L10N->SUPER::get_handle(@_)
      or die "Failed to get secondary language handler";
    $lh->{'fallback'} = $fallback;
    $lh->fail_with( \&fallback_maketext );
    return $lh;
}


##############################################################################

=head2 fallback_maketext

  $lh->fallback_maketext( $phrase )

  $lh->fallback_maketext( $phrase, @args )

Calls maketext with the fallback language handler. L</get_handle> sets
this to the one retrieved by L</Locale::Maketext/get_handle> called
from L<Para::Frame::L10N>.

=cut

sub fallback_maketext
{
    return shift->{'fallback'}->maketext(@_);
}


##############################################################################

=head2 compute

  $lh->compute( $value, \$phrase )

  $lh->compute( $value, \$phrase, @args )

The code for this is directly taken from L<Locale::Maketext/maketext>
for handling execution of the translation found.

If you prefere to create your own maketext method, you can use this to
tie in to the L<Locale::Maketext> framework.

The C<$value> is that returned by the internal C<_compile> method in
L<Locale::Maketext>. C<$phrase> should ge biven as a scalar ref of the
text to translate, used for fallback and error handling if C<$value>
fails. See L<Locale::Maketext/maketext>.

This example reimplements C<maketext> and retrieves the translation
from a SQL translation table, storing the compiled values in a
C<%TRANSLATION> hash:

    sub maketext
    {
        my( $lh, $phrase ) = (shift, shift );
        my $req = $Para::Frame::REQ;

        return "" unless length($phrase);

        # Retrieves the translation from my database

        my @alts = $req->language->alternatives;
        my( $rec, $value );
        foreach my $langcode ( @alts )
        {
            unless( $value = $TRANSLATION{$phrase}{$langcode} )
    	    {
    	        $rec ||= $My::dbix->select_possible_record(
                                   'from tr where c=?',$phrase) || {};
    	        if( defined $rec->{$langcode} and length $rec->{$langcode} )
    	        {
                    # Compiles the translation value
    		    $value = $TRANSLATION{$phrase}{$langcode}
                           = $lh->_compile($rec->{$langcode});
    		    last;
    	        }
    	        next;
    	    }
    	    last;
        }
        return $lh->compute();
    }

    # Return the computed value

    return $lh->compute($value, \$phrase, @_);

=cut

sub compute
{
    my( $lh, $value, $phrase ) = (shift, shift, shift);

    unless( ref $phrase )
    {
        die("The prase should be a scalar ref");
    }

    unless(defined($value))
    {
        if ($lh->{'fail'})
        {
            my $res;
            eval
            {
                my $fail;
                if (ref($fail = $lh->{'fail'}) eq 'CODE')
                {
                    $res = &{$fail}($lh, $$phrase, @_);
                }
                else
                {
                    $res = $lh->$fail($$phrase, @_);
                }
            };
            if ( $@ )
            {
                my $class = ref $lh;
                Carp::croak "Error in $class maketexting:\n$@";
            }
            else
            {
                return $res;
            }
        }
        else
        {
            die shortmess("maketext doesn't know how to say:\n$phrase\nas needed");
        }
    }

    if ( ref($value) eq 'SCALAR' )
    {
        utf8::upgrade($$value );
        return $$value;
    }

    unless( ref($value) eq 'CODE' )
    {
        utf8::upgrade( $value );
        return $value;
    }

    {
        local $SIG{'__DIE__'};
        eval { $value = &$value($lh, @_) };
    }
    if ($@)
    {
        my $err = $@;
        my $class = ref $lh;
        $err =~ s<\s+at\s+\(eval\s+\d+\)\s+line\s+(\d+)\.?\n?>
                 <\n in bracket code [compiled line $1],>s;
        Carp::croak "Error in $class maketexting \"$phrase\":\n$err as used";
    }

    utf8::upgrade( $value );
    return $value;
}


##############################################################################

=head2 preferred

  $lh->preferred()

  $lh->preferred( $lang1, $lang2, ... )

Returns the language form the list that the user preferes. C<$langX>
is the language code, like C<sv> or C<en>.

The list will always be restircted to the languages supported by the
site, ie C<$req-E<gt>site-E<gt>languages>.  The parameters should only
be used to restrict the choises futher.

=head3 Default

The first language in the list of languages supported by the
application.

=head3 Example

  [% SWITCH lang %]
  [% CASE 'sv' %]
     <p>Valkommen ska ni vara!</p>
  [% CASE %]
     <p>Welcome, poor thing.</p>
  [% END %]

=cut

sub preferred
{
    my( $lh, @lim_langs ) = @_;

    my $req = $Para::Frame::REQ;
    my $site;
    if ( my $resp = $req->response_if_existing )
    {
        if( my $page = $resp->page )
        {
            $site = $page->site;
        }
    }

    unless( $site )
    {
        $site = $req->site;
    }

    my @langs;
    if ( @lim_langs )
    {
      LANG:
        foreach my $lang (@{$site->languages})
        {
            foreach ( @lim_langs )
            {
                if ( $lang eq $_ )
                {
                    push @langs, $lang;
                    next LANG;
                }
            }
        }
    }
    else
    {
        @langs = @{$site->languages};
    }

    if ( $req->is_from_client )
    {
        if ( my $clang = $req->q->cookie('lang') )
        {
            unshift @langs, $clang;
        }
    }

    foreach my $lang ($lh->alternatives)
    {
        foreach ( @langs )
        {
            if ( $lang eq $_ )
            {
                return $lang;
            }
        }
    }

    return $site->languages->[0] || 'en';
}


##############################################################################

=head2 alternatives

  $lh->alternatives

Returns a ref to a list of language code strings.  For example
C<['en']>. This is a prioritized list of languages that the sithe
handles and that the client prefere.

=cut

sub alternatives
{
    return wantarray ? @{$_[0]->{'alternatives'}} : $_[0]->{'alternatives'};
}


##############################################################################

=head2 code

  $lh->code

Returnes the first language alternative from L</alternatives> as a
string of two characters.

=cut

sub code
{
    return $_[0]->{'alternatives'}[0];
}


##############################################################################

=head2 set_headers

  $lh->set_headers()

Sets the headers based on the language used for the request

=cut

sub set_headers
{
    my( $lh ) = @_;

    my $req = $Para::Frame::REQ;

    # Set resp header
    #
    if ( $req->is_from_client )
    {
        unless( $req->response->ctype->is("text/css") )
        {
            # TODO: Use Page->set_header
            my $alts = $lh->alternatives;
            if ( $alts->[1] )   # More than one language
            {
                $req->send_code( 'AT-PUT', 'set', 'Vary', 'negotiate,accept-language' );
            }
            $req->send_code( 'AT-PUT', 'set', 'Content-Language', $alts->[0] );
        }
    }
}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
