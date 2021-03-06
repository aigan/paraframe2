package Para::Frame::Template::Plugin::Sorted_table;
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

Para::Frame::Template::Plugin::Sorted_table

=cut

use 5.012;
use warnings;
use base "Template::Plugin";

use Para::Frame::Utils qw( debug );

=head1 DESCRIPTION

See L<Para::Frame::List/pagelist>

=cut


##############################################################################

sub new
{
    my( $this, $context, $order_in, $direction_in, $page_in ) = @_;
    my $class = ref($this) || $this;

#    debug "Preparing $order_in !!!";

    my $stash = $context->stash;
    my $q = $Para::Frame::REQ->q;

    $stash->set('order', $q->param('order') || $order_in );
    $stash->set('direction', $q->param('direction') || $direction_in);
    $stash->set('table_page', $q->param('table_page') || $page_in);

    return bless {}, $class;
}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<Template::Plugin>, L<Para::Frame::List>

=cut
