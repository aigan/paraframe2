package Para::Frame::Spreadsheet::Excel;

=head1 NAME

Para::Frame::Spreadsheet::Excel - Access data in Excel format

=cut

use strict;
use vars qw( $VERSION );
use Spreadsheet::ParseExcel;

BEGIN
{
    $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading Para::Frame::Spreadsheet::Excel $VERSION\n"
      unless $Para::Frame::QUIET;
}

use Para::Frame::Utils qw( throw );
use Para::Frame::Reload;

use base 'Para::Frame::Spreadsheet';

sub init
{
    my( $sh ) = @_;

    my $book = Spreadsheet::ParseExcel::Workbook->Parse($sh->{'fh'});
    $sh->{'book'} = $book or die "Failed to parce excel file\n";
    my $sheet = $book->{Worksheet}->[0];
    $sh->{'sheet'} = $sheet;

    $sh->{'row_number'} = $sheet->{MinRow};
    $sh->{'row_max'}    = $sheet->{MaxRow};
    $sh->{'col_min'}    = $sheet->{MinCol};
    $sh->{'col_max'}    = $sheet->{MaxCol};
}

sub next_row
{
    my( $sh ) = @_;

    my $sheet = $sh->{'sheet'};
    my $col_max = $sh->{'col_max'};
    my $col_min = $sh->{'col_min'};
    my $row_number = $sh->{'row_number'} ++;


    if( $row_number > $sh->{'row_max'} )
    {
	return undef;
    }

    my @row;

    my $has_content = 0;
    for( my $i=$col_min; $i <= $col_max; $i++ )
    {
	my $cell = $sheet->Cell( $row_number, $i );
	if( $cell )
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
    return $sh->next_row unless $has_content;

    return \@row;
}

sub row_number
{
    return shift->{'row_number'};
}


1;

=head1 SEE ALSO

L<Para::Frame>

=cut
