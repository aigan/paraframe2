package Para::Frame::Spreadsheet;

=head1 NAME

Para::Frame::Spreadsheet - Access data in diffrent source formats in a uniform way

=cut

use strict;
use vars qw( $VERSION );
use Data::Dumper;


BEGIN
{
    $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading Para::Frame::Spreadsheet $VERSION\n"
      unless $Para::Frame::QUIET;
}

use Para::Frame::Utils qw( throw );
use Para::Frame::Reload;

=head1 SYNOPSIS

  use Para::Frame::Spreadsheet;
  use IO::File;

  my $fh = new IO::File "my_file";
  my $type = "text/x-csv";

  my $sh = new Para::Frame::Spreadsheet($fh, $type);

  $sh->get_headers;

  while( my $row = $sh->next_rowhash )
  {
     foreach my $col ( $sh->headers )
     {
       print $row->{$col} . "\t";
     }
     print "\n";
  }

=head1 DESCRIPTION

Handles mostly CSV and XML.

=head1 Methods

=head2 new

=cut

sub new
{
    my( $class, $fh, $type ) = @_;

    my $sh = bless {}, $class;
    $sh->{'fh'} = $fh;

    unless( $fh->isa("IO::Handle") or $fh->isa("Fh")  )
    {
	die Dumper $fh;
	throw('action', "No filehandle given: $fh");
    }

    if( $type )
    {
	if( $type eq 'text/comma-separated-values' )
	{
	    require Para::Frame::Spreadsheet::CSV;
	    bless $sh, "Para::Frame::Spreadsheet::CSV";
	}
	elsif( $type eq 'application/vnd.ms-excel' )
	{
	    require Para::Frame::Spreadsheet::Excel;
	    bless $sh, "Para::Frame::Spreadsheet::Excel";
	}
	else
	{
	    die "Spreadsheet type $type not implemented";
	}

	$sh->init;
    }
    else
    {
	die "not implemented";
    }

    return $sh;
}

sub get_headers
{
    my( $sh ) = @_;

    my $row = $sh->next_row;

    $sh->{'cols'} = [];
    $sh->{'colnums'} = {};

    for( my $i=0; $i <= $#$row; $i++ )
    {
	my $val = $row->[$i];
	$sh->{'cols'}[$i] = $val;
	$sh->{'colnums'}{ $val } = $i;
    }

    return scalar @$row;
}

sub headers
{
    my( $sh ) = @_;

    return $sh->{'cols'};
}

sub rowhash
{
    my( $sh ) = @_;

    unless( $sh->{'rowhash'} )
    {
	my $row = $sh->next_row or return undef;
	my $cols = $sh->{'cols'};
	my $rh = $sh->{'rowhash'} = {};
	for( my $i=0; $i <= $#$row; $i++ )
	{
	    $rh->{ $cols->[$i] } = $row->[$i];
	}
    }

    return $sh->{'rowhash'};
}

sub next_rowhash
{
    my( $sh ) = @_;
    $sh->{'rowhash'} = undef;
    return $sh->rowhash;
}

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
