package Para::Frame::Spreadsheet::CSV;
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

Para::Frame::Spreadsheet::CSV - Access data in CSV format

=cut

use 5.010;
use strict;
use warnings;
use base 'Para::Frame::Spreadsheet';

use Text::CSV_XS;
use Encode qw( from_to );

use Para::Frame::Utils qw( throw );
use Para::Frame::Reload;

##############################################################################

=head2 init

=cut

sub init
{
    my( $sh ) = @_;

    my $csv = Text::CSV_XS->new({binary=>1, sep_char=>';'});
    $sh->{'cxv'} = $csv or die "Failed to create CVS obj\n";

    my $fh = $sh->{'fh'};

    # Use DOS mode
    my $cfh = select $fh;
    $/ = "\r\n";
    select $cfh;

    $sh->{'pos'} = 0; # Assuming we start at the beginning
}


##############################################################################

=head2 next_row

=cut

sub next_row
{
    my( $sh ) = @_;

    my $csv = $sh->{'cxv'};
    my $fh = $sh->{'fh'};

##    seek $fh, $sh->{'pos'}, 0; # Shudder!
##    my $pos_a = tell $fh;


    # Find a line with content, ignoring empty lines
    my $line = "\r\n"; # Get started
    while( $line =~ /^\r?\n$/ )
    {
	$line = <$fh>;
	return undef unless defined $line;
    }

##    my $pos_b = tell $fh;
##    ### This is crazy! -- Storing file position
##    $sh->{'pos'} = $pos_b;
##    warn sprintf "%.3d [%d -> %d: %d] '%s'\n", $., $pos_a, $pos_b, length($line), $line;

#    chomp $line;
    warn sprintf "Parsing row [%d] %s\n", length($line), $line; ### DEBUG

    $csv->parse($line)
      or throw('validation',"Failed parsing row $.: ".$csv->error_input());

    my @row;
    foreach my $str ( $csv->fields )
    {
#	warn "  Val $str\n";
#	from_to($str, 'cp437', "iso-8859-1");
#	warn "  Now $str\n\n";
	push @row, $str;
    }

    return \@row;
}


##############################################################################

=head2 row_number

=cut

sub row_number
{
    my $cfh = select shift->{fh};
    my $rownumber = $.;
    select $cfh;
    return $rownumber;

#    return shift->{fh}->input_line_number;
}


##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

