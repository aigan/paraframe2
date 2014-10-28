#!perl
use 5.010;
use utf8;

use Encode qw( _utf8_off _utf8_on );

use Para::Frame::Testing;
use Para::Frame::Utils qw( repair_utf8 deunicode validate_utf8 );

use Test::More tests => 12;
#use Test::More qw(no_plan);

flush_warnings();
binmode(STDOUT, ":utf8");

#my $mixed = q{A–åHÃ¤rsö-Ãkâ.};
my $mixed = "A\x{2013}\x{e5}H\x{c3}\x{a4}rs\x{f6}-\x{c3}k\x{e2}\x{80}\x{93}.";
#say uniescape($mixed);
is( validate_utf8(\$mixed), "DOUBLE-ENCODED utf8", 'detect double-encoded');
#say uniescape(deunicode($mixed));
is( deunicode($mixed), "A\x{96}-\x{e5}H\x{e4}rs\x{f6}-\x{c3}k\x{96}-.", 'deunicode double-encoded' );
repair_utf8(\ $mixed);
is( $mixed, 'A–åHärsö-Ãk–.','repair double-encoded');


my $valid_utf8 = 'Rå röd räka';
is( validate_utf8(\$valid_utf8), 'valid utf8', 'detect valid');
is( deunicode($valid_utf8), 'Rå röd räka','deunicode valid');
repair_utf8(\ $valid_utf8);
is( $valid_utf8, 'Rå röd räka','repair valid');

#my $encoded_marked = 'RÃ¥ rÃ¶d rÃ¤ka';
my $encoded_marked = "R\x{c3}\x{a5} r\x{c3}\x{b6}d r\x{c3}\x{a4}ka";
utf8::upgrade($encoded_marked);

my $encoded_unmarked = "R\x{c3}\x{a5} r\x{c3}\x{b6}d r\x{c3}\x{a4}ka";
is(validate_utf8(\$encoded_unmarked), "UNMARKED utf8", 'detect encoded unmarked');
repair_utf8(\$encoded_unmarked);
is( $encoded_unmarked, 'Rå röd räka', 'repair encoded unmarked' );

is( validate_utf8(\$encoded_marked), "DOUBLE-ENCODED utf8", 'detect encoded marked');
repair_utf8(\$encoded_marked);
is( $encoded_marked, 'Rå röd räka', 'repair encoded marked' );

my $plain = 'Just ascii';
is( validate_utf8(\$plain), 'NOT Marked as utf8', 'detect ascii');
repair_utf8(\ $plain);
is( $plain, 'Just ascii', 'repair ascii');



sub uniescape
{
    my $out = '';
    for( $i=0; $i<length($_[0]);$i++)
    {
        my $c = substr $_[0], $i,1;
        if( ord($c) >= 32 and ord($c) <= 126 )
        {
            $out .= $c;
        }
        else
        {
            $out .= sprintf '\x{%x}', ord($c);
        }
    }
    return $out;
}


1;
