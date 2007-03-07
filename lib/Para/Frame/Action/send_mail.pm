#  $Id$  -*-cperl-*-
package Para::Frame::Action::send_mail;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se action for sending simple emails
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

use strict;

use Para::Frame::Email;
use Para::Frame::Utils qw( throw debug );

sub handler
{
    my ($req) = @_;

    my $q = $req->q;
    my $mail = Para::Frame::Email->new();

    # copy all params by default
    foreach my $param ($q->param)
    {
	$mail->params->{$param} = $q->param($param);
    }

    my $site = $req->site;
    my $site_name = $site->name;
    my $sitemailaddr = $q->param('sitemailaddr') || $site->email;
    my $sitemail;
    if( $sitemailaddr )
    {
	my $sitemail = sprintf('"%s" <%s>', $site_name, $sitemailaddr);
    }

    my $recipient = $q->param('recipient') || $q->param('to');
    if( $recipient )
    {
      CHECK:
	{
	    foreach my $domain (@{$site->email_domains})
	    {
		last if $recipient =~ /$domain$/;
	    }
	    throw('validation', "Sending email to $recipient is not allowed");
	}
    }
    else
    {
	$recipient = $sitemail;
    }

    my $name = $q->param('name') || 'Anonymous';
    my $email =  $q->param('email');
    my $from = sprintf('"%s" <%s>', $name, $email);

    my $subject_request = $q->param('subject') || '<without subject>';
    my $subject_prefix = $q->param('subject_prefix') || "";
    my $subject = $subject_prefix . $subject_request;

    my $template = $q->param('template') || "default.tt";

    my $from_via;
    if( $sitemailaddr )
    {
	$from_via = sprintf('"%s via %s" <%s>', $name, $site_name, $sitemailaddr);
    }

    $mail->params->{'props'} = format_props($req);

    debug "Sending mail to: '$recipient'";

    my $mail_params =
    {
     subject    => $subject,
     to         => $recipient,
     template   => $template,
    };

    if( $from_via )
    {
	$mail_params->{'from'} = $from_via;
	$mail_params->{'reply_to'} = $from;
    }
    else
    {
	$mail_params->{'from'} = $from;
    }

    if( my $reply_to = $q->param('reply_to') )
    {
	$mail_params->{'reply_to'} = $reply_to;
    }

    $mail->send_by_proxy( $mail_params );

    my $return_message = $q->param('return_message') || "";
    return $return_message;
}

sub format_props
{
    my( $req ) = @_;

    my $hr = '-'x 20 ."\n\n";
    my $text = "";

    foreach my $key ( $req->q->param() )
    {
	next unless $key =~ /^prop_(.*)/;
	my $label = $1;
	next if $label eq 'body';

	$text .= $label . ': ';

	my @values = $req->q->param($key);

	$text .= shift(@values). "\n";

	foreach my $value ( @values )
	{
	    $text .= " "x(length($label)+2) . $value . "\n";
	}
	$text .= "\n".$hr;
    }
    return $text . "\n\n";
}

1;
