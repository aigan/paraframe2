package Para::Frame::CGI;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::CGI - CGI class for mapping to/from UTF8

=cut

use 5.010;
use strict;
use warnings;
use base 'CGI';

use Carp qw( confess );
use CGI;

use Para::Frame::Reload;

use Para::Frame::Utils qw( debug datadump );


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
