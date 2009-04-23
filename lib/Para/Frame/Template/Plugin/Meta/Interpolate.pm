package Para::Frame::Template::Plugin::Meta::Interpolate;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Template::Plugin::Meta::Interpolate - Allow evaluation of META parameters

=cut

use 5.010;
use strict;
use warnings;
use base "Template::Plugin";

=head1 SYNOPSIS

  [% META next_template = '~$home/' %]

Goes to the site home page next

  [% META title='-"404 - " _ loc("File not found")' %]

The value is enclosed in C<''>. The initial C<-> tells us to
interpolate the rest as if it said:

  [% title = "404 - " _ loc("File not found") %]

The C<_> is a concatenation operator. And L<Para::Frame::L10N/loc> is
the translation function.

=head1 DESCRIPTION

If value starts with a '-', the rest of value will be evaluated as a TT
expression. (No expressions are normally allowed in META.)

If value starts with a '~', the rest of value will be evaluated as a
TT string with variable interpolation. It's the same as for '-' but
with the extra "" around the value.

It does not sets the variable if it's already true. That enables you
to set it in another way.

=head2 Example

  [* META otitle = '-otitle=["[_1]s administration pages", site.name]' *]

The normal use is to set the variable with the result of the template
output. But to give complex values to a variable, like a list, you can
do it as above.


=cut

#warn "$$: Compiling Para::Frame::Template::Plugin::Meta::Interpolate\n";


##############################################################################

sub new
{
    my( $self, $context, @params ) = @_;

#    warn "new Meta::Interpolate\n";
    my $cfg = $context->config;
    my $st = $cfg->{START_TAG} || '[%';
    $st =~ s/\\//g;
    my $et = $cfg->{END_TAG} || '%]';
    $et =~ s/\\//g;

    my $stash = $context->stash;
    my $template = $stash->{'template'};

    foreach my $key (keys %{$template})
    {
	next if $key =~ /^_/;
	my $val = $template->{$key};
	if( $val =~ /^-(.*)/s )
	{
	    my $src = $st.' '.$1.' '.$et;
#	    warn "Parsing $template->{$key} => $src\n";
	    $val = $context->process( \$src, {} );
#	    warn "Got value $val\n";
	    unless( $stash->get($key) )
	    {
#		warn "Assigning val to $key\n";
		$stash->set($key, $val);
	    }
	}
	elsif( $val =~ /^~(.*)/s )
	{
	    my $src = $st.' "'.$1.'" '.$et;
#	    warn "Parsing $template->{$key} => $src\n";
	    $val = $context->process( \$src, {} );
	    unless( $stash->get($key) )
	    {
		$stash->set($key, $val);
	    }
	}
	else
	{
	    $stash->set($key, $val);
	}
    }

    return $self;
}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::Manual::Templates>, L<Para::Frame::TT::header>, L<Template::Plugin>

=cut
