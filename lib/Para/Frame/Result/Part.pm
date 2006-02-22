#  $Id$  -*-perl-*-
package Para::Frame::Result::Part;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Result Part class
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

Para::Frame::Result::Part - Representing an individual result as part of the Result object

=head1 DESCRIPTION

This object should be a compatible standin for Template::Exception,
since it is a container object.

You create a new part by using L<Para::Frame::Result/error>.

=cut

use strict;
use Data::Dumper;
use Carp qw( carp shortmess croak );
use Template::Exception;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( trim debug );


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

Ask for confirmation of something, involving modification of a form in the submitting template

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


our $ERROR_TYPE =
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
	'no_backtrack' => 1,
	'hide'    => 1,
    },
    'confirm' =>
    {
	'title'   =>
	{
	    'c' => 'Bekräfta uppgift',
	},
	'bg'      => 'yellow',
    },
    'action'     =>
    {
	'title'   =>
	{
	    'c' => 'Försök misslyckades',
	},
	'bg'      => '#ff3718',
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
	'no_backtrack' => 1,
    },
    'notfound'     =>
    {
	'title'   =>
	{
	    'c' => 'Hittar inte',
	},
	'bg'      => 'red',
	'no_backtrack' => 1,
    },
    'denied'     =>
    {
	'title'   =>
	{
	    'c' => 'Access vägrad',
	},
    },
    'template'   =>
    {
	'title'   =>
	{
	    'c' => 'Mallfel',
	},
	'view_context' => 1,
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
    my( $this, $params ) = @_;
    my $class = ref($this) || $this;

    $params ||= {};

    if( ref $params eq 'Template::Exception' )
    {
	$params =
	{
	    error => $params,
	};
    }

    my $message = delete $params->{'message'};
    my $part = bless($params, $class);

    $part->add_message($message);
    unless( $part->{'type'} )
    {
	$part->{'view_context'} = 1;
    }

    return $part;
}


############### Compatible with Template::Exception

=head2 info

  $part->info

Returns the error info by L<Template::Exception> info().

=cut

sub info
{
    my( $part ) = @_;

    return $part->error->info;
}

=head2 type

  $part->type

  $part->type( $type )

Returns the error type by L<Template::Exception> type().

If C<$type> is defined, sets it.

=cut

sub type
{
    my( $part, $type ) = @_;

    if( defined $type )
    {
	debug "Setting part type to $type";
	$part->{'type'} = $type;
    }
    return $part->{'type'} || $part->error_type || "";
}


sub type_info
{
    return $_[0]->error->type_info;
}

sub text
{
    my ($part, $newtextref) = @_;


    my $text = $part->{'context'} ||= '';


    if( $newtextref )
    {
	$$newtextref .= $text if $text ne $$newtextref;

	$part->{'context'} = $$newtextref;
        return '';

    }
    else
    {
        return $text;
    }
}

######################################################

sub error_type
{
    if( $_[0]->{'error'} )
    {
	return $_[0]->{'error'}->type;
    }
}

=head2 error

  $part->error

Returns the L<Template::Exception> object.

=cut

sub error
{
    return $_[0]->{'error'};
}

=head2 title

  $part->title

  $part->title( $title )

Returns the part title.

If C<$title> is defined, sets it.

Defaults to title based on C<type>.

=cut

sub title
{
    my( $part, $title ) = @_;

    if( defined $title )
    {
	$part->{'title'} = $title;
    }

    return $part->{'title'} if $part->{'title'};

    my $type = $part->type;
    if( $type )
    {
	return $ERROR_TYPE->{$type}{'title'}{'c'} ||
	    "\u$type fel...";
    }
}

=head2 message

  $part->message

  $part->message( $message )

  $part->message( \@messages )

Returns the part message

First all error info, followed by all the part messages. Joined by
newline.

If C<$message> is defined, sets it.

=cut

sub message
{
    my( $part, $message ) = @_;

    if( $message )
    {
	$part->{'message'} = [ $message ];
    }

    my @message;
    if( $part->error )
    {
	push @message, $part->error->info;
    }

    push @message, @{$part->{'message'}};

    return join "\n", @message;
}

=head2 hide

  $part->hide

  $part->hide( $bool )

Returns true if this part should not be shown to the normal user.

If C<$bool> is defined, sets it.

Defaults to default for the part type.

=cut

sub hide
{
    my( $part, $bool ) = @_;

    if( defined $bool )
    {
	if( $bool eq '1' )
	{
	    $part->{'hide'} = 1;
	}
	elsif( $bool eq '0' )
	{
	    $part->{'hide'} = 0;
	}
	elsif( $bool eq '' )
	{
	    $part->{'hide'} = undef;
	}
	else
	{
	    croak "should only be set with 1, 0 or ''";
	}
    }

    if( defined $part->{'hide'} )
    {
	return $part->{'hide'};
    }
    else
    {
	return $ERROR_TYPE->{ $part->type }{'hide'};
    }
}

=hide2 border

  $part->border

Returns the border colour for displaying the part, if error.

Defaults to default for error type or black.

=cut

sub border
{
    $_[0]->{'border'} || $ERROR_TYPE->{$_[0]->type}{'border'}||'black';
}

=head2 bg

  $part->bg

Returns the background colour for displaying the part, if error.

Defaults to default for error type or #AAAAFF.

=cut

sub bg
{
    $_[0]->{'bg'} || $ERROR_TYPE->{$_[0]->type}{'bg'}||'#AAAAFF';
}

=head2 width

  $part->width

Returns the width of the border (in px) for displaying the part, if
error.

Defaults to default fro error type or 3.

=cut

sub width
{
    $_[0]->{'width'} || $ERROR_TYPE->{$_[0]->type}{'width'}||3;
}

=head2 view_context

  $part->view_context

  $part->view_context( $bool )

Returns true if we should display the context of the error message.

If C<$bool> is defined, sets it.

Defaults to default for error type or false.

=cut

sub view_context
{
    my( $part, $bool ) = @_;

    if( defined $bool )
    {
	if( $bool eq '1' )
	{
	    $part->{'view_context'} = 1;
	}
	elsif( $bool eq '0' )
	{
	    $part->{'view_context'} = 0;
	}
	elsif( $bool eq '' )
	{
	    $part->{'view_context'} = undef;
	}
	else
	{
	    croak "should only be set with 1, 0 or ''";
	}
    }

    if( defined $part->{'view_context'} )
    {
	return $part->{'view_context'};
    }
    else
    {
	return $ERROR_TYPE->{ $part->type }{'view_context'} || 0;
    }
}

=head2 no_backtrack

  $part->no_backtrack

  $part->no_backtrack( $bool )

Returns true if we should not backtrack because of this error, if error.

If C<$bool> is defined, sets it.

Defaults to the default for the error type or false.

=cut

sub no_backtrack
{
    my( $part, $bool ) = @_;

    if( defined $bool )
    {
	if( $bool eq '1' )
	{
	    $part->{'no_backtrack'} = 1;
	}
	elsif( $bool eq '0' )
	{
	    $part->{'no_backtrack'} = 0;
	}
	elsif( $bool eq '' )
	{
	    $part->{'no_backtrack'} = undef;
	}
	else
	{
	    croak "should only be set with 1, 0 or ''";
	}
    }

    if( defined $part->{'no_backtrack'} )
    {
	return $part->{'no_backtrack'};
    }
    else
    {
	return $ERROR_TYPE->{ $part->type }{'no_backtrack'} || 0;
    }
}

=head2 context

  $part->context

Returns the context of the part.

=cut

sub context
{
    my( $part ) = @_;

    unless( $part->{'context'} )
    {
	$part->set_context;
    }
    return $part->{'context'};
}

=head2 context_line

  $part->context_line

Returns the line of the start of the context

=cut

sub context_line
{
    my( $part ) = @_;

    unless( $part->{'context'} )
    {
	$part->set_context;
    }
    return $part->{'context_line'};
}

sub set_context
{
    my( $part ) = @_;

    my $context = $part->{'raw_context'};
    if( $part->error and not $context )
    {
	$context = $part->error->text;
    }

    $part->{'context'} = undef;
    $part->{'context_line'} = undef;

    if( $part->view_context and $context )
    {
	trim(\$context);
	if( length $context )
	{
	    my @lines = split "\n", $context;
	    my $linecount = scalar @lines;
	    # Save last five rows
	    $part->{'context'} = join "\n", @lines[-5..-1];
	    $part->{'context_line'} = $linecount;
	}
    }
}

=head2 prefix_message

  $part->prefix_message

  $part->prefix_message( $message )

Return a message to prefix the message with.

If C<$message> is defined, sets it.

Defaults to undef.

=cut

sub prefix_message
{
    my( $part, $message ) = @_;

    if( $message )
    {
	trim(\$message);
	$part->{'prefix_message'} = $message;
    }
    return $part->{'prefix_message'};
}

=head2 add_message

  $part->add_message( \@messages )

Adds each message to the message list for the part.

Returns L</message>.

=cut

sub add_message
{
    my( $part, @message_in ) = @_;

    $part->{'message'} ||= [];

    foreach( @message_in )
    {
	$_ or next;
	s/(\n\r?)+$//;
	length or next;
	push @{$part->{'message'}}, $_;
    }

    return $part->message;
}

=head2 as_string

  $part->as_string

Returns a representation of the part in plain text format.

=cut

sub as_string
{
    my( $part ) = @_;

    my $out = "";
    my $type = $part->type;

    if( $part->prefix_message )
    {
	$out .= $part->prefix_message . "\n";
    }

    my $msg  = $part->message;
    $out .= "$type:\n$msg\n";

    if( $part->view_context )
    {
	my $line = $part->context_line;
	if( my $context = $part->context )
	{
	    $out .= "Context at line $line:\n";
	    $out .= $context;
	}
    }
    return $out;
}

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
