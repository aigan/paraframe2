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

=head1 NAME

Para::Frame::Action::send_mail - Formmail

=head1 DESCRIPTION

See also L<Para::Frame::Email>.

=head1 SYNOPSIS

    [% META next_action='send_mail' %]
    <p> Name [% input('name') %]
    <p> Email [% input('email') %]
    <p> Message [% textarea('body') %]
    <p> [% submit('Send the mail') %]

=head1 DESCRIPTION

All query params is turned into params with the same name and sent to
the email template.

Special recognized query params is

  recipient or to : The addres to send the email to
  name            : The name of the sender
  email           : Email of the sender
  subject         : The subject of the email
  subject_prefix  : String to prefix the subject
  template        : The email template to be used
  reply_to        :  Sets an reply_to address
  return_message  : Sends this text as a success message

The mail is sent by proxy.

All query params beginning with C<prop_> are described with their
values in the variable C<props>.

The default email template C<$home/pf/email/default.tt> presents the
variables C<body> and C<props>.

=cut

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
    my $sitemailaddr = $site->email;
    my $sitemail;
    if( $sitemailaddr )
    {
	$sitemail = sprintf('"%s" <%s>', $site_name, $sitemailaddr);
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

    my $home = $site->home_url_path;
    my $template = $q->param('template');
    unless( $template )
    {
	$template = "$home/pf/email/default.tt";
    }

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

=head1 SEE ALSO

L<Para::Frame::Email>

=cut