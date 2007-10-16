#  $Id$  -*-cperl-*-
package Para::Frame::Unicode;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Localization
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Unicode - Handling conversions

=cut

use strict;
use Carp qw(cluck croak carp confess shortmess );
use utf8;

BEGIN
{
    our $VERSION  = sprintf("%d.%01d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Encode::InCharset qw( InASCII InCP1252 InISO_8859_1 );

our( %EQUIVAL, %EQASCII, %EQLATIN1, %EQCP );


sub addequal(@);


#######################################################################


{
    local $_;
    while (<DATA>){ s/\s*#.*//so; addequal($_); }
}


#######################################################################

=head2 addequal

=cut

sub addequal(@)
{
    return unless
      my @chr = map hex($_), split /(?:\s+|\+)/, shift;

    my $key = shift @chr;
    my $val = join '', map chr($_), @chr;

    $EQUIVAL{$key} = $val;
    my $char = chr($key);

    if( $char !~ /\p{InISO_8859_1}/ and
	$val =~ /^\p{InISO_8859_1}+$/ )
    {
	$EQLATIN1{$key} = $val;
    }

    if( $char !~ /\p{InASCII}/ and
	$val =~ /^\p{InASCII}+$/ )
    {
	$EQASCII{$key} = $val;
    }

    if( $char !~ /\p{InCP1252}/ and
	$val =~ /^\p{InCP1252}+$/ )
    {
	$EQCP{$key} = $val;
    }
}

sub map_to_latin1
{
    return $EQLATIN1{$_[0]} ? $EQLATIN1{$_[0]} : '?';
}


1;

=head1 SEE ALSO

L<Para::Frame>

=cut


# Data taken from Unicode::Lite

__DATA__

# LATIN 1
00C4 41+65 # A"    Ae
00D6 4F+65 # O"    Oe
00DC 55+65 # U"    Ue
00E4 61+65 # a"    ae
00F6 6F+65 # o"    oe
00FC 75+65 # u"    ue
00DF 73+73 # szet  ss

# CYRILLIC
0410 41    # A     A
0411 42    # BE    B
0412 56    # VE    V
0413 47    # GHE   G
0414 44    # DE    D
0415 45    # IE    E
0401 59+4F # IO    YO
0416 5A+48 # ZHE   ZH
0417 5A    # ZE    Z
0418 49    # I     I
0419 4A    # J     J
041A 4B    # KA    K
041B 4C    # EL    L
041C 4D    # EM    M
041D 4E    # EN    N
041E 4F    # O     O
041F 50    # PE    P
0420 52    # ER    R
0421 53    # ES    S
0422 54    # TE    T
0423 55    # U     U
0424 46    # EF    F
0425 58    # HA    X
0426 43    # TSE   C
0427 43+48 # CHE   CH
0428 53+48 # SHA   SH
0429 57    # SHCHA W
042A 7E    # HARD  ~
042B 59    # YERU  Y
042C 27    # SOFT  '
042D 45+27 # E     E'
042E 59+55 # YU    YU
042F 59+41 # YA    YA
0430 61    # a     a
0431 62    # be    b
0432 76    # ve    v
0433 67    # ghe   g
0434 64    # de    d
0435 65    # ie    e
0451 79+6F # io    yo
0436 7A+68 # zhe   zh
0437 7A    # ze    z
0438 69    # i     i
0439 6A    # j     j
043A 6B    # ka    k
043B 6C    # el    l
043C 6D    # em    m
043D 6E    # en    n
043E 6F    # o     o
043F 70    # pe    p
0440 72    # er    r
0441 73    # es    s
0442 74    # te    t
0443 75    # u     u
0444 66    # ef    f
0445 78    # ha    x
0446 63    # tse   c
0447 63+68 # che   ch
0448 73+68 # sha   sh
0449 77    # shcha w
044A 7E    # hard  ~
044B 79    # yeru  y
044C 27    # soft  '
044D 65+27 # e     e'
044E 79+75 # yu    yu
044F 79+61 # ya    ya

# ANGLE QUOTATION MARK
008B 3C    # SINGLE LEFT  <
009B 3E    # SINGLE RIGHT >
00AB 3C+3C # DOUBLE LEFT  <<
00BB 3E+3E # DOUBLE RIGHT >>

# SIGNS
2024 2E       # ONE DOT  .
2025 2E+2E    # TWO DOT  ..
2026 2E+2E+2E # ELLIPSIS ...
2030 25+2E    # MILLE    %.
2031 25+2E+2E # THOUSAND %..
00B2 28+32+29 # SUPER 2  (2)
00B3 28+33+29 # SUPER 3  (3)
00B9 28+31+29 # SUPER 1  (1)
00A9 28+63+29 # COPY   c (c)
00AE 28+72+29 # REG    R (r)
0192 28+66+29 # FUNC     (f)
2122 28+74+6D+29# TRADE (tm)

00BD 31+2F+32 # 1/2
2153 31+2F+33 # 1/3
2154 32+2F+33 # 2/3
00BC 31+2F+34 # 1/4
00BE 33+2F+34 # 3/4
2155 31+2F+35 # 1/5
2156 32+2F+35 # 2/5
2157 33+2F+35 # 3/5
2158 34+2F+35 # 4/5
2159 31+2F+36 # 1/6
215A 35+2F+36 # 5/6
215B 31+2F+38 # 1/8
215C 33+2F+38 # 3/8
215D 35+2F+38 # 5/8
215E 37+2F+38 # 7/8

2013 0096 2D  # EN DASH   -
2014 0097 2D  # EM DASH   -
0096 2013 2D  # EN DASH   -
0097 2014 2D  # EM DASH   -

00BF 3F   # INVERTED      ?
00A8 22   # DIAERESIS     "
00D7 78   # MULTIPLY      x
00F7 27   # DEVISION      /
221A 56   # SQUARE ROOT û V
25A0 6F   # BLACK SQUAR þ o
00B0 6F   # DEGREE      ø o
2219 2E   # BULLET       .
00B7 2E   # MIDDLE DOT  ú .
02dc 7E   # SMALL TILDE   ~
2018 27   # SINGLE LEFT '
2019 27   # SINGLE RIGH '
201A 27   # SINGLE LOW9 '
201C 22   # DOUBLE LEFT "
201D 22   # DOUBLE RIGH "
201E 22   # DOUBLE LOW9 "
00AC 2510 # NOT         ¿ ¿
00B1 2B+2C# PLUS_MINUS   +-
2248 7E+3D# ALMOST EQUAL ~=
2260 21+3D# NOT EQUAL TO !=
2261 3D+3D# IDENTICAL    ==
2264 3C+3D# LESS | EQUAL <=
2265 3E+3D# GREAT| EQUAL >=
203C 21+21# 2 EXCLAMATION!!
203D 3F+21#              ?!

# BLOCK
2588 42   # Û B
258C 7C   # Ý |
2590 7C   # Þ |
2580 2D   # ß -
2584 2D   # Ü -

# SHADE
2591 2588 # ° Û
2592 2588 # ± Û
2593 2588 # ² Û

# BOX DRAWINGS
2502 7C   # ³ |
2500 2D   # Ä -
253C 2B   # Å +
250C 2F   # Ú /
2514 5C   # À \
2510 AC 5C# ¿¿\
2518 2F   # Ù /
252C 2500 # Â Ä
2534 2500 # Á Ä
251C 2502 # Ã ³
2524 2502 # ´ ³

2551 2502 # º ³
2550 2500 # Í Ä
256C 253C # Î Å
2554 250C # É Ú
255A 2514 # È À
2557 2510 # » ¿
255D 2518 # ¼ Ù
2566 252C # Ë Â
2569 2534 # Ê Á
2560 251C # Ì Ã
2563 2524 # ¹ ´

256B 256C # × Î
2553 2554 # Ö É
2559 255A # Ó È
2556 2557 # · »
255C 255D # ½ ¼
2565 2566 # Ò Ë
2568 2569 # Ð Ê
255F 2551 # Ç º
2562 2551 # ¶ º

256A 253C # Ø Å
2552 250C # Õ Ú
2558 2514 # Ô À
2555 2510 # ¸ ¿
255B 2518 # ¾ Ù
2564 252C # Ñ Â
2567 2534 # Ï Á
255E 251C # Æ Ã
2561 2524 # µ ´
