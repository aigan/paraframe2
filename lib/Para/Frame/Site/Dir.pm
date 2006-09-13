#  $Id$  -*-cperl-*-
package Para::Frame::Site::Dir;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Dir class
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

Para::Frame::Site::Dir - Represents a directory in the site

=cut

use strict;
use Carp qw( croak confess cluck );
use IO::Dir;
use File::stat; # exports stat
use Scalar::Util qw(weaken);
#use Dir::List; ### Not used...

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}


use base qw( Para::Frame::Dir Para::Frame::Site::File );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );
use Para::Frame::List;
use Para::Frame::Page;

=head1 DESCRIPTION

Represents a directory in the site.

This class inherits from L<Para::Frame::Dir> and
L<Para::Frame::Site::File>.

=cut

#######################################################################

=head2 new

  Para::Frame::Site::Dir->new(\%args)

See L<Para::Frame::File>

=cut


#######################################################################

=head1 Accessors

See L<Para::Frame::File>

=cut

#######################################################################

sub pageclass
{
    return "Para::Frame::Site::Page";
}

sub fileclass
{
    return "Para::Frame::Site::File";
}


=head2 dirs

Returns a L<Para::Frame::List> with L<Para::Frame::Site::Dir> objects.

=cut

sub dirs
{
    my( $dir ) = @_;

    $dir->initiate;

    my @list;
    foreach my $name ( keys %{$dir->{file}} )
    {
	next unless $dir->{file}{$name}{directory};
	my $url = $dir->{url_name}.'/'.$name;
	push @list, $dir->new({ site => $dir->site,
				url  => $url,
			      });
    }

    return Para::Frame::List->new(\@list);
}

#######################################################################

=head2 parent

We get the parent L<Para::Frame::Site::Dir> object.

Returns undef if we trying to get the parent of the
L<Para::Frame::Site/home>.

=cut

sub parent
{
    my( $dir ) = @_;

    my $home = $dir->site->home_url_path;
    my( $pdirname ) = $dir->{'url_name'} =~ /^($home.*)\/./ or return undef;

    return $dir->new({site => $dir->site,
		      url  => $pdirname.'/',
		     });
}


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
