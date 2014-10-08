package Para::Frame::Time;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Time - Parses, calculates and presents dates and times

=cut

use 5.010;
use strict;
use warnings;
use utf8;
use base qw( DateTime );

use Carp qw( cluck carp );
use Date::Manip::Date;
use DateTime; # Should use 0.3, but not required
use DateTime::Duration;
use DateTime::Span;
use DateTime::Format::Strptime;
use DateTime::Format::HTTP;


# These are set in Para::Frame->configure
# Use timezone only for presentation. Not for date calculations
our $TZ;           # Default Timezone
our $FORMAT;       # Default format
our $STRINGIFY;    # Default format used for stringification
our $LOCAL_PARSER; # For use with Date::Manip
our %DM;           # DateManip objects
our $BASE_DATE;    # See set_base()

our @EXPORT_OK = qw(internet_date date now timespan duration ); #for docs only

use Para::Frame::Reload; # This code is mingled with DateTime...
use Para::Frame::Utils qw( throw debug datadump );

no warnings 'redefine';
sub import
{
    my $class = shift;

    # Initiate Date::Manip
    $DM{'en'} = new Date::Manip::Date;
    $DM{'en'}->config("Language","English","DateFormat","non-US");
    _patch_dm_formats( $DM{'en'} );

#    Date_Init("Language=English");
#    Date_Init("Language=Swedish"); # Reset language



    #Export functions like Exporter do
    my $callpkg = caller();
    no strict 'refs'; # Symbolic refs
    *{"$callpkg\::$_"} = \&{"$class\::$_"} foreach @_;


    $LOCAL_PARSER =
      DateTime::Format::Strptime->new( pattern => '%Y%m%d%H:%M:%S',
				       time_zone => 'floating',
                                     );
}


# Based om Date::Extract (used in _extract_date )
#
our $rx_relative_en          = '(?:today|tomorrow|yesterday)';
our $rx_relative_sv          = '(?:idag|imorgon|igår)';
our $rx_long_weekday_en      = '(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)';
our $rx_long_weekday_sv      = '(?:Måndag|Tisdag|Onsdag|Torsdag|Fredag|Lördag|Söndag)';
our $rx_short_weekday_en     = '(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)';
our $rx_short_weekday_sv     = '(?:Mån?|Tis?|Ons?|Tor?|Fre?|Lör?|Sön?)';
our $rx_weekday_en           = "(?:$rx_long_weekday_en|$rx_short_weekday_en)";
our $rx_weekday_sv           = "(?:$rx_long_weekday_sv|$rx_short_weekday_sv)";
our $rx_relative_weekday_en  = "(?:(?:next|previous|last)\\s*$rx_weekday_en)";
our $rx_relative_weekday_sv  = "(?:(?:nästa|förra|föregående)\\s*$rx_weekday_sv)";
our $rx_long_month_en        = '(?:of\\s)?(?:January|February|March|April|May|June|July|August|September|October|November|December)';
our $rx_long_month_sv        = '(?:Januari|Februari|Mars|April|Maj|Juni|Juli|Augusti|September|Oktober|November|December)';
our $rx_short_month_en       = '(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)';
our $rx_short_month_sv       = '(?:Jan|Feb|Mar|Apr|Maj|Jun|Jul|Aug|Sep|Okt|Nov|Dec)';
our $rx_month_en             = "(?:$rx_long_month_en|$rx_short_month_en)";
our $rx_month_sv             = "(?:$rx_long_month_sv|$rx_short_month_sv)";



=head1 DESCRIPTION

Parses with Date::Manip and returns a modified DateTime object
Also supports returning DateTime objects

This is a subclass to L<DateTime>, it automaticly strinigifies using
L</format_datetime> (?).

TODO: Check what it uses for stringification...

=cut


##############################################################################

=head2 get

  Para::Frame::Time->get( $any_type_of_date )

Parses C<$any_type_of_date> and returns a C<Para::Frame::Time> object.

This handles among other things, swedish and english dates, as
recognized by L<Date::Manip/ParseDateString>.

The object is set to use the current locale and current timezone for display.

Make sure that the C<$any_type_of_date> has the timezone defined.
Dates with an unspecified timezone will be asumed to be in the local
timezone (and not in UTC). This means that dates and times parsed from
HTML forms will be taken to be the local time.

If you parse dates from a SQL database, make sure it has a defiend
timezone, or is in the local timezone, or set the timezone yourself
BEFORE you call this method.

=cut

sub get
{
    my( $this, $time ) = @_;

    return undef unless $time;

    my $DEBUG = 0;


    my $class = ref($this) || $this;
    if( UNIVERSAL::isa $time, "DateTime" )
    {
	if( UNIVERSAL::isa $time, $class )
	{
	    debug "Keeping date '$time'" if $DEBUG;
	    return $time;
	}
	else
	{
	    # Rebless in right class. (May be subclass)
	    debug "Reblessing date '$time'" if $DEBUG;
	    return bless $time, $class;
	}
    }

    # Trimming
    $time =~ s/\s+$//;
    $time =~ s/^\s+//;

    my $tz = $TZ;

    debug "Parsing date '$time'" if $DEBUG;

    my $date;
    if( $time =~ /^(\d{7,})([,\.]\d+)?$/ )
    {
	# Epoch time. Maby with subsecond precision
	debug "  as epoch" if $DEBUG;
	$date = DateTime->from_epoch( epoch => $1 );
    }
    else
    {
	debug "Parsing with standard format" if $DEBUG;

	eval{ $date = $FORMAT->parse_datetime($time) };
    }

    unless( $date ) # Handling common compact dates and times
    {
	# Recognized formats:
	#
	# 090102
	# 20090102
	# 09-01-02
	# 2009-01-02
	# date 304
	# date 0304
	# date 3:04
	# date 03:04
	# date 3.04
	# date 03.04
	# date 30405
	# date 030405
	# date 3.04.05
	# date 03.04.05
	# date 3:04:05
	# date 03:04:05

	if( $time =~ /^(19|20)?(\d\d)(-)?(\d\d)\3?(\d\d)(?:\s+(\d\d?)(\.|:)?(\d\d)(?:\7(\d\d))?)?\s*$/ )
	{
	    debug "Parsing date in compact format" if $DEBUG;

	    my $cent = $1 || 20;
	    my $year = $cent . $2;
	    my $month = $4;
	    my $day = $5;

	    my $hour = $6 || 0;
	    my $min = $8 || 0;
	    my $sec = $9 || 0;

	    $date = DateTime->new( year => $year,
				   month => $month,
				   day => $day,
				   hour => $hour,
				   minute => $min,
				   second => $sec,
				 );
	}
    }


    unless( $date )
    {
	debug "Parsing common formats" if $DEBUG;

# NOTE: Give example of good reason before activating this
#	if( $time =~ s/([\+\-]\d\d)\s*$/${1}00/ )
#	{
#	    debug "Reformatted date to '$time'" if $DEBUG;
#	}

	eval{ $date = DateTime::Format::HTTP->parse_datetime( $time, $tz ) };
    }

    my $lang;

    unless( $date )
    {
        $lang = $Para::Frame::REQ->lang->preferred;

	# Parsing in local timezone
	debug "Parsing universal using lang $lang" if $DEBUG;
        unless( $DM{$lang} )
        {
            $DM{$lang} = new Date::Manip::Date;
            $DM{$lang}->config("Language",$lang,"DateFormat","non-US");
        }

	if( $BASE_DATE )
	{
	    debug "Using base ".$BASE_DATE->desig if $DEBUG;
	    $DM{$lang}->config("setdate",$BASE_DATE->ymd.'-'.$BASE_DATE->hms);
	}

#        my $err = $DM{$lang}->parse($time);
#        debug "Res of parsing is ".$DM{$lang}->value;
#        debug "Err of parsing is $err";

        unless( $DM{$lang}->parse($time) ) # Relative $BASE_DATE
        {
            $date = $LOCAL_PARSER->parse_datetime(scalar $DM{$lang}->value);
        }
        else
        {
            carp( $DM{$lang}->err() ) if $DEBUG;
        }
    }

    unless( $date )
    {
	# Parsing historical years
	if( $time =~ /^-?\d{1,4}$/ )
	{
	    debug "  as historical year" if $DEBUG;
	    $date = DateTime->new( year => $time );
	    return bless($date, $class)->init('floating');
	}
    }

    unless( $date )
    {
 	# Try once more, in english
#	my $cur_lang = $Date::Manip::Cnf{'Language'} || 'English';
	if( $lang ne 'en' )
	{
	    debug "Trying in english...";
#	    Date_Init("Language=English");

	    if( $BASE_DATE )
	    {
		debug "Using base ".$BASE_DATE->desig if $DEBUG;
		$DM{'en'}->config("setdate",$BASE_DATE->ymd.'-'.$BASE_DATE->hms);
	    }

#            debug "Using dm obj ".$DM{'en'};
            unless( $DM{'en'}->parse($time) ) # Relative $BASE_DATE
            {
#		debug "Complete? ".$DM{'en'}->complete;
#                debug( "DM res: ".$DM{'en'}->value );
                $date = $LOCAL_PARSER->parse_datetime(scalar $DM{'en'}->value);
#                debug "DM val ".$date;
            }
            else
            {
                carp( $DM{'en'}->err() ) if $DEBUG;
            }

#	    Date_Init("Language=$cur_lang"); # Reset language
	}

	unless( $date )
	{
	    cluck;
	    throw('validation', "Time format '$time' not recognized");
	}
    }

    if( $date->year < 1900 or $date->year > 2100 )
    {
	debug "Using floating time zone for historic ".$date->iso8601;
	$tz = 'floating';
    }

    return bless($date, $class)->init($tz);
}


##############################################################################

=head2 init

  $time->init()
  $time->init($tz);

=cut

sub init
{
    #debug "Initiating date: $_[0]";
    $STRINGIFY and $_[0]->set_formatter($STRINGIFY);
    eval{ $_[0]->set_time_zone($_[1] || $TZ) };
    if( $@ =~ /^Invalid local time for date/ )
    {
	debug $@;
	debug "Setting UTC for ".$_[0]->sysdesig;
	$_[0]->set_time_zone('UTC');
	undef $@;
    }

    #debug "Finaly: $_[0]";
    return $_[0];
}


##############################################################################

=head2 set_base

  $his->set_base($date)

Setting the base time for parsing relative times, for other than
relative to now.

=cut

sub set_base
{
    my( $this, $base ) = @_;
    $BASE_DATE = $base;
}


##############################################################################

=head2 now

  now() # Exportable

Returns a C<Para::Frame::Time> object representing current time.

=cut

sub now
{
#    cluck "Para::Frame::now called with ".datadump(\@_);
    my $now = bless(DateTime->now())->init;
#    debug "Para::Frame::now returning '$now'";
    return $now;
}


##############################################################################

=head2 date

  date($any_string) #exportable

This function calls L</get> whit the given string.

=cut

sub date
{
    return Para::Frame::Time->get(@_);
}


##############################################################################

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


##############################################################################

=head2 duration

  duration( %params ) #exportable

Returns a L<DateTime::Duration> object.

=cut

sub duration
{
    return DateTime::Duration->new( @_ );
}


##############################################################################

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
    my $res = Para::Frame::Time->get($_[0])->strftime('%a, %d %b %Y %T %z');
#    setlocale(LC_TIME, $old);
    return $res;
}


##############################################################################

=head2 format_datetime

  $t->format_datetime( \%args )

Using the DateTime::Format object given by L<Para::Frame/configure>.

If C<format> are given, its used with L<DateTime/strftime> instead.

Supported args are

  format

Returns a string representing the datetime


=cut

sub format_datetime
{
    my( $t, $args ) = @_;
    $args ||= {};
    if( $args->{'format'} )
    {
	return $t->strftime( $args->{'format'} );
    }

    return $FORMAT->format_datetime($t);
}


##############################################################################

=head2 stamp

  $t->stamp

Same as L</format_datetime>

=cut

sub stamp
{
    $_[0]->format_datetime($_[1]);
}


##############################################################################

=head2 desig

  $t->desig

Same as L</format_datetime>

=cut

sub desig
{
    $_[0]->format_datetime($_[1]);
}


##############################################################################

=head2 plain

  $t->plain

Same as L</format_datetime>

=cut

sub plain
{
    $_[0]->format_datetime($_[1]);
}


##############################################################################

=head2 loc

  $t->loc

Same as L</format_datetime>

TODO: Localize format

=cut

sub loc($)
{
    return $_[0]->format_datetime(undef);
}


##############################################################################

=head2 sysdesig

  $t->sysdesig

Returns a string representation of the object for debug purposes.

=cut

sub sysdesig
{
    return sprintf("Date %s", $_[0]->strftime('%Y-%m-%d %H.%M.%S %z' ));
}


##############################################################################

sub defined { 1 }


##############################################################################

=head2 syskey

  $t->syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return "time:".$_[0]->iso8601;
}


##############################################################################

=head2 equals

  $t->equals( $t2 )

Returns true if both objects has the same value.

=cut

sub equals
{
    my( $val1, $val2 ) = @_;

    return 0 unless UNIVERSAL::isa $val2, 'DateTime';

#    warn "Checking equality of two dates\n";
#    warn "  Date 1: $val1\n";
#    warn "  Date 2: $val2\n";

    return( $val1 == $val2 );
}


##############################################################################

=head2 set_stringify

  $class->set_stringify( 1 )

  $class->set_stringify( $format )

Sets the format for autostringification of all new dates.

C<$format> can be a format for L<DateTime::Format::Strptime> or a
DateTime formatter as explained in L<DateTime/Formatters And
Stringification>. If you call it with '1', it will use C<time_format>
from L<Para::Frame/configure>.

=cut

sub set_stringify
{
    my( $this, $format ) = @_;

    my $class = ref($this) || $this;

    if( $format )
    {
	if( $format =~ /%/ )
	{
	    $STRINGIFY = DateTime::Format::Strptime->
		new(
		    pattern => $Para::Frame::CFG->{'time_format'},
#		    time_zone => $TZ,
		    locale => $Para::Frame::CFG->{'locale'},
		   );
	}
	elsif( ref $format )
	{
	    $STRINGIFY = $format;
	}
	elsif( $format == 1 )
	{
	    $STRINGIFY = $FORMAT;
	}
	elsif( not $format )
	{
	    undef $STRINGIFY;
	}
	else
	{
	    die "Format malformed: $format";
	}
    }

    debug "Stringify now set";

    return $STRINGIFY;
}


##############################################################################

=head2 set_timezone

  $class->set_timezone( ... )

Calls L<DateTime::TimeZone/new> with the first param as the C<name>.

Sets up the environment with the given timezone.

Returns the L<DateTime::TimeZone> object.

=cut

sub set_timezone
{
    my( $this, $name ) = @_;

    $TZ = DateTime::TimeZone->new( name => $name );
    debug "Timezone set to ".$TZ->name;


#    # TODO; DO NOT USE Date::Manip anymore :(
#    die "fixme";
#    Date_Init("TZ=");
}


##############################################################################

=head2 extract_date

  $this->extract_date( $text, $base )

Looked at DateTime::Format::Natural and Date::Extract. No support for
swedish dates...

Should handle different degrees of precision, from month to day.  In
English or Swedish. (Sweden uses it's own variants of english dates)


=cut

sub extract_date
{
    my( $this, $string, $base ) = @_;
#    my $class = ref($this) || $this;

    my( $date ) = $this->_extract_date( $string );
    if( $date )
    {
	debug sprintf "Extracted date '%s' (%d)", $date, length($date);
	# Weekdays always referse to the future

	if( $date =~ /^$rx_long_weekday_en$/i )
	{
	    $date = "next $date";
	}

	if( $date =~ /^$rx_long_weekday_sv$/i )
	{
	    $date = "nästa $date";
	}

	$this->set_base($base) if $base;

        return eval{ $this->get( $date ) };
    }

    return undef;
}


##############################################################################

sub _extract_date
{
    my( $this, $text ) = @_;

    # Based om Date::Extract

    # 1 - 31
    my $cardinal_monthday = "(?:[1-9]|[12][0-9]|3[01])";
    my $monthday          = "(?:$cardinal_monthday(?:st|nd|rd|th|a|e)?)";

    my $day_month         = "(?:$monthday\\s*(?:$rx_month_en|$rx_month_sv))";
    my $month_day         = "(?:(?:$rx_month_en|$rx_month_sv)\\s*$monthday)";
    my $day_month_year    = "(?:(?:$day_month|$month_day)\\s*,?\\s*\\d\\d\\d\\d)";
    my $month_year        = "(?:(?:$rx_month_en|$rx_month_sv)\\s*,?\\s*\\d\\d\\d\\d)";

    my $yyyymmdd          = "(?:\\d\\d\\d\\d[-/]\\d\\d[-/]\\d\\d)";
    my $ddmm              = "(?:\\d\\d?/\\d\\d?)";
    my $ddmmyyyy          = "(?:\\d\\d[-/]\\d\\d[-/]\\d\\d\\d\\d)";
    my $weekday           = "(?:$rx_long_weekday_en|$rx_long_weekday_sv)";
    my $weekday_ddmm      = "$weekday\\s$ddmm";


    my $regex = qr{
        \b(
            $rx_relative_en         # today
          | $rx_relative_sv         # today
          | $rx_relative_weekday_en # last Friday
          | $rx_relative_weekday_sv # last Friday
          | $yyyymmdd         # 1986-11-13
          | $day_month_year   # November 13th, 1986
          | $day_month        # 13th of November
          | $month_day        # Nov 13
	  | $month_year       # Nobvember 1986
	  | $ddmmyyyy         # 13/11/1986
	  | $weekday_ddmm     # Friday 13/11
	  | $ddmm             # 13/11
          | $rx_long_weekday_en          # Monday
          | $rx_long_weekday_sv          # Monday
	  )\b
    }ix;

    return $$text =~ /$regex/gi if ref $text;
    return  $text =~ /$regex/gi;
}

##############################################################################

=head2 _patch_dm_formats

Modify REGEXES from Date::Manip::Date/_other_rx

Added   D/M
Removed YYYY/M/D

Added   mmmYYYY
Removed mmmDDYY

=cut

sub _patch_dm_formats
{
    my( $dm ) = @_;

    my $rx = 'common_2';
    $dm->_other_rx($rx);
    my $dmb = $dm->{tz}{base};

    ### Sanitycheck in case of changed internal format of DM
    die "rx not found in DM"
      unless $$dmb{'data'}{'rx'}{'other'}{$rx};


      my $abb = $$dmb{'data'}{'rx'}{'month_abb'}[0];
      my $nam = $$dmb{'data'}{'rx'}{'month_name'}[0];

      my $y4  = '(?<y>\d\d\d\d)';
      my $y2  = '(?<y>\d\d)';
      my $m   = '(?<m>\d\d?)';
      my $d   = '(?<d>\d\d?)';
      my $dd  = '(?<d>\d\d)';
      my $mmm = "(?:(?<mmm>$abb)|(?<month>$nam))";
      my $sep = '(?<sep>[\s\.\/\-])';

      my $daterx =
#        "${y4}${sep}${m}\\k<sep>$d|" .        # YYYY/M/D
        "${d}\/${m}|" .                         # D/M

        "${mmm}\\s*${dd}\\s*${y4}|" .         # mmmDDYYYY
        "${mmm}\\s*${y4}|" .                  # mmmYYYY
#        "${mmm}\\s*${dd}\\s*${y2}|" .         # mmmDDYY
        "${mmm}\\s*${d}|" .                   # mmmD
        "${d}\\s*${mmm}\\s*${y4}|" .          # DmmmYYYY
        "${d}\\s*${mmm}\\s*${y2}|" .          # DmmmYY
        "${d}\\s*${mmm}|" .                   # Dmmm
        "${y4}\\s*${mmm}\\s*${d}|" .          # YYYYmmmD

        "${mmm}${sep}${d}\\k<sep>${y4}|" .    # mmm/D/YYYY
        "${mmm}${sep}${d}\\k<sep>${y2}|" .    # mmm/D/YY
        "${mmm}${sep}${d}|" .                 # mmm/D
        "${d}${sep}${mmm}\\k<sep>${y4}|" .    # D/mmm/YYYY
        "${d}${sep}${mmm}\\k<sep>${y2}|" .    # D/mmm/YY
        "${d}${sep}${mmm}|" .                 # D/mmm
        "${y4}${sep}${mmm}\\k<sep>${d}|" .    # YYYY/mmm/D

        "${mmm}${sep}?${d}\\s+${y2}|" .       # mmmD YY      mmm/D YY
        "${mmm}${sep}?${d}\\s+${y4}|" .       # mmmD YYYY    mmm/D YYYY
        "${d}${sep}?${mmm}\\s+${y2}|" .       # Dmmm YY      D/mmm YY
        "${d}${sep}?${mmm}\\s+${y4}|" .       # Dmmm YYYY    D/mmm YYYY

        "${y2}\\s+${mmm}${sep}?${d}|" .       # YY   mmmD    YY   mmm/D
        "${y4}\\s+${mmm}${sep}?${d}|" .       # YYYY mmmD    YYYY mmm/D
        "${y2}\\s+${d}${sep}?${mmm}|" .       # YY   Dmmm    YY   D/mmm
        "${y4}\\s+${d}${sep}?${mmm}|" .       # YYYY Dmmm    YYYY D/mmm

        "${y4}:${m}:${d}";                    # YYYY:MM:DD

      $daterx = qr/^\s*(?:$daterx)\s*$/i;
      $$dmb{'data'}{'rx'}{'other'}{$rx} = $daterx;

}


##############################################################################

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
