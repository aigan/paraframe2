#  $Id$  -*-cperl-*-
package Para::Frame::Email;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Email class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Email - For sending emails

=cut

use strict;
use Carp;
use locale;
use IO::File;
use vars qw( $VERSION );
use Mail::Address;
use MIME::Lite;
use Net::DNS;
use Net::SMTP;
use Socket;
use MIME::Words;
use Crypt::OpenPGP;

BEGIN
{
    $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use Para::Frame::Request;
use Para::Frame::Utils qw( throw debug fqdn datadump );
use Para::Frame::Widget;
use Para::Frame::Time qw( date );
use Para::Frame::Email::Address;

=head2 DESCRIPTION

Put the email templates under C<$home/email/>.

=head2 SYNOPSIS

Using the default C<send_mail> paraframe action:

    [% META next_action='send_mail' %]
    <p> Name [% input('name') %]
    <p> Email [% input('email') %]
    <p> Message [% textarea('body') %]
    <p> [% submit('Send the mail') %]

Set the C<Para::Frame::Site/email> variable in the site configuration.

See L<Para::Frame::Email::send_mail>

=cut


#######################################################################

=head2 new

  Para::Frame::Email->new( \%params )

Creates the Email sender object.

The default params for the email are:

  u    = The active L<Para::Frame::User> object (for the application)
  q    = The active L<CGI> object
  date = The L<Para::Frame::Time/date> function
  site = The L<Para::Frame::Site> object

The given C<params> can replace and add to this list. They are given
to L</set>.

Returns the object.

=cut

sub new
{
    my( $class, $p ) = @_;
    my $req = $Para::Frame::REQ;

    my $e = bless
    {
	params =>
	{
	    'u'        => $req->session->user,
	    'q'        => $req->q,
	    'date'     => sub{ date(@_) },
	    'site'     => $req->site,
	},
    }, $class;

    $e->set($p) if $p;
    return $e;
}


#######################################################################

=head2 set

  $e->set( \%params )

Adds and/or replaces the params to use for sending this email.

=cut

sub set
{
    my( $e, $p ) = @_;

    $p ||= {};

    foreach my $key ( keys %$p )
    {
	$e->{params}{$key} = $p->{$key};
    }

    return $e->{params};
}


#######################################################################

=head2 params

  $e->params

Returns the hashref of params.

=cut

sub params
{
    return $_[0]->{params};
}


#######################################################################

=head2 good

  $listref = $e->good()
  @list    = $e->good()
  $bool    = $e->good($email)

In scalar context, it retuns a listref of addresses successfully sent
to.

In list context, it returns a list of addresses sucessfully sent to.

If given an C<$email> returns true if this address was sucessfully
sent to.

=cut

sub good
{
    my( $e, $email ) = @_;

    if( $email )
    {
    	return $e->{'result'}{'good'}{$email};
    }

    return wantarray ? keys %{$e->{'result'}{'good'}} : $e->{'result'}{'good'};
}


#######################################################################

=head2 bad

  $listref = $e->bad()
  @list    = $e->bad()
  $bool    = $e->bad($email)

In scalar context, it retuns a listref of addresses not sent to.

In list context, it returns a list of addresses not sent to.

If given an C<$email> returns true if this address was not sent to.

=cut

sub bad
{
    my( $e, $email ) = @_;

    if( $email )
    {
	return $e->{'result'}{'bad'}{$email};
    }

    return wantarray ? keys %{$e->{'result'}{'bad'}} : $e->{'result'}{'bad'};
}


#######################################################################

=head2 error_msg

  $e->error_msg

Returns the error messages generated or the empty string.

=cut

sub error_msg
{
    return $_[0]->{error_msg} || "";
}


#######################################################################

=head2 send_in_fork

  $fork = Para::Frame::Email->send_in_fork( \%params )
  $fork = Para::Frame::Email->send_in_fork()
  $fork = $e->send_in_fork( \%params )
  $fork = $e->send_in_fork()

Sends the email in a fork. Throws an exception if failure occured.

Returns the fork. 

The return message in the fork is taken from $params{return_message}
or the default "Email delivered".

Calls L</send> with the given C<params>.

Example:

  $fork = Para::Frame::Email->send_in_fork( \%params )
  $fork->yield;
  return "" if $fork->failed;

=cut

sub send_in_fork
{
    my( $e, $p_in ) = @_;

    $e = $e->new unless ref $e;
    $p_in ||= {};

    my $msg = delete( $p_in->{'return_message'} ) || "Email delivered";

    my $fork = $Para::Frame::REQ->create_fork;
    if( $fork->in_child )
    {
	$e->send( $p_in ) or throw('email', $e->error_msg);
	$fork->return($msg);
    }

    return $fork;
}


#######################################################################

=head2 send_in_background

  Para::Frame::Email->send_in_background( \%params )
  Para::Frame::Email->send_in_background()
  $e->send_in_background( \%params )
  $e->send_in_background()

Sends the email in the background. That is. Send it between other
requests. This will make the site unaccessable while the daemin waits
for the recieving email server to answer.

Throws an exception if failure occured.

Returns true if sucessful.

Calls L</send> with the given C<params>.

=cut

sub send_in_background
{
    my( $e, $p_in ) = @_;
    my $req = $Para::Frame::REQ;

    $e = $e->new($p_in) unless ref $e;

    $req->add_background_job(sub{
	$e->send_in_fork() or throw('email', $e->error_msg);
    });
    return 1;
}


#######################################################################

=head2 send_by_proxy

  Para::Frame::Email->send_by_proxy( \%params )
  Para::Frame::Email->send_by_proxy()
  $e->send_by_proxy( \%params )
  $e->send_by_proxy()

Sends the email using a proxy like sendmail.

Adds the param C<by_proxy = 1>

Throws an exception if failure occured.

The return message is taken from $params{return_message} or the
default "Email delivered".

Calls L</send> with the given C<params>.

=cut

sub send_by_proxy
{
    my( $e, $p_in ) = @_;

    # Let another program do the sending. We will not know if it realy
    # succeeded.

    $e = $e->new unless ref $e;
    $p_in ||= {};
    $p_in->{'by_proxy'} = 1;

    return $e->send($p_in);
}


#######################################################################

=head2 send

  Para::Frame::Email->send( \%params )
  Para::Frame::Email->send()
  $e->send( \%params )
  $e->send()

Calls L</set> with the given params, adding or replacing the existing
params.

Resets the result status before sending.

The required params are:

  template  = Which TT template to use for the email
  from      = The sender email address
  subject   = The subject line of the email
  to        = The reciever email address

Optional params:

  pgpsign   = Signs the email with pgpsign
  reply_to  = Adds a Reply-To header to the email
  by_proxy  = Sens email using sendmail


The template are searched for in the C<$home/email/> dir under the
site home. If the template starts with C</>, it will not be prefixed
by C<$home/email/>.

C<to> can be a ref to a list of email addresses to try. We try them in
the given order. Quits after the furst sucessful address.

Sends all the params to the TT template for rendering.

With param C<pgpsign>, signs the resulting email by calling
L</pgpsign> with the email content and the param value.

Makes the C<form> address an object using
L<Para::Frame::Email::Address/parse>.

Makes the C<to> addresses objects by using
L<Para::Frame::Email::Address/parse>.

Encodes the to, form and subject fields of the email by using mime
encoding.

Sends the email in the format quoted-printable.

If sending C<by_proxy>, we will not get any indication if the email
was sucessfully sent or not.

Returns true on success or false on failure to send email.

Exceptions:

notfound - Hittar inte e-postmallen ...

mail - Failed to parse address $p->{'from'}

Example:

  my $emailer = Para::Frame::Email->new({
    template => 'registration_confirmation.tt',
    from     => '"The registry office" <registry@mydomain.com>',
    to       => $recipient_email,
    subject  => "Welcome to our site",
  });
  $emailer->send or throw('email', $emailer->err_msg);


=cut

sub send
  {
    my($e, $p_in ) = @_;

    my $req = $Para::Frame::REQ;
    my $site = $req->site;
    my $home = $site->home_url_path;
    my $fqdn = fqdn;

    unless( $site->send_email )
    {
	debug "Not sending any email right now...";
	return 0;
    }

    $e = $e->new unless ref $e;

    my $err_msg = "";
    my $res = $e->{'result'} = {}; # Reset results
    my $p = $e->set( $p_in );


    $p->{'template'} or die "No template selected\n";
    $p->{'from'}     or die "No from selected\n";
    $p->{'subject'}  or die "No subject selected\n";
    $p->{'to'}       or die "No reciever for this email?\n";

    # List of addresses to try. Quit after first success
    my @try = ref $p->{'to'} eq 'ARRAY' ? @{$p->{'to'}} : $p->{'to'};


    my $url;
    if( $p->{'template'} =~ /^\// )
    {
	$url = $p->{'template'};
    }
    else
    {
	$url = "$home/email/".$p->{'template'};
    }

    my $page = Para::Frame::File->new({
				       url => $url,
				       site => $site,
				       file_may_not_exist => 1,
				      });

    my( $tmpl ) = $page->template;
    if( not $tmpl )
    {
	throw('notfound', "Hittar inte e-postmallen ".$p->{'template'});
    }

    my $rend = $tmpl->renderer;

    my $burner = $rend->set_burner_by_type('plain');


    # Clone params for protection from change
    my %params = %$p;

    $params{'page'} = $page;

    my $data = "";
    $burner->burn( $rend, $tmpl->sys_path, \%params, \$data )
      or throw($burner->error);
    utf8::downgrade($data); # Convert to ISO-8859-1

    if( $p->{'pgpsign'} )
    {
	pgpsign(\$data, $p->{'pgpsign'} );
    }

    my $from_addr = Para::Frame::Email::Address->parse( $p->{'from'} );
    $from_addr or
	throw('mail', "Failed to parse address $p->{'from'}\n");

    my $envelope_from_addr = $from_addr;
    if( $p->{'envelope_from'} )
    {
	$envelope_from_addr = Para::Frame::Email::Address->parse( $p->{'envelope_from'} );
    }

    my $envelope_from_addr_str = $envelope_from_addr->address;
    my $from_addr_str = $from_addr->address;


    my @tried = ();
  TRY:
    foreach my $try ( @try )
    {
	$try or debug(0,"Empty reciever email address") and next;
	my( $to_addr ) = Para::Frame::Email::Address->parse( $try );
	unless( $to_addr )
	{
	    # Try to stringify
	    $try = $try->as_string if ref $try;

	    $res->{'bad'}{$try} ||= [];
	    push @{$res->{'bad'}{$try}}, "Failed parsing";
	    debug(0,"Failed parsing $try");
	    next;
	}
#	my $to_addr_str = $to_addr->address;
	push @tried, $to_addr->address;

	my $msg;

	# I don't know.  Trying to mimic others
	if( $p->{'pgpsign'} )
	{
	    $msg = MIME::Lite->new(
	      From     => $from_addr->format,
	      To       => $to_addr->format,
	      Subject  => $p->{'subject'},
	      Type     => 'TEXT',
	      Data     => $data,
#	      Encoding => '8bit',
	      Encoding => 'quoted-printable',
	     );
#	    $msg->attr('content-type.charset' => 'UTF8');
	    $msg->attr('content-type.charset' => 'ISO-8859-1');
	}
	else
	{
	    $msg = MIME::Lite->new(
	      From     => encode_mimewords($from_addr->format),
	      To       => encode_mimewords($to_addr->format),
	      Subject  => encode_mimewords($p->{'subject'}),
	      Type     => 'TEXT',
	      Data     => $data,
	      Encoding => 'quoted-printable',
	     );
#	    $msg->attr('content-type.charset' => 'UTF8');
	    $msg->attr('content-type.charset' => 'ISO-8859-1');
	}


	if( $p->{'reply_to'} )
	{
	    $msg->add('Reply-To' =>  $p->{'reply_to'} );
	}

	my $sender_addr;
	if( $p->{'sender'} )
	{
	    $sender_addr = Para::Frame::Email::Address->parse( $p->{'sender'} );
	}

	if( $sender_addr )
	{
	    $msg->add('Sender' => $sender_addr->format );
	    debug "Sender set to ".$sender_addr->format;
	}
	elsif( not $envelope_from_addr->equals( $from_addr ) )
	{
	    $msg->add('Sender' => $envelope_from_addr->format );
	    debug "Sender set to ".$envelope_from_addr->format." from envelope from";
	}


	# Should we send this by proxy?
	#
	if( $p->{'by_proxy'} )
	{
	    my $to_addr_str = $to_addr->address;
	    if( $msg->send_by_sendmail( FromSender => $from_addr->address ) )
	    {
		# Success!
		debug(2,"Success");
		$res->{'good'}{$to_addr_str} ||= [];
		push @{$res->{'good'}{$to_addr_str}}, "succeeded";
		last TRY;
	    }
	    else
	    {
		$res->{'bad'}{$to_addr_str} ||= [];
		push @{$res->{'bad'}{$to_addr_str}}, "failed";
		$err_msg .= debug(0,"Faild to send mail to $to_addr_str");
		next TRY;
	    }
	}


	my( $host ) = $to_addr->host();
	unless( $host )
	{
	    my $to_addr_str = $to_addr->address;
	    $res->{'bad'}{$to_addr_str} ||= [];
	    push @{$res->{'bad'}{$to_addr_str}}, "Nu such host";
	    debug(0,"Nu such host: $to_addr_str");
	    next;
	}

	my @mx_list = mx($host);
	my @mailhost_list;
	foreach my $mx ( @mx_list )
	{
	    push @mailhost_list, $mx->exchange();
	}
	unless( @mailhost_list )
	{
	    $err_msg .= debug(0,"Domain $host do not accept email (No MX record)");
	    unless( $host =~ /^mail\./ )
	    {
		push @mailhost_list, "mail.$host";
	    }
	    push @mailhost_list, $host;
	    $err_msg .= debug(0,"  But I'll try anyway (guessing mailserver)");
	}
      MX:
	foreach my $mailhost ( @mailhost_list )
	{
	    $req->note("Connecting to $mailhost");

	    # TODO: Specify hello string...
	    my $smtp = Net::SMTP->new( Host    => $mailhost,
				       Timeout => 60,
				       Debug   => 0,
				       Hello   => $fqdn,
				       );

#	    # DEBUG (should nog happen)
#	    if( $smtp and $smtp->domain eq 'paranormal.se' )
#	    {
#		undef $smtp;
#	    }

	    my $to_addr_str = $to_addr->address;

	  SEND:
	    {
		if( $smtp )
		{
		    $req->note(sprintf("Connected to %s", $smtp->domain));
		    debug(0,"Sending mail from $envelope_from_addr_str");
		    debug(0,"Sending mail to $to_addr_str");
		    $smtp->mail($envelope_from_addr_str) or last SEND;
		    $smtp->to($to_addr_str) or last SEND;
		    $smtp->data() or last SEND;
		    $smtp->datasend($msg->as_string) or last SEND;
		    $smtp->dataend() or last SEND;
		    $smtp->quit() or last SEND;

		    # Success!
		    debug(2,"Success",-1);
		    $res->{'good'}{$to_addr_str} ||= [];
		    push @{$res->{'good'}{$to_addr_str}}, $smtp->message();
		    last TRY;
		}
		$err_msg .= "No answer from mx $mailhost";
		$req->note("No answer from mx $mailhost");
		next MX;
	    }

	    $res->{'bad'}{$to_addr_str} ||= [];
	    push @{$res->{'bad'}{$to_addr_str}}, $smtp->message();
	    my $mailhost_err_msg = "Error response from $mailhost: ".$smtp->message();
	    $err_msg .= $mailhost_err_msg;
	    $req->note($mailhost_err_msg);
	    debug(-1);
	}
	debug(0,"Address bad");
    }

    if( $err_msg )
    {
	my $cnt = @tried;
	$err_msg .= "Tried ".Para::Frame::Widget::inflect($cnt, "1 e-mail address", "%d e-mail addresses")."\n";
    }

    unless( @tried )
    {
	$err_msg .= "No working e-mail found\n";
    }

    debug(1,"Returning status. Error set to: $err_msg");

    $e->{error_msg} = $err_msg;

    if( $res->{'good'} )
    {
	debug(1,"Returning success");
	return 1;
    }
    else
    {
	debug(1,"Returning failure");
	return 0;
	# throw('mail', $err_msg);
    }
}


#######################################################################

sub encode_mimewords
{
    my $string = MIME::Words::encode_mimewords($_[0]);
    $string =~ s/\?= =\?ISO-8859-1\?Q\?/?= =?ISO-8859-1?Q?_/g;
    return $string;
}


#######################################################################

=head2 pgpsign

  pgpsign( $dataref, $configfile )

This is called by C<$e-C<gt>send()> if the param C<pgpsign> has
C<$configfile> as value.

The signing is done by L<Crypt::OpenPGP> using C<Compat> PGP5 and
C<ConfigFile $configfile>.

Modifies $dataref.

Return true on success.

Exceptions:

action - The error given by L<Crypt::OpenPGP/sign>

=cut

sub pgpsign
{
    my( $dataref, $cfile ) = @_;

    ## Code builded from examples in manuale.  KeyID taken from
    ## example in file pgplet.  sub get_seckey()


    my $conf =
    {
     Compat => 'PGP5',
     ConfigFile => $cfile,
    };

    my $pgp = Crypt::OpenPGP->new( %$conf );
    my $cert = get_seckey( $pgp ) or die $pgp->errstr;
    my $key_id = $cert->key_id_hex;

    my $signature = $pgp->sign(
			       Data   => $$dataref,
			       KeyID      => $key_id,
			       Clearsign  => 1,
			      ) or die $pgp->errstr;

    debug(0,"Signing email");
    # Substitute the original data
    ${$_[0]} = $signature;
    return 1;
}

sub get_seckey {
    my($pgp, $opts) = @_;
    my $ring = Crypt::OpenPGP::KeyRing->new( Filename =>
        $pgp->{cfg}->get('SecRing') ) or
            return $pgp->error(Crypt::OpenPGP::KeyRing->errstr);
    my $kb;
    if (my $user = $opts->{'local-user'}) {
        my($lr, @kb) = (length($user));
        if (($lr == 8 || $lr == 16) && $user !~ /[^\da-fA-F]/) {
            @kb = $ring->find_keyblock_by_keyid(pack 'H*', $user);
        } else {
            @kb = $ring->find_keyblock_by_uid($user);
        }
        if (@kb > 1) {
            my $prompt = "
The following keys can be used to sign the message:
";
            my $i = 1;
            for my $kb (@kb) {
                my $cert = $kb->signing_key or next;
                $prompt .= sprintf "    [%d] %s (ID %s)\n",
                    $i++, $kb->primary_uid,
                    substr($cert->key_id_hex, -8, 8);
            }
            $prompt .= "
Enter the index of the signing key you wish to use: ";
            my $n;
            $n = prompt($prompt, $i - 1) while $n < 1 || $n > @kb;
            $kb = $kb[$n-1];
        } else {
            $kb = $kb[0];
        }
    } else {
        $kb = $ring->find_keyblock_by_index(-1);
    }
    return $pgp->error("Can't find keyblock: " . $ring->errstr)
        unless $kb;
    my $cert = $kb->signing_key;
    $cert->uid($kb->primary_uid);
    $cert;
}

#######################################################################


1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::Email::Address>

=cut
