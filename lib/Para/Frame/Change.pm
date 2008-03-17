#  $Id$  -*-cperl-*-
package Para::Frame::Change;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2008 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Change - DB Change class

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );


=head1 DESCRIPTION

This is an object for collecting information about changes.

The idea is to let various methods add messages about changes or
errors to objects. If everything is okey, display all the messages. If
one of the messages returns an error, only display the error and do a
rollback so that no changes is done to the DB.

Could be used in combination with methods in L<Para::Frame::DBIx>.

=head1 METHODS

=cut


#######################################################################

=head2 new

=cut

sub new
{
    my( $class ) = @_;

    my $change = bless {}, $class;

    return $change->reset;
}


#######################################################################

=head2 reset

  $changes->reset()

Resets the change object. Like creating a new object, but keeps the
existing one.

Returns the now empty object.

=cut

sub reset
{
    my( $change ) = @_;

    foreach my $key ( keys %$change )
    {
	delete $change->{$key};
    }

    $change->{'errors'} = 0;
    $change->{'errmsg'} = "";
    $change->{'changes'} = 0;
    $change->{'message'} = "";
    $change->{'form_params'} = [];

    return $change;
}


#######################################################################

=head2 rollback

  $changes->rollback()

=cut

sub rollback
{
    my( $change ) = @_;



    return $change->reset;
}


#######################################################################

=head2 success

  $changes->success( $message )

Adds a success message. Increments the C<changes> counter.

Returns true.

=cut

sub success
{
    my( $change, $msg ) = @_;
    $msg =~ s/\n?$/\n/; # Add if missing
    $change->{'changes'} ++;
    $change->{'message'} .=  $msg;
    debug "Adding success message: $msg";
    return 1;
}


#######################################################################

=head2 note

  $changes->note( $message )

Adds a note, not counting as success or failure.

Returns true.

=cut

sub note
{
    my( $change, $msg ) = @_;
    $msg =~ s/\n?$/\n/; # Add if missing
    $change->{'message'} .=  $msg;
    debug "Adding note: $msg";
    return 1;
}


#######################################################################

=head2 fail

  $changes->fail( $message )

Adds a failure message. Increments the C<errors> counter.

Returns false.

=cut

sub fail
{
    my( $change, $msg ) = @_;
    $msg =~ s/\n?$/\n/; # Add if missing
    $change->{'errors'} ++;
    $change->{'errmsg'} .=  $msg;
    debug "Adding fail message: $msg";
    return undef;
}


#######################################################################

=head2 changes

  $changes->changes

Returns the number of successful C<changes>.

=cut

sub changes
{
    return $_[0]->{'changes'};
}


#######################################################################

=head2 errors

  $changes->errors

Returns the number of C<errors>

=cut

sub errors
{
    return $_[0]->{'errors'};
}


#######################################################################

=head2 message

  $changes->message

Returns the messages from the successful changes. Each message
separated by a newline.

=cut

sub message
{
    return $_[0]->{'message'};
}


#######################################################################

=head2 errmsg

  $changes->errmsg

Returns teh error messages. Each message separated by a newline.

=cut

sub errmsg
{
    return $_[0]->{'errmsg'};
}


#######################################################################

=head2 queue_clear_params

  $changes->queue_clear_params( @list )

Will call <Para::Frame::Utils/clear_params> before rendering the
resulting page, unless we got a rollback.

=cut

sub queue_clear_params
{
    my( $change, @params ) = @_;

    my $req = $Para::Frame::REQ;
    return unless $req->is_from_client;
    my $target_response = $req->response_if_existing;
    return unless $target_response;

    push @{$change->{'form_params'}}, @params;
}


#######################################################################

=head2 before_render_output

Called just before $req->response->render_output

=cut

sub before_render_output
{
    my( $change ) = @_;

    if( my @params = @{$change->{'form_params'}} )
    {
	debug 2, "Clearing form params";
	Para::Frame::Utils::clear_params(@params);
    }
}


#######################################################################

=head2 report

  $changes->report

  $changes->report( $errtype )

Puts the L</message> in a L<Para::Frame::Result/message>.

If there is an L</errmsg>, Throws an exception with that message of
type C<$errtype>. The default errtype is C<validation>.

=cut

sub report
{
    my( $change, $errtype ) = @_;

    $errtype ||= 'validation';

    if( length( $change->{'message'} ) )
    {
	$Para::Frame::REQ->result->message( $change->{'message'} );
    }

    if( $change->{'errors'} )
    {
	throw($errtype, $change->{'errmsg'} );
    }

    $change->reset;
    return "";
}


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
