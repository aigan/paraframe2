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
use Time::Piece;
use Date::Manip;
use Clone qw( clone );
use vars qw( $VERSION );
use Mail::Address;
use MIME::Lite;
use Net::DNS;
use Net::SMTP;
use MIME::Words;
use Crypt::OpenPGP;

BEGIN
{
    $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use Para::Frame::Request;
use Para::Frame::Utils qw( throw );

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

sub send
{
    my($e, $p_in ) = @_;

    my $DEBUG = 1;
    my $err_msg = "";
    my $res = $e->{'result'} = {}; # Reset results
    my $p = $e->set( $p_in );

    $p->{'template'} or die "No template selected\n";
    $p->{'from'}     or die "No from selected\n";
    $p->{'subject'}  or die "No subject selected\n";
    $p->{'to'}       or die "No reciever for this email?\n";

    # List of addresses to try. Quit after first success
    my @try = ref $p->{'to'} eq 'ARRAY' ? @{$p->{'to'}} : $p->{'to'};

    my $req = $Para::Frame::REQ;
    my( $in, $ext ) = $req->find_template("/email/".$p->{'template'});
    if( not $in )
    {
	$req->result->error('notfound', "Hittar inte e-postmallen ".$p->{'template'});
    }


    if( $DEBUG )
    {
	#warn "try addresses: ".join(",", @try)."...\n";

	my $providers =  $Para::Frame::th->{'plain'}->context->load_templates();
	warn "Plain include path is: @{$providers->[0]->include_path()}\n";
    }

    my $data = "";
    $Para::Frame::th->{'plain'}->process($in, $p, \$data) or
	throw('template', "Template error: ".$Para::Frame::th->{'plain'}->error );

    if( $p->{'pgpsign'} )
    {
	pgpsign(\$data, $p->{'pgpsign'} );
    }

    my( $from_addr ) = Para::Frame::Email::Address->parse( $p->{'from'} );
    $from_addr or
      thtow('mail', "Failed to parse address $p->{'from'}\n");
    my $from_addr_str = $from_addr->address;


  TRY:
    foreach my $try ( @try )
    {
	$try or warn "Empty email\n" and next;

	my( $to_addr ) = Para::Frame::Email::Address->parse( $try );
	unless( $to_addr )
	{
	    $res->{'bad'}{$try} ||= [];
	    push @{$res->{'bad'}{$try}}, "Failed parsing";
	    warn "Failed parsing $try\n";
	    next;
	}
	my $to_addr_str = $to_addr->address;

	my $msg;

	# I don't know.  Trying to mimic others
	if( $p->{'pgpsign'} )
	{
	    $msg = MIME::Lite->new(
	      From     => $from_addr_str,
	      To       => $to_addr_str,
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
	      From     => encode_mimewords($from_addr_str),
	      To       => encode_mimewords($to_addr_str),
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


	my( $host ) = $to_addr->host();
	unless( $host )
	{
	    $res->{'bad'}{$try} ||= [];
	    push @{$res->{'bad'}{$try}}, "Nu such host";
	    warn "Nu such host: $try\n";
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
	    $err_msg .= "Domain $host do not accept email (No MX record)\n";
	    unless( $host =~ /^mail\./ )
	    {
		push @mailhost_list, "mail.$host";
	    }
	    push @mailhost_list, $host;
	    $err_msg .= "  But I'll try anyway (guessing mailserver)\n";
	}
      MX:
	foreach my $mailhost ( @mailhost_list )
	{
	    warn "\tConnectiong to $mailhost\n";

	    my $smtp = Net::SMTP->new($mailhost,
				      Timeout => 60,
				      Debug   => 0,
				     );
	  SEND:
	  {
	      if( $smtp )
	      {
		  warn "\tSending mail to $to_addr_str\n";
		  $smtp->mail($from_addr_str) or last SEND;
		  $smtp->to($to_addr_str) or last SEND;
		  $smtp->data() or last SEND;
		  $smtp->datasend($msg->as_string) or last SEND;
		  $smtp->dataend() or last SEND;
		  $smtp->quit() or last SEND;

		  # Success!
		  warn "Success\n";
		  $res->{'good'}{$try} ||= [];
		  push @{$res->{'good'}{$try}}, $smtp->message();
		  last TRY;
	      }
	      warn "\tNo answer from $mailhost\n";
	      $err_msg .= "No answer from mx $mailhost\n";
	      next MX;
	  }

	    $res->{'bad'}{$try} ||= [];
	    push @{$res->{'bad'}{$try}}, $smtp->message();
	    warn "$:: \tError response from $mailhost: ".$smtp->message()."\n";
	    $err_msg .= "Error response from $mailhost: ".$smtp->message()."\n";
	}
	warn "\tAddress bad\n";
    }

    warn "Returning status. Error set to: $err_msg\n" if $DEBUG;

    $e->{error_msg} = $err_msg;

    if( $res->{'good'} )
    {
	warn "Returning success\n";
	return 1;
    }
    else
    {
	warn "Returning failure\n";
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

    warn "Signing email\n";
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
