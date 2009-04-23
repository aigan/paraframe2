package Para::Frame::Code::Class;
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

Para::Frame::Code::Class - Represents a perl class

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( croak confess cluck );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );
use Para::Frame::File;

##############################################################################

=head2 get

  Para::Frame::Code::Class->get( $classname )

  Para::Frame::Code::Class->get( $object )

Returns: an object representing the class.

=cut

sub get
{
    my( $this, $name_in ) = @_;
    my $class = ref($this) || $this;
    my $name = ref($name_in) || $name_in;

    my $c =
    {
     name => $name,
    };

    return bless $c, $class;
}

##############################################################################

=head2 name

  $c->name()

Returns: The class name as a literal string.

=cut

sub name
{
    return $_[0]->{'name'};
}

##############################################################################

=head2 parents

  $c->parents()

Returns: A hashref of class objects

=cut

sub parents
{
    my( $c ) = @_;

    my @list;
    my $package = $c->name;
    no strict "refs";
    foreach my $isa (@{"${package}::ISA"})
    {
	push @list, $c->get($isa);
    }
    return \@list;
}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
