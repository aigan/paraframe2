#  $Id$  -*-perl-*-
package Para::Frame::Uploaded;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework class for uploaded files
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Uploaded - Class for uploaded files

=cut

use strict;
use Data::Dumper;
use File::Copy; # copy, move
use Net::SCP;
use IO::File;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug throw );


#######################################################################

=head1 DESCRIPTION

Uploaded files are taken care of in L<Para::Frame::Client>

They are temporarily saved in C</tmp/paraframe/>. The filename is the
client process id followed by the fieldname with nonalfanum chars
removed. An ENV is set with the prefix C<paraframe-upload-> that has
the full filename as the value. The file is deleted directly after the
request!

Use L</save_as> to store the file.

Example:

  $req->uploaded('filefield')->save_as($destfile);

=cut


#######################################################################

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

    my $fieldkey = $fieldname;
    $fieldkey =~ s/[^\w_\-]//g; # Make it a normal filename

    my $filename =  $q->param($fieldname)
      or throw('incomplete', "$fieldname missing");

    my $infile = $req->env->{"paraframe-upload-$fieldkey"} or
      die "No file handler \n".Dumper($req->env);

    my $uploaded = bless
    {
     filename => $filename,
     fieldname => $fieldname,
     fieldkey => $fieldkey,
     infile => $infile,
    }, $class;

#    $q->param($fieldname, 'testar'); # Doesn't work

    return $uploaded;
}

sub move_to
{
    my( $uploaded, $destfile ) = @_;

    die "Should move $uploaded->{infile} to $destfile";
}

#######################################################################

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

    debug "Should save $uploaded->{infile} as $destfile";

    $args ||= {};

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

	my $fromfile = $uploaded->{infile};

	local $SIG{CHLD} = 'DEFAULT';
	my $scp = Net::SCP->new({host=>$host, user=>$username});
	debug "Connected to $host as $username";
	$scp->put($fromfile, $destfile)
	  or die "Failed to copy $fromfile to $destfile with scp: $scp->{errstr}";
    }
    else
    {
	copy( $uploaded, $destfile ) or
	  die "Failed to copy $uploaded to $destfile: $!";
    }

    return $uploaded;
}

#######################################################################

=head2 fh

  $uploaded->fh

  $uploaded->fh( $mode )

Creates and returns an L<IO::File> object

=cut

sub fh
{
    my( $uploaded ) = shift;
    return File::IO->new( $uploaded->{'filename'}, @_ );
}


#######################################################################


1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>

=cut
