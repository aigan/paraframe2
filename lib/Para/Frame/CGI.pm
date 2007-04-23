#  $Id$  -*-cperl-*-
package Para::Frame::CGI;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework CGI class for mapping to/from UTF8
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::CGI - CGI class for mapping to/from UTF8

=cut

use strict;

use Carp qw( confess );
use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use Para::Frame::Utils qw( debug datadump );

use base 'CGI';

#######################################################################

=head2 new

=cut

sub new
{
    my $class = shift;
    my $q = $class->SUPER::new(@_);

    foreach my $key ( @{$q->{'.parameters'}} )
    {
	foreach(@{$q->{$key}})
	{
	    utf8::decode($_);
	}
    }

#    if( my $val = $q->param('id') )
#    {
#	my $len1 = length($val);
#	my $len2 = bytes::length($val);
#	debug "  >>$val ($len2/$len1)";
#	if( utf8::is_utf8($val) )
#	{
#	    if( utf8::valid($val) )
#	    {
#		debug "Marked as valid utf8";
#	    }
#	    else
#	    {
#		debug "Marked as INVALID utf8";
#	    }
#	}
#	else
#	{
#	    debug "NOT Marked as utf8";
#	}
#    }

    return $q;
}

#######################################################################

=head2 req

=cut

sub req    { $_[0]->{'req'} }

#######################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame::Request>, L<CGI>

=cut
