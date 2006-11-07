#  $Id$  -*-cperl-*-
package Para::Frame::Result;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Result class
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

Para::Frame::Result - Holds the results of actions and exceptions

=cut

use strict;
use Data::Dumper;
use Carp qw( carp shortmess croak confess );
use Template::Exception;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( trim debug catch run_error_hooks datadump );
use Para::Frame::Result::Part;

=head1 DESCRIPTION

The result object holds the results of the actions taken and exceptions thrown (L<Para::Frame::Utils/throw>).

=head1 Properties

=head2 info

$result->{info} is the storage space for actions results.  Put your
data in an apropriate subhash.  Example:

  $result->{info}{myresult} = \@listresult;

The info hash is accessed in the template as C<result.info>.


=cut

sub new
{
    my( $class ) = @_;

    my $result = bless
    {
     part => [],
     errcnt => 0,
     backtrack => 0,
     info => {},
     main => undef,
     hide_part => {},
    }, $class;


    # Add info about compilation errors
    foreach my $module ( keys %Para::Frame::Result::COMPILE_ERROR )
    {
	my $errmsg = $Para::Frame::Result::COMPILE_ERROR{$module};
	$result->error('compilation', "$module\n\n$errmsg");
    }

#    # Do not count these compile errors, since that would halt
#    # everything. We only want to draw atention to the problem but
#    # still enable usage
#    #
#    $result->{errcnt} = 0;


    return $result;
}

sub message
{
    my( $result, @messages ) = @_;

    foreach my $msg ( @messages )
    {
	$msg ||= "";
	$msg =~ s/(\n\r?)+$//;
	next unless length $msg;

	debug(3, "Adding result message '$msg'");

	push @{$result->{'part'}}, Para::Frame::Result::Part->new({
	    'message' => $msg,
	});
	$Para::Frame::REQ->note($msg);
    }
}

=head2 exception

  $result->exception()
  $result->exception($error)
  $result->exception($type, $info, $text)

If called with no params, uses $@ as $error.

If called with more than one params, creates an $error object with
type $type, info $info and text $text.  $text can be undef.

returns the generated Para::Frame::Result::Part.

If $error is a Part, just returns it.

For other errors, adds parts to result and returns one of them.

=cut

sub exception
{
    my( $result, $explicit, $info_in, $textref ) = @_;

#    debug "exception called with ".datadump(\@_);

    $textref ||= "";
    unless( ref $textref )
    {
	$textref = \ "$textref";
    }

    if( $info_in )
    {
	$explicit = Template::Exception->new($explicit, $info_in, $textref);
    }

    $@ = $explicit if $explicit;

#    debug "Now catcing ".datadump(\$@);
    my $error = catch($@);

    unless( $error )
    {
	confess "Exception without a cause ($@) for Result ".datadump($result);
    }

    if( UNIVERSAL::isa($error, 'Para::Frame::Result::Part') )
    {
	debug "!!!!! THIS ERROR ALREADY PROCESSED !!!!!!";
	return $error;
    }

    run_error_hooks($error);

    return $result->error( $error );
}


=head2 error

  $result->error( $type, $message, $contextref )

  $result->error( $type, $message )

  $result->error( $exception_obj )

Creates a new L<Para::Frame::Result::Part> and adds it to the
result. Clears out $@

Marks the part as hidden if it is of a type that should be hidden or
if hide_all is set.

The part type determines if the result is flagd for backtracking;
making the resulting page uri and template the same as the origin
page.

Returns the part.

=cut

sub error
{
    my( $result, $type, $message, $contextref ) = @_;

    my $error;
    if( ref $type )
    {
	$error = $type;
    }
    else
    {
	unless( $message )
	{
	    confess "Exception without a cause";
	}

	$message =~ s/(\n\r?)+$//;
	if( $contextref and not ref $contextref )
	{
	    $contextref = \ "$contextref";
	}

	$error = Template::Exception->new( $type, $message, $contextref );
    }

#    warn "Clearing our error info\n";
    $@ = undef; # Clear out error info

    my $part = Para::Frame::Result::Part->new($error);

    if( $result->{'hide_part'}{'hide_all'} or
	$result->{'hide_part'}{$type} )
    {
	$part->hide(1);
    }

    push @{$result->{'part'}}, $part;
    $result->{'backtrack'}++ unless $part->no_backtrack;
    $result->{'errcnt'}++;

    return $part;
}

=head2 errcnt

Returns the number of errors in the result.

=cut

sub errcnt
{
    return $_[0]->{'errcnt'};
}

=head2 backtrack

  $result->backtrack()

  $result->backtrack(0)

  $result->backtrack(1)

If given a defined param, sets the switch to that value.

Must be a number. The value will change by future errors.

Returns:

 true if we should backtrack because of the result.

=cut

sub backtrack
{
    if( defined $_[1] )
    {
	$_[0]->{'backtrack'} = $_[1];
    }

    return $_[0]->{'backtrack'};
}

=head2 parts

Returns a reference to a list of all L<Para::Frame::Result::Part>
objects.

=cut

sub parts
{
    return $_[0]->{'part'};
}

=head2 error_parts

Returns all visible error parts.

=cut

sub error_parts
{
    my( $result ) = @_;

    my @res;

    foreach my $part ( @{$result->{'part'}} )
    {
	next if $part->hide;

	next unless $part->error;

	push @res, $part;
    }

    return \@res;
}

=head2 info_parts

Returns all visible info parts.

=cut

sub info_parts
{
    my( $result ) = @_;

    my @res;

    foreach my $part ( @{$result->{'part'}} )
    {
	next if $part->hide;

	next if $part->error;

	push @res, $part;
    }

    return \@res;
}

=head2 find

  $result->find( $type )

$type is the name of the type in string format.

Retruns the first part in the result that is of the specified type.

=cut

sub find
{
    my( $result, $type ) = @_;
    # Find first part of type $type and return it
    debug "Finding part of type $type";
    foreach my $part ( @{$result->parts} )
    {
	debug "  checking part ".$part->as_string;
	next unless $part->type;
	return $part if $part->type eq $type;
    }
    debug "  No such part";
    return undef;
}

=head2 hide_part

  $result->hide_part( $type )
  $result->hide_part()

Hides all errors of the specified type.

Of no type is given; hides all errors.

Nothing returned.

=cut

sub hide_part
{
    my( $result, $type ) = @_;

    # Hide all parts of given type
    # Hide all errors if no type given

    debug 4, "Hiding parts of type $type";

    $type ||= 'hide_all';

    # For hiding future errors
    $result->{'hide_part'}{$type} = 1;

    foreach my $part ( @{$result->{'part'}} )
    {
 	next unless $part->type;
 	if( $type eq 'hide_all' )
 	{
 	    $part->hide(1);
 	}
 	elsif( $part->type eq $type )
	{
	    $part->hide(1);
 	}
     }

    return undef;
}

=head2 as_string

Returns the result in string format.

=cut

sub as_string
{
    my( $result ) = @_;

    my $out = "";
    foreach my $part (@{ $result->parts })
    {
	$out .= $part->as_string . "\n";
    }
    return $out;
}

=head2 incorporate

  $res->import( $res2 )

Import the result from another request into this result.

=cut

sub incorporate
{
    my( $result, $res2 ) = @_;

    debug "Incorporate results";

    push @{$result->{'part'}}, @{$res2->{'part'}};

    $result->{'errcnt'} += $res2->{'errcnt'};
    $result->{'backtrack'} += $res2->{'backtrack'};

    foreach my $key (keys %{$res2->{'hide_part'}})
    {
	$result->{'hide_part'}{$key} = $res2->{'hide_part'}{$key};
    }

    foreach my $key (keys %{$res2->{'info'}})
    {
	debug "  Copying info.$key to result";
	$result->{'info'}{$key} = $res2->{'info'}{$key};
    }

    return 1;
}



1;

=head1 SEE ALSO

L<Para::Frame>

=cut
