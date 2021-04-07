package Para::Frame::Spreadsheet::Excel;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2021 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Spreadsheet::Excel - Access data in Excel format

=cut

use 5.012;
use warnings;
use Carp qw( confess );
use base 'Para::Frame::Spreadsheet';

use Spreadsheet::ParseExcel 0.49; # Will not work with later versions

use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Reload;

##############################################################################

=head2 init

=cut

sub init
{
	my( $sh ) = @_;

	debug "Excel init";

	my $parser = Spreadsheet::ParseExcel->new();
	my $book = $parser->Parse( $sh->{'fh'} );
	$sh->{'book'} = $book or die "Failed to parce excel file\n";
	my $sheet = $book->Worksheet(0);
	$sh->{'sheet'} = $sheet;

	my( $row_min, $row_max ) = $sheet->row_range();
	my( $col_min, $col_max ) = $sheet->col_range();
	$sh->{'row_number'} = $row_min;
	$sh->{'row_max'}    = $row_max;
	$sh->{'col_min'}    = $col_min;
	$sh->{'col_max'}    = $col_max;

#	debug datadump( $sh, 3 );

}


##############################################################################

=head2 next_row

=cut

sub next_row
{
	my( $sh ) = @_;

	my $sheet = $sh->{'sheet'};
	my $col_max = $sh->{'col_max'};
	my $col_min = $sh->{'col_min'};
	my $row_number = $sh->{'row_number'} ++;

#	debug "Read row $row_number of " .  $sh->{'row_max'};

	unless( $sheet )
	{
		debug datadump $sh;
		confess "spreadsheet missing";
	}

	if ( $row_number > $sh->{'row_max'} )
	{
		return undef;
	}

	my @row;

	my $has_content = 0;
	for ( my $i=$col_min; $i <= $col_max; $i++ )
	{
		my $cell = $sheet->Cell( $row_number, $i );
		if ( $cell )
		{
	    my $val = $cell->Value;
	    $val =~ s/\0//g;
	    push @row, $val;
	    $has_content ++ if length($val);
		}
		else
		{
	    push @row, undef;
		}
	}

	# Find a line with content, ignoring empty lines
	return [] unless $has_content;

	return \@row;
}


##############################################################################

=head2 row_number

=cut

sub row_number
{
	return shift->{'row_number'};

}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
