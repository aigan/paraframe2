#  $Id$  -*-perl-*-
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
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
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
#use Clone qw( clone );
use Template::Exception;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( trim debug );
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
    my $self =
    {
	part => [],
	errcnt => 0,
	backtrack => 0,
	info => {},
	main => undef,
    };

    bless($self, $class);

    # Add info about compilation errors
    foreach my $module ( keys %Para::Frame::Result::COMPILE_ERROR )
    {
#	warn " --> Reporting compile error for $module\n";
	my $errmsg = $Para::Frame::Result::COMPILE_ERROR{$module};
	$self->error('compilation', "$module\n\n$errmsg");
    }

#    # Do not count these compile errors, since that would halt
#    # everything. We only want to draw atention to the problem but
#    # still enable usage
#    #
#    $self->{errcnt} = 0;


    return $self;
}

sub message
{
    my( $self, @messages ) = @_;

    foreach my $msg ( @messages )
    {
	$msg =~ s/(\n\r?)+$//;
	next unless length $msg;

	debug(3, shortmess "Adding result message '$msg'");

	push @{$self->{'part'}}, Para::Frame::Result::Part->new({
	    'message' => $msg,
	});
    }
}

sub exception
{
    my( $self, $explicit, $info, $output ) = @_;

#    warn("Input is ".Dumper($self, $explicit, $@)."\n");

    if( $info )
    {
	$explicit = Template::Exception->new($explicit, $info, $output);
    }

    $@ = $explicit if $explicit;

    # Check if the info part is in fact the exception object
    if(  ref($@) and ref($@->[1]) eq 'ARRAY' )
    {
	$@ = $@->[1]; # $@->[0] is probably 'undef'
    }

#    warn("Exception: ".Dumper($@, \@_)."\n");
    my $error = $Para::Frame::th->{'html'}->error();
    if( $error and not UNIVERSAL::isa($error, 'Template::Exception') )
    {
	$@ = $error;
	$error = undef;
    }

    $info  ||= ref($@) ? $@->[1] : $error ? $error->info() : $@;
    my $type = ref($@) ? $@->[0] : $error ? $error->type() : undef;
    my $context = $error ? $error->text() : undef;

    $type = undef if $type and $type eq 'undef';

    ## on_error_detect
    #
    Para::Frame->run_hook($Para::Frame::REQ, 'on_error_detect', \$type, \$info );

    $type ||= 'action';

#    warn "Exception defined: $type\n";
    if( $type eq 'undef' )
    {
	confess Dumper( $info, \@_ );
    }

    return $self->error($type, $info, \$context);
}

sub error
{
    my( $self, $type, $message, $contextref ) = @_;

    $message =~ s/(\n\r?)+$//;
    unless( ref $contextref )
    {
	$contextref = \ "$contextref";
    }

    my $error = Template::Exception->new( $type, $message, $contextref );

    $@ = undef; # Clear out error info

    my $part = Para::Frame::Result::Part->new($error);

    push @{$self->{'part'}}, $part;
    $self->{'backtrack'}++ unless $part->no_backtrack;
    $self->{'errcnt'}++;

    return $part;
}

sub errcnt
{
    return $_[0]->{'errcnt'};
}

sub backtrack
{
    return $_[0]->{'backtrack'};
}

sub parts
{
    return $_[0]->{'part'};
}

sub find
{
    my( $self, $type ) = @_;
    # Find first part of type $type and return it
    foreach my $part ( @{$self->{'parts'}} )
    {
	next unless $part->{'type'};
	return $part if $part->{'type'} eq $type;
    }
    return undef;
}

sub hide_part
{
    my( $self, $type ) = @_;

    # Hide all parts of given type
    # Hide all errors if no type given

    debug 4, "Hiding parts of type $type";

    foreach my $part ( @{$self->{'part'}} )
    {
	next unless $part->type;
	if( $type )
	{
	    if( $part->type eq $type )
	    {
		$part->hide(1);
	    }
	}
	else
	{
	    $part->hide(1);
	}
    }
    return undef;
    
}

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

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
