#  $Id$  -*-perl-*-
package Para::Frame::Time;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Request class
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

Para::Frame::Time

=cut

# Override Time::Piece with some new things
use strict;
use Time::Piece;
use Date::Manip;
use Carp qw( cluck );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

#use Para::Frame::Reload; # This code is mingled with Time::Piece

use Para::Frame::Utils qw( throw );

sub import { shift; @_ = ('Time::Piece', @_); goto &Time::Piece::import }


=head1 DESCRIPTION

Modification of L<Time::Piece>, it automaticly strinigifies to the
format C<%Y-%m-%d %H.%M>.

=cut

sub get
{
    my( $this, $time ) = @_;
    my $DEBUG = 1;

    Date_Init("Language=English");
    Date_Init("Language=Swedish"); # Reset language

    warn "Parsing date '$time'\n" if $DEBUG;

    return undef unless $time;

    my $date;
    if( $time =~ /^\d{7,}$/ )
    {
	$date = $time;
    }
    else
    {
	$time =~ s/^(\d{4}-\d{2}-\d{2} \d{2})\.(\d{2})$/$1:$2:00/; # Make date more recognizable
	$date = UnixDate($time, '%s');
    }
    warn "  Epoch: $date\n" if $DEBUG;
    unless( $date )
    {
 	# Try once more, in english
	my $cur_lang = $Date::Manip::Cnf{'Language'};
	warn "Trying in english...\n" if $DEBUG;
	Date_Init("Language=English");

	$date = UnixDate($time, '%s');
	warn "    Epoch: $date\n" if $DEBUG;

	Date_Init("Language=$cur_lang"); # Reset language

	unless( $date )
	{
	    cluck;
	    throw('validation', "Time format '$time' not recognized");
	}
    }
    my $to = localtime( $date );
    warn "  Finaly: $to\n" if $DEBUG;
    return $to;
}

### New methods

package Time::Piece;

BEGIN
{
    $^W = 0; # Ignore warning about redefine overload
}

use Date::Manip;
use overload '""' => \&stamp;

#use vars qw( @ISA );
#push @ISA, qw( Para::Frame::Literal );


sub stamp { shift->strftime('%Y-%m-%d %H.%M' ) }

sub desig
{
    return $_[0]->stamp;
}


sub sysdesig
{
    return sprintf("Date %s", $_[0]->stamp);
}

sub defined { 1 }

sub plain { $_[0]->stamp }

#######################################################################

=head3 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return sprintf("time:%d", UnixDate(shift, '%s'));
}


#######################################################################

=head2 equals

=cut

sub equals
{
    my( $val1, $val2 ) = @_;

#    warn "Checking equality of two dates\n";
#    warn "  Date 1: $val1\n";
#    warn "  Date 2: $val2\n";

    return( $val1 == $val2 );
}


######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>,
L<Time::Piece>

=cut
