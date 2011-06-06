package Para::Frame::L10N::sv;
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

Para::Frame::L10N::sv - framework for localization - Swedish

=head1 DESCRIPTION

Using Locale::Maketext

=cut

use 5.010;
use strict;
use warnings;
use utf8; # Using Latin-1 (åäö)

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );

use base qw(Para::Frame::L10N);

our %Lexicon =
  (
   '_AUTO' => 1,

   'Action failed' =>
   'Försök misslyckades',

   'Click for calendar' =>
   'Klicka för kalender',

   'Compilation error' =>
   'Kompileringsfel',

   'Compiling [_1]' =>
   'Kompilerar [_1]',

   'Confirm' =>
   'Bekräfta uppgift',

   'Database error' =>
   'Databasfel',

   'During the processing of [_1]' =>
   'Under körningen av [_1]',

   'File not found' =>
   'Filen hittades inte',

   'Form check failed' =>
   'Fel vid kontroll',

   'Include path is' =>
   'Sökvägen är',

   'Information missing' =>
   'Uppgifter saknas',

   'Multiple alternatives' =>
   'Flera alternativ',

   'Name' =>
   'Namn',

   'Name is missing' =>
   'Namn saknas',

   'Not found' =>
   'Hittar inte',

   'page_ready' =>
   'Sidan är klar!',

   'Password' =>
   'Lösenord',

   'Password is missing' =>
   'Ange lösenord också',

   'Permission Denied' =>
   'Access nekad',

   'Processing' =>
   'Arbetar',

   'Processing page' =>
   'Laddar sidan',

   'Problem during update' =>
   'Problem med att spara uppgift',

   'Request sent' =>
   'Kontakt etablerad',

   'Rendering page' =>
   'Genererar sidan',

   'recaptcha-no-response' =>
   'Fyll i de två orden som visas på bilden',

   'recaptcha-incorrect-captcha-sol' =>
   'De ord du fyllde i stämmer inte med bilden. Försök igen',

   'Template error' =>
   'Mallfel',

   'Template missing' =>
   'Mallfil saknas',

   'The file you requested cannot be found' =>
   'Sidan som du angav kunde inte hittas',

   'The user [_1] doesn\'t exist' =>
   'Användaren [_1] existerar inte',

  );

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
