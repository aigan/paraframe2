#  $Id$  -*-perl-*-
package Para::Frame::L10N::sv;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Localization: sv
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::L10N::sv - framework for localization - Swedish

=head1 DESCRIPTION

Using Locale::Maketext

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%01d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );

use base qw(Para::Frame::L10N);

our %Lexicon =
  (
   '_AUTO' => 1,

   'File not found' =>
   'Filen hittades inte',

   'The file you requested cannot be found' =>
   'Sidan som du angav kunde inte hittas',

   'During the processing of [_1]' =>
   'Under körningen av [_1]',

   'Permission Denied' =>
   'Access nekad',

   'Database error' =>
   'Databasfel',

   'Problem during update' =>
   'Problem med att spara uppgift',

   'Information missing' =>
   'Uppgifter saknas',

   'Form check failed' =>
   'Fel vid kontroll',

   'Multiple alternatives' =>
   'Flera alternativ',

   'Confirm' =>
   'Bekräfta uppgift',

   'Action failed' =>
   'Försök misslyckades',

   'Compilation error' =>
   'Kompileringsfel',

   'Not found' =>
   'Hittar inte',

   'Template error' =>
   'Mallfel',

   'Template missing' =>
   'Mallfil saknas',

   'Include path is' =>
   'Sökvägen är',

  );

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
