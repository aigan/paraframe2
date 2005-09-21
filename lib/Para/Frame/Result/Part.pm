#  $Id$  -*-perl-*-
package Para::Frame::Result::Part;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Result Part class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Result - Representing an individual result as part of the Result object

=cut

use strict;
use Data::Dumper;
use Carp qw( carp shortmess croak );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( trim debug );


sub new
{
    my( $this, $params ) = @_;
    my $class = ref($this) || $this;

    $params ||= {};
    my $part = bless($params, $class);

    return $part;
}

sub prefix_message
{
    my( $part, $message ) = @_;

    if( $message )
    {
	trim(\$message);
	$part->{'prefix_message'} = $message;
    }
    return $part->{'prefix_message'};
}

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
