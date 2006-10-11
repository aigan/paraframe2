package Para::Frame::Spreadsheet::CSV;

=head1 NAME

Para::Frame::Spreadsheet::CSV - Access data in CSV format

=cut

use strict;
use vars qw( $VERSION );
use Text::CSV_XS;
use Encode qw( from_to );

BEGIN
{
    $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading Para::Frame::Spreadsheet::CSV $VERSION\n"
      unless $Para::Frame::QUIET;
}

use Para::Frame::Utils qw( throw );
use Para::Frame::Reload;

use base 'Para::Frame::Spreadsheet';


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

sub row_number
{
    my $cfh = select shift->{fh};
    my $rownumber = $.;
    select $cfh;
    return $rownumber;

#    return shift->{fh}->input_line_number;
}

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

