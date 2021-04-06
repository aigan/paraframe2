package Para::Frame::Spreadsheet;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Spreadsheet - Access data in diffrent source formats in a uniform way

=cut

use 5.012;
use warnings;
no if $] >= 5.018, warnings => "experimental";

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw datadump debug );

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

=cut


##############################################################################

=head2 new

=cut

sub new
{
	my( $class, $fh, $type, $conf ) = @_;

	my $sh = bless {}, $class;
	$sh->{'fh'} = $fh;

	$conf ||= {};
	$sh->{'conf'} = $conf;

	unless( $fh->isa("IO::Handle") or $fh->isa("Fh")  )
	{
		die datadump( $fh );
		throw('action', "No filehandle given: $fh");
	}

	if ( $type )
	{
		given( $type )
		{
			when(['text/comma-separated-values','text/csv'] )
			{
				require Para::Frame::Spreadsheet::CSV;
				bless $sh, "Para::Frame::Spreadsheet::CSV";
			}
			when( 'application/vnd.ms-excel' )
			{
				require Para::Frame::Spreadsheet::Excel;
				bless $sh, "Para::Frame::Spreadsheet::Excel";
			}
			default
			{
				die "Spreadsheet type $type not implemented";
			}
		}

		$sh->init;
	}
	else
	{
		die "not implemented";
	}

	return $sh;
}


##############################################################################

=head2 get_headers

=cut

sub get_headers
{
	my( $sh ) = @_;

	my $row = $sh->next_row;

	$sh->{'cols'} = [];
	$sh->{'colnums'} = {};

	for ( my $i=0; $i <= $#$row; $i++ )
	{
		my $val = $row->[$i];
		next unless $val;
		$sh->{'cols'}[$i] = $val;
		$sh->{'colnums'}{ $val } = $i;
	}

	if ( $sh->{'conf'}{extra_headers} )
	{
		return $sh->add_headers($sh->{'conf'}{extra_headers});
	}

	return scalar @$row;
}


##############################################################################

=head2 add_headers

For adding extra headers, for fields added in row_filter

=cut

sub add_headers
{
	my( $sh, $headers ) = @_;

	my $i = $#{$sh->{'cols'}};
	foreach my $header (@$headers)
	{
		$i++;
		$sh->{'cols'}[$i] = $header;
		$sh->{'colnums'}{ $header } = $i;
	}

	return($i+1);
}


##############################################################################

=head2 headers

=cut

sub headers
{
	my( $sh ) = @_;

	return $sh->{'cols'};
}


##############################################################################

=head2 rowhash

=cut

sub rowhash
{
	my( $sh ) = @_;

	unless ( $sh->{'rowhash'} )
	{
		my $row = $sh->next_row or return undef;
		my $cols = $sh->{'cols'};
		my $rh = $sh->{'rowhash'} = {};
		for ( my $i=0; $i <= $#$row; $i++ )
		{
	    my $key = $cols->[$i];
	    unless( $key )
	    {
				debug "Column $i has no label";
				next;
	    }

	    $rh->{ $key } = $row->[$i];
		}
	}

	return $sh->{'rowhash'};
}


##############################################################################

=head2 next_rowhash

=cut

sub next_rowhash
{
	my( $sh ) = @_;
	$sh->{'rowhash'} = undef;
	return $sh->rowhash;
}


##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
