#  $Id$  -*-perl-*-
package Para::Frame::Time;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Time class
#
# Parses with Date::Manip and returns a modified Time::Piece object
# Also supports returning DateTime objects
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
#use POSIX qw(locale_h);
use Carp qw( cluck );
use Data::Dumper;
use Date::Manip;
use DateTime;
use DateTime::Duration;
use DateTime::Span;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use base qw( DateTime );

our $TZ; # Default Timezone, set in Para::Frame->configure
# Use timezone only for presentation. Not for date calculations

our @EXPORT_OK = qw(internet_date date now timespan duration ); #for docs only

use Para::Frame::Reload; # This code is mingled with DateTime...
use Para::Frame::Utils qw( throw debug );

no warnings 'redefine';
sub import
{
    my $class = shift;

    # Initiate Date::Manip
    Date_Init("Language=English");
    Date_Init("Language=Swedish"); # Reset language

    #Export functions like Exporter do
    my $callpkg = caller();
    no strict 'refs'; # Symbolic refs
    *{"$callpkg\::$_"} = \&{"$class\::$_"} foreach @_;
}


=head1 DESCRIPTION

Subclass to L<DateTime>, it automaticly strinigifies to the
format C<%Y-%m-%d %H.%M>.

=cut

=head2 get

  Para::Frame::Time->get( $any_type_of_date )

Parses everything and returns object

=cut

sub get
{
    my( $this, $time ) = @_;

    return $time if UNIVERSAL::isa $time, "DateTime";

    return undef unless $time;

    debug(3,"Parsing date '$time'");

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
    debug(5,"Epoch: $date");
    unless( $date )
    {
 	# Try once more, in english
	my $cur_lang = $Date::Manip::Cnf{'Language'};
	debug(1,"Trying in english...");
	Date_Init("Language=English");

	$date = UnixDate($time, '%s');
	debug(1,"Epoch: $date");

	Date_Init("Language=$cur_lang"); # Reset language

	unless( $date )
	{
	    cluck;
	    throw('validation', "Time format '$time' not recognized");
	}
    }
    my $to = $this->from_epoch( epoch => $date );
    debug(4,"Finaly: $to");
    return $to;
}

=head2 now

  now() # Exportable

Returns obj representing current time

=cut

sub now
{
    Para::Frame::Time->SUPER::now();
}
  
=head2 date

  date($any_string) #exportable

Same as Para::Frame::Time->get()

=cut

sub date
{
    return Para::Frame::Time->get(@_);
}


=head2 timespan

  timespan($from, $to) #exportable

Returns a DateTime::Span object.

Use undef value for setting either $from or $to to infinity

This returns a closed span, including its end-dates.

For other options, use DateTime::Span directly

=cut

sub timespan
{
    my( $from_in, $to_in ) = @_;

    my @args;

    if( $from_in )
    {
	my $from = Para::Frame::Time->get($from_in);
	push @args, ( start => $from );
    }

    if( $to_in )
    {
	my $to = Para::Frame::Time->get($to_in);
	push @args, ( end => $to );
    }

    return Para::Frame::Time->from_datetimes( @args );
}


=head2 duration

  duration( %params ) #exportable

Returns a DateTime::Duration object.

=cut

sub duration
{
    return DateTime::Duration->new( @_ );
}


=head2 internet_date

  internet_date()
  internet_date($time)

Returns a date in a format suitable for use in SMTP or HTTP headers.

=cut

sub internet_date
{
#    my $old = setlocale(LC_TIME);
#    setlocale(LC_TIME, "C");
    my $res = strftime('%a, %d %b %Y %T %z', Para::Frame::Time->get($_[0]));
#    setlocale(LC_TIME, $old);
    return $res;
}

sub cdate
{

    # TODO: Remove me. This is not realy a cdate format. Used for
    # fromatting dates for the DB. Change to use the specific dbix
    # datetime_format function

    $_[0]->clone->set_time_zone($TZ)->strftime('%Y-%m-%d %H:%M:%S');
 }

sub format_datetime
{
    $_[0]->clone->set_time_zone($TZ)->strftime('%Y-%m-%d %H.%M' )
}

sub stamp
{
    $_[0]->format_datetime;
}

sub desig
{
    $_[0]->format_datetime;
}

sub plain
{
    $_[0]->format_datetime;
}

sub sysdesig
{
    return sprintf("Date %s", $_[0]->strftime('%Y-%m-%d %H.%M.%S %z' ));
}

sub defined { 1 }

#######################################################################

=head3 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return $_[0]->iso8601;
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


############################################################
############################################################
#
# Change overload behaviour in DateTime::Duration
{
    no warnings;
    package DateTime::Duration;

    sub _compare_overload
    {
	my( $d1, $d2, $rev ) = @_;
	($d1, $d2) = ($d2, $d1) if $rev;
	return DateTime::Duration->compare( $d1, $d2 );
    }
}

############################################################
############################################################
#
# Add overload for stringify in DateTime::Span

package DateTime::Span;
    
use overload
    (
    '""' => '_stringify_overload',
    '<=>' => '_compare_overload',
    );

sub _stringify_overload
{
    my $start = $_[0]->start;
    my $end   = $_[0]->end;
    
    return "$start - $end";
}

sub _compare_overload
{
    my( $s1, $s2, $rev ) = @_;

    if( $rev )
    {
	if( $s2->isa('DateTime::Span') )
	{
	    return DateTime::Duration->compare($s2->duration,
					       $s1->duration,
					       $s1->start );
	}
	else
	{
	    return DateTime::Duration->compare($s2,
					       $s1->duration,
					       $s1->start );
	}
    }
    else
    {
	if( $s2->isa('DateTime::Span') )
	{
	    return DateTime::Duration->compare($s1->duration,
					       $s2->duration,
					       $s1->start );
	}
	else
	{
	    return DateTime::Duration->compare($s1->duration,
					       $s2,
					       $s1->start );
	}
    }
}

############################################################

1;

=head1 SEE ALSO

L<Para::Frame>,
L<Time::Piece>

=cut
