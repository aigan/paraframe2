#  $Id$  -*-cperl-*-
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
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Email::Address - Represents an email address

=cut

use strict;
use Net::DNS;
use Net::SMTP;
use Mail::Address;
use Carp qw( carp confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw reset_hashref fqdn debug );

use overload '""' => \&as_string;
use overload 'eq' => \&equals;
use overload 'ne' => sub{ not &equals(@_) };

=head1 DESCRIPTION

Objects of this class is a container for L<Mail::Address> objects. It
stringifies to L</as_string> and uses L</equals> for C<eq>/C<ne>
comparsions.

=cut


#######################################################################

=head2 parse

  Para::Frame::Email::Address->parse( $email_in )

This is the object constructor.

If C<$email_in> already is an Para::Frame::Email::Address object;
retuns it.

Parses the address using L<Mail::Address/parse>.

Checks that the domain name was given.

Returns the object.

Exceptions:

email - '$email_str_in' is not a correct email address

email - Give the whole email address, includning the \@\n'$email_str_in' is not correct

=cut

sub parse
{
    my( $class, $email_str_in ) = @_;

    # OBS: Should not be called as a constructor by subclasses
    if( $class eq "Para::Member::Email::Address" )
    {
	confess "check this";
    }

    # May change the object class belonging
    return $email_str_in
	if UNIVERSAL::isa($email_str_in, $class);

    my $addr;
    if( UNIVERSAL::isa $email_str_in, "Para::Frame::Email::Address" )
    {
	# We are upgrading to a superclass
	confess "check this";
	$addr = $email_str_in->{'addr'};
    }
    else
    {
	# Retrieve first in list
	( $addr ) = Mail::Address->parse( $email_str_in );
    }

    $addr or throw('email', "'$email_str_in' is not a correct email address");

    unless( $addr->host )
    {
	throw('email', "Give the whole email address, includning the \@\n'$email_str_in' is not correct");
    }

    my $a = bless { addr => $addr }, $class;

    return $a;
}


#######################################################################

=head2 as_string

  $a->as_string

Returns a string using L<Mail::Address/address>

=cut

sub as_string { $_[0]->{addr}->address }


#######################################################################

=head2 user

  $a->user

Returns a string using L<Mail::Address/user>

=cut

sub user { $_[0]->{addr}->user }


#######################################################################

=head2 address

  $a->address

Returns a string using L<Mail::Address/address>

=cut

sub address { $_[0]->{addr}->address }


#######################################################################

=head2 host

 $a->host

Returns a string using L<Mail::Address/host>

=cut

sub host { $_[0]->{addr}->host }


#######################################################################

=head2 format

 $a->format

Returns a string using L<Mail::Address/format>

=cut

sub format { $_[0]->{addr}->format }


#######################################################################

=head2 format_human

 $a->format_human

Returns a human readable version of the object including the name if
existing.

=cut

sub format_human
{
    my( $a ) = @_;
    if( $a->name )
    {
	return sprintf "%s <%s>", $a->name, $a->address;
    }
    else
    {
	return $a->address;
    }
}


#######################################################################

=head2 name

  $a->name

Returns the name for the email address.

=cut

sub name
{
    return shift->{addr}->name(@_);
}


#######################################################################

=head2 desig

  $a->desig

Gives a resonable designation of the object. In this case, the name or
the address.

=cut

sub desig
{
    my( $a ) = @_;
    return $a->name || $a->address;
}

# sub update
# {
#     my( $a, $a_in ) = @_;
# 
#     my $a_new = $a->parse( $a_in );
# 
#     reset_hashref( $a );
# 
#     $a->{'addr'} = $a_new->{'addr'};
# 
#     return $a;    
# }


#######################################################################

=head2 validate

 $a->validate

Checks that the address is valid.  Checks that the domain exists and
that it accepts email. If possible, checks that the email address
exists at that domain.

Returns true if address was validated.

If the address was not validated, throws an exception.

Exceptions:

email - ... an explanation of what went wrong ...

=cut

sub validate
{
    my( $a ) = @_;

    my $fork = $Para::Frame::REQ->create_fork;
    if( $fork->in_child )
    {
	my $success = $a->_validate;
	$fork->{'error_msg'} = $a->{'error_msg'};
	$fork->{'success'} = $success;
	$fork->return;
    }
    $fork->yield;

    $a->{'error_msg'} = $fork->result->{'error_msg'};
    throw('email', $a->{'error_msg'}) unless $fork->result->{'success'};
    return 1;
}

sub _validate
{
    my( $a ) = @_;

    my $err_msg = "";

    my( $host ) = $a->host() or die;
    my $fqdn = fqdn;

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
	    debug "Guess $host";
	    my $res   = Net::DNS::Resolver->new;
	    my $query = $res->query($host);
	    if ($query)
	    {
		foreach my $rr ($query->answer)
		{
		    next unless $rr->type eq "A";
		    push @mailhost_list, $host;
		    debug "  Yes, maby.";
		    next HOST;
		}
	    }
	    else
	    {
		debug "  No answer...";
	    }
	}
	if( @mailhost_list )
	{
	    $err_msg .= "  But I'll try anyway (guessing mailserver)\n";
	}
	else
	{
	    $a->{'error_msg'} = $err_msg;
	    $a->{'error_msg'} = "$host finns inte";
	    return 0;
	}
    }
  MX:
    foreach my $mailhost ( @mailhost_list )
    {
	debug "Connecting to $mailhost";
      TRY:
	for my $i (1..3) # hotmail is stupid
	{
	    my $smtp = Net::SMTP->new($mailhost,
				      Timeout => 30,
				      Debug   => 0,
				      Hello   => $fqdn,
				      );
	  SEND:
	    {
		if( $smtp )
		{
		    debug "Connected";
		    # Returns localhost if host nonexistant
		    my $domain = $smtp->domain();
		    $domain or last SEND;
		    debug "Domain: $domain";
		    $smtp->quit() or last SEND;
		    debug "Success";
		    debug "Warnings:\n$err_msg" if $err_msg;
		    return 1;
		}
		debug "No answer from $mailhost";
		$err_msg .= "No answer from mx $mailhost\n" if $i == 1;

		sleep(2); # We are inside a fork!

		next TRY;
	    }
	    debug "Error response from $mailhost: ".$smtp->message();
	    $err_msg .= "Error response from $mailhost: ".$smtp->message()."\n";
	}
	next MX;
    }
    debug "Address bad";
    $a->{'error_msg'} = $err_msg;
    return 0;
}


#######################################################################

=head2 error_msg

  $a->error_msg

Returns the error message from the latest validation.

=cut

sub error_msg
{
    return $_[0]->{'error_msg'};
}


#######################################################################

=head2 equals

  $a->equals($a2)

Makes $a2 a atring if it is an object using L</as_string>.

Checks that the two strings are equal.

Returns true or false.

=cut

sub equals
{
    my( $a, $a2_in ) = @_;

    $a2_in ||= "";
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


#######################################################################

=head1 Global TT params

Adds C<email> as an global tt param. Uses L</parse>.

=cut


#######################################################################

=head2 on_configure

=cut

sub on_configure
{
    my( $class ) = @_;

    my $params =
    {
	'email'         => sub{ $class->parse(@_) },
    };

    Para::Frame->add_global_tt_params( $params );
}

######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<Mail::Address>

=cut
