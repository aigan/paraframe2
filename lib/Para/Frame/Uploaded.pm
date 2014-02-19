package Para::Frame::Uploaded;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Uploaded - Class for uploaded files

=cut

use 5.010;
use strict;
use warnings;

use File::Copy; # copy, move
use Net::SCP;
use IO::File;
use Carp qw( cluck );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug throw datadump );
use Para::Frame::File;


##############################################################################

=head1 DESCRIPTION

Uploaded files are taken care of in L<Para::Frame::Client>

They are temporarily saved in C</tmp/paraframe/>. The filename is the
client process id followed by the fieldname with nonalfanum chars
removed. The file is deleted directly after the request!

Use L</save_as> to store the file.

Example:

  $req->uploaded('filefield')->save_as($destfile);

=cut


##############################################################################

=head2 new

  Para::Frame::Uploaded->new($fieldname)

Called by L<Para::Frame::Request/uploaded>.

Returns: The L<Para::Frame::Uploaded> object

=cut

sub new
{
    my( $this, $fieldname ) = @_;
    my $class = ref($this) || $this;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    $fieldname or throw('incomplete', "fieldname param missing");

#    my $fieldkey = $fieldname;
#    $fieldkey =~ s/[^\w_\-]//g; # Make it a normal filename

    my $filename =  $q->param($fieldname)
      or throw('incomplete', "$fieldname missing");

    my $uploaded = $req->{'files'}{$fieldname};

    $uploaded->{ filename } = $q->param($fieldname);
    $uploaded->{ fieldname } = $fieldname;

    return bless $uploaded, $class;
}


##############################################################################

sub move_to
{
    my( $uploaded, $destfile ) = @_;

    die "Should move $uploaded->{infile} to $destfile";
}

##############################################################################

=head2 save_as

  $uploaded->save_as( $destfile )

  $uploaded->save_as( $destfile, \%args )

Copies the file to C<$destfile>.

SCP is supported. You can use C<//host/path> or C<//user@host/path>.

For SCP, C<$args-E<gt>{username}> is used if set.

Returns: C<$uploaded>

=cut

sub save_as
{
    my( $uploaded, $destfile, $args ) = @_;

    $args ||= {};
    my $fromfile = $uploaded->{tempfile};

    if( UNIVERSAL::isa $destfile, 'Para::Frame::File' )
    {
	$destfile = $destfile->sys_path;
    }

    debug "Should save $fromfile as $destfile";

    if( $destfile =~ m{^//([^/]+)(.+)} )
    {
	my $host = $1;
	$destfile = $2;
	my $username;
	if( $host =~ /^([^@]+)@(.+)/ )
	{
	    $username = $1;
	    $host = $2;
	}

	if( $args->{'username'} )
	{
	    $username = $args->{'username'};
	}

	local $SIG{CHLD} = 'DEFAULT';
	my $scp = Net::SCP->new({host=>$host, user=>$username});
	debug "Connected to $host as $username";
	$scp->put($fromfile, $destfile)
	  or die "Failed to copy $fromfile to $destfile with scp: $scp->{errstr}";
    }
    else
    {
	copy( $fromfile, $destfile ) or
	  die "Failed to copy $fromfile to $destfile: $!";
    }

    return $uploaded;
}

##############################################################################

=head2 fh

  $uploaded->fh

  $uploaded->fh( $mode )

Creates and returns an L<IO::File> object

=cut

sub fh
{
    debug "In Para::Frame::Uploaded->fh";
    my( $uploaded, $mode, $perms ) = @_;

    $mode //= $uploaded->{'filemode'} || 0;

    cluck "No mode - ".datadump($uploaded) unless $mode;
    debug "Using mode $mode";

    my $fh = IO::File->new( $uploaded->{'tempfile'}, $mode );

    if( debug )
    {
	my( $mode, $uid, $gid) = (stat($uploaded->{'tempfile'}))[2,4,5];
	debug sprintf("Permissions are %04o uid%d gid%d\n",
		      $mode & 07777, $uid, $gid);
    }

    return $fh;
}


##############################################################################

=head2 set_mode

=cut

sub set_mode
{
    my(  $uploaded, $mode ) = @_;
    $uploaded->{'filemode'} = $mode;
}


##############################################################################

=head2 info

  $uploaded->info

  $uploaded->info( $item )

Returns a hash from L<CGI> C<uploadInfo()>, ot the specified C<$item>.

=cut

sub info
{
    my( $uploaded, $item ) = @_;

    if( $item )
    {
	return $uploaded->{'info'}{$item};
    }
    else
    {
	return $uploaded->{'info'};
    }
}


##############################################################################

=head2 content_type

  $uploaded->content_type

Returns the best guess of the content type. It may be taken from
L</info> or the file extension or the internal content of the file.

=cut

sub content_type
{
    my( $uploaded ) = @_;

    return $uploaded->{'info'}{'Content-Type'};
}


##############################################################################

=head2 tempfile

  $uploaded->tempfile

Retuns a L<Para::Frame::File> of the temporary file, that will be
removed after this request.

=cut

sub tempfile
{
    my( $uploaded ) = @_;

    return Para::Frame::File->new({ filename => $uploaded->{'tempfile'} });
}


##############################################################################

=head2 tempfilename

  $uploaded->tempfilename

Retuns the filename of the temporary file, that will be removed after
this request.

=cut

sub tempfilename
{
    my( $uploaded ) = @_;

    return $uploaded->{'tempfile'};
}


##############################################################################


1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>

=cut
