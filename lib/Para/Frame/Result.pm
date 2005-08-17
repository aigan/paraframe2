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
use Carp qw( carp shortmess croak );
use Clone qw( clone );
use Template::Exception;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( trim debug );

=head1 DESCRIPTION

The result object holds the results of the actions taken and exceptions thrown (L<Para::Frame::Utils/throw>).

=head1 Properties

=head2 info

$result->{info} is the storage space for actions results.  Put your
data in an apropriate subhash.  Example:

  $result->{info}{myresult} = \@listresult;

The info hash is accessed in the template as C<result.info>.

=head1 Exceptions

=head2 dbi

Database or SQL error

=head2 update

Problem occured while trying to store data in the DB.

=head2 incomplete

Some required field in a HTML form was left blank

=head2 validation

A value given in a HTML form was invalid

=head2 confirm

Ask for confirmation of something.  (deprecated)

=head2 template

Format or execution error in the template page

=head2 action

Generic error while executing an action

=head2 compilation

A cimpilation error of Perl code

=head2 notfound

A page (template) or object was requested but not found

=head2 file

Error during file manipulation.  This could be a filesystem permission
error

=cut

our $error_types =
{
    'dbi'        =>
    {
	'title' =>
	{
	    'c'   => 'Databasfel',
	},
	'border'  => 'red',
	'bg'      => 'AAAAAA',
    },
    'update'        =>
    {
	'title'   =>
	{
	    'c' => 'Problem med att spara uppgift',
	},
	'border'  => 'red',
	'bg'      => 'AAAAAA',
    },
    'incomplete' =>
    {
	'title'   =>
	{
	    'c' => 'Uppgifter saknas',
	},
	'bg'      => 'yellow',
    },
    'validation' =>
    {
	'title'   =>
	{
	    'c' => 'Fel vid kontroll',
	},
	'bg'      => 'yellow',
    },
    'alternatives' =>
    {
	'title'   =>
	{
	    'c' => 'Flera alternativ',
	},
    },
    'confirm' =>
    {
	'title'   =>
	{
	    'c' => 'Bekräfta uppgift',
	},
	'bg'      => 'yellow',
    },
    'template'   =>
    {
	'title'   =>
	{
	    'c' => 'Mallfel',
	},
	'view_context' => 1,
    },
    'action'     =>
    {
	'title'   =>
	{
	    'c' => 'Försök misslyckades',
	},
	'bg'      => 'red',
	'view_context' => 1,
    },
    'compilation' =>
    {
	'title'   =>
	{
	    'c' => 'Kompileringsfel',
	},
	'bg'      => 'yellow',
	'border'  => 'red',
    },
    'notfound'     =>
    {
	'title'   =>
	{
	    'c' => 'Hittar inte',
	},
	'bg'      => 'red',
    },
    'denied'     =>
    {
	'title'   =>
	{
	    'c' => 'Access vägrad',
	},
    },
    'file'       =>
    {
	'title' =>
	{
	    'c' => 'Mallfil saknas',
	},
    },
};


sub new
{
    my( $class, $req ) = @_;
    my $self =
    {
	part => [],
#	errcnt => 0,
	info => {},
	main => undef,
        req => $req,
    };

    bless($self, $class);

    # Add info about compilation errors
    foreach my $module ( keys %Para::Frame::Result::COMPILE_ERROR )
    {
#	warn " --> Reporting compile error for $module\n";
	my $errmsg = $Para::Frame::Result::COMPILE_ERROR{$module};
	$self->error('compilation', "$module\n\n$errmsg");
    }

    # Do not count these compile errors, since that would halt
    # everything. We only want to draw atention to the problem but
    # still enable usage
    #
    $self->{errcnt} = 0;


    return $self;
}

sub message
{
    my( $self, @messages ) = @_;

    foreach my $msg ( @messages )
    {
	$msg =~ s/(\n\r?)+$//;
	next unless length $msg;

	if( $msg eq '1' ) # sanity check
	{
	    $self->error('action', shortmess "Message '1' not helpful");
	    next;
	}

	debug(3, shortmess "Adding result message '$msg'");
	push @{$self->{'part'}}, {'message' => $msg};
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

    my $info = ref($@) ? $@->[1] : $error ? $error->info() : $@;
    my $type = ref($@) ? $@->[0] : $error ? $error->type() : undef;
    my $context = $error ? $error->text() : undef;

    $type = undef if $type and $type eq 'undef';

    ## on_error_detect
    #
    Para::Frame->run_hook($self->{'req'}, 'on_error_detect', \$type, \$info );

    $type ||= 'action';

#    warn "Exception defined: $type\n";
    if( $type eq 'undef' )
    {
	die Dumper( $info );
    }

    $self->error($type, $info, $context);

#    warn("Error: ".Dumper($self)."\n");

   return 1;
}

sub error
{
    my( $self, $type, $message, $context ) = @_;

    $message =~ s/(\n\r?)+$//;
#    chomp($message);

    $@ = undef; # Clear out error info

    my $params = clone( $error_types->{$type} ) || {};

    unless( $type )
    {
	$params->{'view_context'} = 1;
    }

    $params->{'type'} ||= $type;
    $params->{'title'}{'c'} ||= "\u$type fel...";
    $params->{'message'} = $message;

    if( $params->{'view_context'} )
    {
	trim(\$context);
	if( length $context )
	{
	    my @lines = split "\n", $context;
	    my $linecount = scalar @lines;
	    warn "Context: $context\n";
	    # Save last five rows
	    $params->{'context'} = join "\n", @lines[-5..-1];
	    $params->{'context_line'} = $linecount;
	}
    }

    push @{$self->{'part'}}, $params;
    $self->{'errcnt'}++;
#    $self->{'type'} ||= $type;

    return undef;
}

sub errcnt
{
    return $_[0]->{'errcnt'};
}

sub parts
{
    return $_[0]->{'part'};
}

sub type
{
    croak "deprecated";
#    return $_[0]->{'type'};
}

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
