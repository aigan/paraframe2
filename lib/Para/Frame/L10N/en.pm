package Para::Frame::L10N::en;
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

Para::Frame::L10N::en - framework for localization - English

=head1 DESCRIPTION

Using Locale::Maketext

=cut

use 5.012;
use warnings;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );

use base qw(Para::Frame::L10N);

our %Lexicon =
  (
   '_AUTO' => 1,

   'page_ready' =>
   'Page Ready!',
  );

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
