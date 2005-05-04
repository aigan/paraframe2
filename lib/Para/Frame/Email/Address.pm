#  $Id$  -*-perl-*-
package Para::Frame::Email::Address;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Email Address class
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

Para::Frame::Email::Address

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Net::DNS;
use Net::SMTP;
use Mail::Address;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw );

sub parse
{
    my( $class, $email_str_in ) = @_;

    return $email_str_in if UNIVERSAL::isa($email_str_in, "Para::Frame::Email::Address");

    warn "Parsing email string '$email_str_in'\n";
    my( $addr ) = Mail::Address->parse( $email_str_in );

    $addr or throw('email', "'$email_str_in' är inte en korrekt e-postadress\n");

    unless( $addr->host )
    {
	throw('email', "Ange hela adressen, inklusive \@\n'$email_str_in' är inte korrekt");
    }

    my $a = bless { addr => $addr }, $class;

    return $a;
}

sub as_string { $_[0]->{addr}->address }

sub address { $_[0]->{addr}->address }

sub host { $_[0]->{addr}->host }

sub validate
{
    my( $a ) = @_;

    my $err_msg = "";

    my( $host ) = $a->host() or die;

    my @mx_list = mx($host);
    my @mailhost_list;
    foreach my $mx ( @mx_list )
    {
	push @mailhost_list, $mx->exchange();
    }
    unless( @mailhost_list )
    {
	$err_msg .= "Domain $host do not accept email (No MX record)\n";
	my @host_list;
	unless( $host =~ /^mail\./ )
	{
	    push @host_list, "mail.$host";
	}
	push @host_list, $host;

      HOST:
	foreach my $host ( @host_list )
	{
	    warn "Guess $host\n";
	    my $res   = Net::DNS::Resolver->new;
	    my $query = $res->query($host);
	    if ($query)
	    {
		foreach my $rr ($query->answer)
		{
		    next unless $rr->type eq "A";
		    push @mailhost_list, $host;
		    warn "  Yes, maby.\n";
		    next HOST;
		}
	    }
	    else
	    {
		warn "  No answer...\n";
	    }
	}
	if( @mailhost_list )
	{
	    $err_msg .= "  But I'll try anyway (guessing mailserver)\n";
	}
	else
	{
	    $a->{'error_msg'} = $err_msg;
	    throw('email', "$host finns inte");
	}
    }
  MX:
    foreach my $mailhost ( @mailhost_list )
    {
	warn "\tConnecting to $mailhost\n";
      TRY:
	for my $i (1..3) # hotmail is stupid
	{
	    my $smtp = Net::SMTP->new($mailhost,
				      Timeout => 30,
				      Debug   => 0,
				      );
	  SEND:
	    {
		if( $smtp )
		{
		    warn "\tConnected\n";
		    # Returns localhost if host nonexistant
		    my $domain = $smtp->domain();
		    $domain or last SEND;
		    warn "\tDomain: $domain\n";
		    $smtp->quit() or last SEND;
		    warn "Success\n";
		    warn "Warnings:\n$err_msg\n" if $err_msg;
		    return 1;
		}
		warn "\tNo answer from $mailhost\n";
		$err_msg .= "No answer from mx $mailhost\n" if $i == 1;
		sleep 2;
		next TRY;
	    }
	    warn "\tError response from $mailhost: ".$smtp->message()."\n";
	    $err_msg .= "Error response from $mailhost: ".$smtp->message()."\n";
	}
	next MX;
    }
    warn "\tAddress bad\n";
    $a->{'error_msg'} = $err_msg;
    throw('email', $err_msg);
}

sub error_msg
{
    return $_[0]->{'error_msg'};
}

sub equals
{
    my( $a, $a2_in ) = @_;

    my $a2_as_string;
    if( ref $a2_in )
    {
	if( $a2_in->isa( "Para::Frame::Email::Address" ) )
	{
	    $a2_as_string = $a2_in->as_string;
	}
	else
	{
	    die;
	}
    }
    else
    {
	$a2_as_string = $a2_in;
    }

    return $a->as_string eq $a2_as_string;
}

######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>,

=cut
