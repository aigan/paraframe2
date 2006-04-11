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

Para::Frame::Time - Parses, calculates and presents dates and times

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

# Use timezone only for presentation. Not for date calculations
our $TZ;     # Default Timezone, set in Para::Frame->configure
our $FORMAT; # Default presentation format.

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

This is a subclass to L<DateTime>, it automaticly strinigifies using
L</format_datetime>.

=cut

=head2 get

  Para::Frame::Time->get( $any_type_of_date )

Parses C<$any_type_of_date> and returns a C<Para::Frame::Time> object.

This handles among other things, swedish and english dates, as
recognized by L<Date::Manip/ParseDateString>.

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

Returns a C<Para::Frame::Time> object representing current time.

=cut

sub now
{
    Para::Frame::Time->SUPER::now();
}

=head2 date

  date($any_string) #exportable

This function calls L</get> whit the given string.

=cut

sub date
{
    return Para::Frame::Time->get(@_);
}


=head2 timespan

  timespan($from, $to) #exportable

Returns a L<DateTime::Span> object.

Use undef value for setting either $from or $to to infinity

This returns a closed span, including its end-dates.

For other options, use L<DateTime::Span> directly

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

    return DateTime::Span->from_datetimes( @args );
}


=head2 duration

  duration( %params ) #exportable

Returns a L<DateTime::Duration> object.

=cut

sub duration
{
    return DateTime::Duration->new( @_ );
}


=head2 internet_date

  internet_date( $time_in_any_format ) # exportable
  $t->internet_date()

Returns a date string in a format suitable for use in SMTP or HTTP
headers.

Can be called as a function or mehtod.

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

=head2 format_datetime

  $t->format_datetime()

Returns a string using the format given by L<Para::Frame/configure>.

=cut

sub format_datetime
{
    $_[0]->clone->set_time_zone($TZ)->strftime($FORMAT)
}

=head2 stamp

  $t->stamp

Same as L</format_datetime>

=cut

sub stamp
{
    $_[0]->format_datetime;
}

=head2 desig

  $t->desig

Same as L</format_datetime>

=cut

sub desig
{
    $_[0]->format_datetime;
}

=head2 plain

  $t->plain

Same as L</format_datetime>

=cut

sub plain
{
    $_[0]->format_datetime;
}

=head2 sysdesig

  $t->sysdesig

Returns a string representation of the object for debug purposes.

=cut

sub sysdesig
{
    return sprintf("Date %s", $_[0]->strftime('%Y-%m-%d %H.%M.%S %z' ));
}

sub defined { 1 }

#######################################################################

=head2 syskey

  $t->syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return $_[0]->iso8601;
}


#######################################################################

=head2 equals

  $t->equals( $t2 )

Returns true if both objects has the same value.

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
L<DateTime>,
L<DateTime::Duration>,
L<DateTime::Span>

=cut
