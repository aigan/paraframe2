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
use POSIX qw(locale_h strftime);
use Time::Piece;
use Date::Manip;
use Carp qw( cluck );
use Data::Dumper;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

our @EXPORT_OK = qw(internet_date date now ); #for docs only

#use Para::Frame::Reload; # This code is mingled with Time::Piece

use Para::Frame::Utils qw( throw debug );

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

    # Pretend to be Time::Piece
    @_ = ('Time::Piece'); # Do not forward @_
    goto &Time::Piece::import;
}


=head1 DESCRIPTION

Modification of L<Time::Piece>, it automaticly strinigifies to the
format C<%Y-%m-%d %H.%M>.

=cut

=head2 get

  Para::Frame::Time->get( $any_type_of_date )

Parses everything and returns object

=cut

sub get
{
    my( $this, $time ) = @_;

    return $time if UNIVERSAL::isa $time, "Time::Piece";

    debug(3,"Parsing date '$time'");

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
    my $to = localtime( $date );
    debug(4,"Finaly: $to");
    return $to;
}

=head2 now

  now() # Exportable

Same as the overloaded localtime(), except that it works even in list
context

=cut

sub now
{
    return scalar localtime;
}

=head2 date

  date($any_string) #exportable

Same as Para::Frame::Time->get()

=cut

sub date
{
    return Para::Frame::Time->get(@_);
}


=head2 internet_date

  internet_date()
  internet_date($time)

Returns a date in a format suitable for use in SMTP or HTTP headers.

=cut

sub internet_date
{
    my $old = setlocale(LC_TIME);
    setlocale(LC_TIME, "C");
    my $res = strftime('%a, %d %b %Y %T %z', localtime($_[0]));
    setlocale(LC_TIME, $old);
    return $res;
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
