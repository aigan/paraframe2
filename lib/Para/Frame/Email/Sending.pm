package Para::Frame::Email::Sending;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2010 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Email::Sending - For sending emails

=cut

use 5.010;
use strict;
use warnings;

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
use Scalar::Util qw( reftype );
#use Crypt::OpenPGP;

use Para::Frame::Reload;

use Para::Frame::Request;
use Para::Frame::Utils qw( throw debug fqdn datadump validate_utf8 deunicode );
use Para::Frame::Widget;
use Para::Frame::Time qw( date now ); #);
use Para::Frame::Email::Address;
use Para::Frame::Renderer::Email;
#use Para::Frame::Renderer::TT_noplace;

our $COUNTER = 1; # For generating message-id


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

See L<Para::Frame::Email::Sending::send_mail>

=cut


##############################################################################

=head2 new

  Para::Frame::Email::Sending->new( \%params )

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


##############################################################################

=head2 set

  $e->set( \%params )

Adds and/or replaces the params to use for sending this email.

Params with special meaning are:

  body
#  body_encoded
  by_proxy
  envelope_from
  envelope_from_addr
  from
  from_addr
#  header
#  header_rendered_to
  in_reply_to
  message_id
#  mime_lite
  pgpsign
  references
  reply_to
  sender
  subject
  template
  to


=cut

sub set
{
    my( $s, $p ) = @_;

    $p ||= {};

    foreach my $key ( keys %$p )
    {
	$s->{params}{$key} = $p->{$key};
    }

    return $s->{params};
}


##############################################################################

=head2 params

  $s->params

Returns the hashref of params.

=cut

sub params
{
    return $_[0]->{params};
}


##############################################################################

=head2 good

  $listref = $s->good()
  @list    = $s->good()
  $bool    = $s->good($email)

In scalar context, it retuns a listref of addresses successfully sent
to.

In list context, it returns a list of addresses sucessfully sent to.

If given an C<$email> returns true if this address was sucessfully
sent to.

=cut

sub good
{
    my( $s, $email ) = @_;

    if( $email )
    {
    	return $s->{'result'}{'good'}{$email};
    }

    return wantarray ? keys %{$s->{'result'}{'good'}} : $s->{'result'}{'good'};
}


##############################################################################

=head2 bad

  $listref = $s->bad()
  @list    = $s->bad()
  $bool    = $s->bad($email)

In scalar context, it retuns a listref of addresses not sent to.

In list context, it returns a list of addresses not sent to.

If given an C<$email> returns true if this address was not sent to.

=cut

sub bad
{
    my( $s, $email ) = @_;

    if( $email )
    {
	return $s->{'result'}{'bad'}{$email};
    }

    return wantarray ? keys %{$s->{'result'}{'bad'}} : $s->{'result'}{'bad'};
}


##############################################################################

=head2 error_msg

  $s->error_msg

Returns the error messages generated or the empty string.

=cut

sub error_msg
{
    return $_[0]->{error_msg} || "";
}


##############################################################################

=head2 send_in_fork

  $fork = Para::Frame::Email::Sending->send_in_fork( \%params )
  $fork = Para::Frame::Email::Sending->send_in_fork()
  $fork = $s->send_in_fork( \%params )
  $fork = $s->send_in_fork()

Sends the email in a fork. Throws an exception if failure occured.

Returns the fork.

The return message in the fork is taken from $params{return_message}
or the default "Email delivered".

Calls L</send> with the given C<params>.

Example:

  $fork = Para::Frame::Email::Sending->send_in_fork( \%params )
  $fork->yield;
  return "" if $fork->failed;

=cut

sub send_in_fork
{
    my( $s, $p_in ) = @_;

    $s = $s->new unless ref $s;
    $p_in ||= {};

    my $msg = delete( $p_in->{'return_message'} ) || "Email delivered";

    my $fork = $Para::Frame::REQ->create_fork;
    if( $fork->in_child )
    {
	$s->send( $p_in ) or throw('email', $s->error_msg);
	$fork->return($msg);
    }

    return $fork;
}


##############################################################################

=head2 send_in_background

  Para::Frame::Email::Sending->send_in_background( \%params )
  Para::Frame::Email::Sending->send_in_background()
  $s->send_in_background( \%params )
  $s->send_in_background()

Sends the email in the background. That is. Send it between other
requests. This will make the site unaccessable while the daemin waits
for the recieving email server to answer.

Throws an exception if failure occured.

Returns true if sucessful.

Calls L</send> with the given C<params>.

=cut

sub send_in_background
{
    my( $s, $p_in ) = @_;
    my $req = $Para::Frame::REQ;

    $s = $s->new($p_in) unless ref $s;

    $req->add_background_job('send_email_in_background', sub{
	$s->send_in_fork() or throw('email', $s->error_msg);
    });
    return 1;
}


##############################################################################

=head2 send_by_proxy

  Para::Frame::Email::Sending->send_by_proxy( \%params )
  Para::Frame::Email::Sending->send_by_proxy()
  $s->send_by_proxy( \%params )
  $s->send_by_proxy()

Sends the email using a proxy like sendmail.

Adds the param C<by_proxy = 1>

Throws an exception if failure occured.

The return message is taken from $params{return_message} or the
default "Email delivered".

Calls L</send> with the given C<params>.

=cut

sub send_by_proxy
{
    my( $s, $p_in ) = @_;

    # Let another program do the sending. We will not know if it realy
    # succeeded.

    debug "Sending by proxy";

    $s = $s->new unless ref $s;
    $p_in ||= {};
    $p_in->{'by_proxy'} = 1;

    return $s->send($p_in);
}


##############################################################################

=head2 send

  Para::Frame::Email::Sending->send( \%params )
  Para::Frame::Email::Sending->send()
  $s->send( \%params )
  $s->send()

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

  my $emailer = Para::Frame::Email::Sending->new({
    template => 'registration_confirmation.tt',
    from     => '"The registry office" <registry@mydomain.com>',
    to       => $recipient_email,
    subject  => "Welcome to our site",
  });
  $emailer->send or throw('email', $emailer->err_msg);


=cut

sub send
{
    my($s, $p_in ) = @_;

    my $req = $Para::Frame::REQ;
    my $site = $req->site;
    my $home = $site->home_url_path;
    my $fqdn = fqdn;

    unless( $site->send_email )
    {
	debug "Not sending any email right now...";
	return 0;
    }

    debug "Creating PF message obj";

    $s = $s->new unless ref $s;

    my $err_msg = "";
    my $res = $s->{'result'} = {}; # Reset results
    my $p = $s->set( $p_in );

    $p->{'from'}     or die "No from selected\n";
    $p->{'to'}       or die "No reciever for this email?\n";

    # List of addresses to try. Quit after first success
    my @try = ref $p->{'to'} eq 'ARRAY' ? @{$p->{'to'}} : $p->{'to'};

    my $from_addr = Para::Frame::Email::Address->parse( $p->{'from'} );
    $from_addr or
	throw('mail', "Failed to parse address $p->{'from'}\n");

    $p->{'from_addr'} = $from_addr;

    my $envelope_from_addr = $from_addr;
    if( $p->{'envelope_from'} )
    {
	$envelope_from_addr = Para::Frame::Email::Address->parse( $p->{'envelope_from'} );
    }
    $p->{'envelope_from_addr'} = $envelope_from_addr;

    my $envelope_from_addr_str = $envelope_from_addr->address;
    my $from_addr_str = $from_addr->address;

    debug "Email from $from_addr_str";


    my @tried = ();
  TRY:
    foreach my $try ( @try )
    {
	$try or debug(0,"Empty reciever email address") and next;

	debug "Trying $try";

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
	push @tried, $to_addr->address;

	debug "Rendering message";
	my $dataref = $s->renderer->render_message($to_addr);
	debug "Rendering message - done";


	# Should we send this by proxy?
	#
	if( $p->{'by_proxy'} )
	{
	    my $to_addr_str = $to_addr->address;

	    my $Sendmail = "/usr/lib/sendmail";
	    my $FromSender = $from_addr->address;

	    ### Start with the command and basic args:
	    my @cmd = ($Sendmail, '-t', '-oi', '-oem');
	    push @cmd, "-f$FromSender";

	    eval
	    {
		### Open the command in a taint-safe fashion:
		debug "Opening a pipe to sendmail";
		my $pid = open SENDMAIL, "|-";
		defined($pid) or die "open of pipe failed: $!\n";
		if(!$pid)    ### child
		{
		    debug "Executing command @cmd";
		    exec(@cmd) or die "can't exec $Sendmail: $!\n";
		    ### NOTREACHED
		}
		else         ### parent
		{
		    debug "Sending email to pipe";
		    print SENDMAIL $$dataref;
		    close SENDMAIL || die "error closing $Sendmail: $! (exit $?)\n";
		    debug "Pipe closed";
		}
	    };

	    if( $@ )
	    {
		debug "We got problems: $@";
		$res->{'bad'}{$to_addr_str} ||= [];
		push @{$res->{'bad'}{$to_addr_str}}, "failed";
		$err_msg .= debug(0,"Faild to send mail to $to_addr_str");
		next TRY;
	    }
	    else
	    {
		# Success!
		debug(1,"Success");
		$res->{'good'}{$to_addr_str} ||= [];
		push @{$res->{'good'}{$to_addr_str}}, "succeeded";
		last TRY;
	    }
	}


	debug "Getting host";
	my( $host ) = $to_addr->host();
	unless( $host )
	{
	    my $to_addr_str = $to_addr->address;
	    $res->{'bad'}{$to_addr_str} ||= [];
	    push @{$res->{'bad'}{$to_addr_str}}, "Nu such host";
	    debug(0,"Nu such host: $to_addr_str");
	    next;
	}

	debug "Getting MX";
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

	    # Needs to have a high timeout. Some SMTP servers likes to
	    # keep us waiting as a way to sort out spammers.

	    my $smtp = Net::SMTP->new( Host    => $mailhost,
				       Timeout => 120,
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
		    $smtp->debug(1) if debug > 1;
		    $req->note(sprintf("Connected to %s", $smtp->domain));
		    debug(0,"Sending mail from $envelope_from_addr_str");
		    debug(0,"Sending mail to $to_addr_str");
		    $smtp->mail($envelope_from_addr_str) or last SEND;
		    $smtp->to($to_addr_str) or last SEND;
		    my $datawait = 0;
		    while( not $smtp->data() )
		    {
			if( $datawait ++ > 10 )
			{
			    debug "timeout waiting for data ready";
			    last SEND;
			}
			debug "waiting for data ready";
			sleep 0.2 * $datawait;
		    }
		    $smtp->datasend($$dataref) or last SEND;
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
	    my $mailhost_err_msg = sprintf "Error response from %s: %s: %s", $mailhost, $smtp->code, $smtp->message;
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

#    debug(1,"Returning status. Error set to: $err_msg");

    $s->{error_msg} = $err_msg;

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


##############################################################################

=head2 pgpsign

  pgpsign( $dataref, $configfile )

This is called by C<$s-C<gt>send()> if the param C<pgpsign> has
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

    require Crypt::OpenPGP;
    Crypt::OpenPGP->import();

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

##############################################################################

=head2 generate_message_id

Generates a unique message id, without surrounding <>.

Given in the form $cnt.$epoch.$port.pf\@$fqdn

The C<pf> is for giving som kind of namespace that hopefully will
differ it from other mail services on this domain.

Supported args are:

  time

Returns: The message id, without surrounding <>

=cut

sub generate_message_id
{
    my( $this, $args ) = @_;

    $args ||= {};

    my $now = $args->{'time'} || now();

    my $right = fqdn();

    # Combination of time port and counter should be unique

    my $port = $Para::Frame::CFG->{'port'};
    my $epoch = $now->epoch;
    my $count = ++ $COUNTER;

    my $left = $count .".". $epoch .".". $port .".". "pf";

    return $left .'@'. $right;
}

##############################################################################

=head2 renderer

=cut

sub renderer
{
    return $_[0]->{renderer} ||=
      Para::Frame::Renderer::Email->new({params=>$_[0]->{'params'}});
}

##############################################################################

=head2 email

=cut

sub email
{
    return $_[0]->renderer->email;
}

##############################################################################


1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::Email::Address>

=cut
