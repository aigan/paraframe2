#  $Id$  -*-perl-*-
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
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Email - Sending emails

=cut

use strict;
use Carp;
use locale;
use Data::Dumper;
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
use Para::Frame::Utils qw( throw debug );
use Para::Frame::Widget;

sub new
{
    my( $class, $p ) = @_;
    my $req = $Para::Frame::REQ;

    my $e = bless
    {
	params =>
	{
	    'u'        => $req->s->u,
	    'q'        => $req->q,
	    'date'     => sub{ date(@_) },
	    'site'     => $req->site,
	},
    }, $class;

    $e->set($p) if $p;
    return $e;
}

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

sub params
{
    return $_[0]->{params};
}

sub good
{
    my( $e, $email ) = @_;

    # scalar $e->good  # returns ref to array of strings of successful emails
    # @list = $e->good # returns list of hashes of strings of successful emails
    # $e->good( $email_str ) # returns true if email string recorded as positive

    if( $email )
    {
    	return $e->{'result'}{'good'}{$email};
    }

    return wantarray ? keys %{$e->{'result'}{'good'}} : $e->{'result'}{'good'};
}

sub bad
{
    my( $e, $email ) = @_;

    if( $email )
    {
	return $e->{'result'}{'bad'}{$email};
    }

    return wantarray ? keys %{$e->{'result'}{'bad'}} : $e->{'result'}{'bad'};
}

sub error_msg
{
    return $_[0]->{error_msg} || "";
}

=head2 send_in_fork

  $e->send_in_fork(\%params)

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

sub send
{
    my($e, $p_in ) = @_;

    # DEBUG...
    unless( $Para::SITE_CFG->{'send_email'} )
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

    my $req = $Para::Frame::REQ;

    # List of addresses to try. Quit after first success
    my @try = ref $p->{'to'} eq 'ARRAY' ? @{$p->{'to'}} : $p->{'to'};

    my( $in, $ext ) = $req->find_template("/email/".$p->{'template'});
    if( not $in )
    {
	throw('notfound', "Hittar inte e-postmallen ".$p->{'template'});
    }


    my $burner = $Para::Frame::CFG->{'th'}{'plain'};

    if( debug )
    {
	my $providers =  $burner->providers;
	debug(0,"Plain include path is: @{$providers->[0]->include_path()}");
    }


    # Clone params for protection from change
    my %params = %$p;

    my $data = "";
    $burner->burn( $in, \%params, \$data ) or throw($burner->error);

    if( $p->{'pgpsign'} )
    {
	pgpsign(\$data, $p->{'pgpsign'} );
    }

    my( $from_addr ) = Para::Frame::Email::Address->parse( $p->{'from'} );
    $from_addr or
      throw('mail', "Failed to parse address $p->{'from'}\n");
#    my $from_addr_str = $from_addr->address;


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
              Encoding => '8bit',
	     );
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
#	    $msg->attr('content-type.charset' => 'ISO-8859-1');
	}

	if( $p->{'Reply-To'} )
	{
	    $msg->add('Reply-To' =>  $p->{'Reply-To'} );
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
	    debug(0,"Connecting to $mailhost",1);

	    my $smtp = Net::SMTP->new( Host    => $mailhost,
				       Timeout => 60,
				       Debug   => 0,
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
		    debug(0,sprintf("Connected to %s", $smtp->domain));
		    
		    debug(0,"Sending mail to $to_addr_str");
		    $smtp->mail($from_addr->address) or last SEND;
		    $smtp->to($to_addr_str) or last SEND;
		    $smtp->data() or last SEND;
		    $smtp->datasend($msg->as_string) or last SEND;
		    $smtp->dataend() or last SEND;
		    $smtp->quit() or last SEND;

		    # Success!
		    debug(2,"Success",-2);
		    $res->{'good'}{$to_addr_str} ||= [];
		    push @{$res->{'good'}{$to_addr_str}}, $smtp->message();
		    last TRY;
		}
		$err_msg .= debug(0,"No answer from mx $mailhost",-1);
		next MX;
	    }

	    $res->{'bad'}{$to_addr_str} ||= [];
	    push @{$res->{'bad'}{$to_addr_str}}, $smtp->message();
	    $err_msg .= debug(0,"Error response from $mailhost: ".$smtp->message());
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

sub encode_mimewords
{
    my $string = MIME::Words::encode_mimewords($_[0]);
    $string =~ s/\?= =\?ISO-8859-1\?Q\?/?= =?ISO-8859-1?Q?_/g;
    return $string;
}

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

1;
