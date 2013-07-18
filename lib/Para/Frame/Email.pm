package Para::Frame::Email;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Email - For representing an email.Recieved or for sending

=cut

use 5.010;
use strict;
use warnings;

use Email::MIME;
use Email::MIME::CreateHTML;
use HTML::FormatText::WithLinks;
use Carp qw( confess );

use Para::Frame::Reload;
use Para::Frame::Email::Address;
use Para::Frame::Utils qw( debug datadump validate_utf8 throw deunicode );

##############################################################################

=head2 new

=cut

sub new
{
    my( $class, $header, $body ) = @_;


    $body ||= \ '';
    $header ||= [];

    debug "c $class, h $header, b $body";
#    confess "CHECKME";

    my $em = Email::MIME->create(
				 header => $header,
				 body   => $$body,
				 attributes =>
				 {
				  charset  => 'ISO-8859-1',
				  encoding => 'quoted-printable',
				 },
				);


    my $e = bless
    {
     em => $em,
    }, $class;

    return $e;
}


##############################################################################

=head2 new_html

=cut

sub new_html
{
    my( $class, $header, $body ) = @_;


    $body ||= \ '';
    $header ||= [];

    debug "c $class, h $header, b $body";
#    confess "CHECKME";


    my $em = Email::MIME->create_html
      (
       header => $header,
       body   => $$body,
       text_body => 'plain-placeholder',
      );

    my( $pp, @parts );
    foreach my $part ( $em->subparts )
    {
        if( $part->body =~ /^plain-placeholder/ )
        {
            $pp = $part;
        }
        else
        {
            push @parts, $part;
        }
    }

    my $ft = HTML::FormatText::WithLinks->new();
    my $plain = $ft->parse($$body);
    my $plain_out = deunicode($plain); # Convert to ISO-8859-1
    $pp->charset_set( 'ISO-8859-1' );
    $pp->encoding_set( 'quoted-printable' );
    $pp->body_set( $plain_out );

    $em->parts_set([$pp, @parts]);

    debug "EM ".datadump $em;

    my $e = bless
    {
     em => $em,
    }, $class;

    return $e;
}


##############################################################################

=head2 clone

=cut

sub clone
{
    my( $e ) = @_;
    my $class = ref($e);

    $e->redraw;
    my $em = Email::MIME->new($e->{'em'}->as_string);


    my $e2 = bless
    {
     em => $em,
    }, $class;

    return $e2;
}


##############################################################################

=head2 header_str_set

=cut

sub header_str_set
{
    # BUG: Email::MIME 1.902 splits up the encoded row (of From) in a
    # way that confuses Thunderbird

    shift->{'em'}->header_str_set(@_);
}


##############################################################################

=head2 header_set

=cut

sub header_set
{
    shift->{'em'}->header_set(@_);
}


##############################################################################

=head2 raw

Retuns a scalar ref to the whole email with header in raw format.

=cut

sub raw
{
    $_[0]->redraw;
    return \ $_[0]->{'em'}->as_string;
}


##############################################################################

=head2 apply_header_from_params

=cut

sub apply_headers_from_params
{
    my( $e, $p, $to_addr ) = @_;

    my $from_addr = $p->{'from_addr'};
    my $subject = $p->{'subject'};
    my $envelope_from_addr = $p->{'envelope_from_addr'};

    debug "Rendering header from mail to $to_addr";

    $e->header_set('From' => $from_addr->format_mime );
    $e->header_set('To'   => $to_addr->format_mime );


    if( $p->{'subject'} )
    {
	$e->header_set('Subject' => encode_mimewords($p->{'subject'}) );
    }

    if( $p->{'reply_to'} )
    {
	my $reply_to_addr = Para::Frame::Email::Address->
	  parse($p->{'reply_to'});
	$e->header_set('Reply-To' => $reply_to_addr->format_mime);
    }

    if( $p->{'message_id'} )
    {
	unless( $p->{'message_id'} =~ /<.*>/ )
	{
	    $p->{'message_id'} = '<'.$p->{'message_id'}.'>';
	}

	$e->header_set('Message-ID' => $p->{'message_id'} );
    }

    if( $p->{'in_reply_to'} )
    {
	unless( $p->{'in_reply_to'} =~ /<.*>/ )
	{
	    $p->{'in_reply_to'} = '<'.$p->{'in_reply_to'}.'>';
	}
	$e->header_set('In-Reply-To' => $p->{'in_reply_to'} );
    }

    if( $p->{'references'} )
    {
	$e->header_set('References' => $p->{'references'} );
    }

    # Not working...
#    $msg->add('X-Mailer' => "Paraframe $Para::Frame::VERSION (ML $Mime::LITE::VERSION)" );

    my $sender_addr;
    if( $p->{'sender'} )
    {
	$sender_addr = Para::Frame::Email::Address->parse( $p->{'sender'} );
    }

    if( $sender_addr )
    {
	$e->header_set('Sender' => $sender_addr->format );
	debug "Sender set to ".$sender_addr->format;
    }
    elsif( not $envelope_from_addr->equals( $from_addr ) )
    {
	$e->header_set('Sender' => $envelope_from_addr->format );
	debug "Sender set to ".$envelope_from_addr->format." from envelope from";
    }

#    if( $p->{'body_html'} )
#    {
#        my $em = $e->{'em'};
#        delete $em->{'attributes'};
#        throw 'validation', "Apply headers for HTML";
#    }


}

##############################################################################

=head2 redraw

=cut

sub redraw
{
    return;
}


##############################################################################

##############################################################################

sub encode_mimewords
{
    my $string = MIME::Words::encode_mimewords($_[0]);
    $string =~ s/\?= =\?ISO-8859-1\?Q\?/?= =?ISO-8859-1?Q?_/g;
    return $string;
}


##############################################################################


1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::Email::Address>

=cut
