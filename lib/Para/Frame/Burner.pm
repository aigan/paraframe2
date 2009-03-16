package Para::Frame::Burner;
#=====================================================================
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
#=====================================================================

=head1 NAME

Para::Frame::Burner - Creates output from a template

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( croak cluck confess );
use Template;
use Template::Exception;
use Template::Config;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );

our %TYPE;
our %EXT;

=head2 DESCRIPTION

There are three standard burners.

  html     = The burner used for all tt pages

  plain    = The burner used for emails and other plain text things

  html_pre = The burner for precompiling of tt pages

They are defined by L<Para::Frame/configure> in C<th>.

=cut

#######################################################################

=head2 new

=cut

sub new
{
    my( $this, $config_in ) = @_;
    my $class = ref($this) || $this;

    my $burner = bless {}, $class;


    my $config = {};

#    my %th_default = ();
#    foreach my $key ( keys %th_default )
#    {
#	$config->{$key} = $th_default{$key};
#    }

    foreach my $key ( keys %$config_in )
    {
	next if $key eq 'type';
	$config->{$key} = $config_in->{$key};
    }

# To be set dynamicly
#    $config->{'INCLUDE_PATH'}
#      = $config_in->{'INCLUDE_PATH'} || [ $burner ];

    $burner->{'type'} = $config_in->{'type'} or
      croak "No type given for burner";

    $burner->{'subdir_suffix'} = $config_in->{'subdir_suffix'} || '';
    $burner->{'pre_dir'} = $config_in->{'pre_dir'}
      or croak "No pre_dir given for burner";
    $burner->{'inc_dir'} = $config_in->{'inc_dir'}
      or croak "No inc_dir given for burner";

    $burner->{'config'} = $config;
    $burner->{'free'} = [];
    $burner->{'used'} = {};


    Para::Frame->add_hook('on_error_detect', sub {
	my( $typeref, $inforef, $contextref ) = @_;

	$typeref ||= \ "";
	$contextref ||= \ "";
	$inforef ||= \ "";

	if( my $error = $burner->error() )
	{
	    return unless $error;
	    if( not UNIVERSAL::isa($error, 'Template::Exception') )
	    {
		$$inforef .= "\n". $error;
	    }
	    else
	    {
		# It may already have been noted
		return if $error->type eq $$typeref;

		$$typeref ||= $error->type;
		$$inforef .= "\n". $error->info;
		$$contextref ||= $error->text;
	    }
	}
    });

    Para::Frame->add_hook('done', sub {
	$burner->free_th;
    });

    return $burner;
}

#######################################################################

=head2 add

  Para::Frame::Burner->add( \%config )

Adds a burner.

Se sourcecode for details...

=cut

sub add
{
    my( $this, $config_in ) = @_;
    my $class = ref($this) || $this;

    my $burner = $class->new( $config_in );

    my $handles = $burner->{'config'}{'handles'} || [];
    $handles = [$handles] unless ref $handles;

    my $type = $burner->{'type'} or die "Type missing";

    foreach my $ext ( @$handles )
    {
	$EXT{$ext} = $burner;
	debug "Regestring ext $ext to burner $type";
    }

    $TYPE{ $type } = $burner;

    return $burner;
}


#######################################################################

=head2 get_by_ext

  Para::Frame::Burner->get_by_ext( $ext )

Returns the burner registred for the extension.

Returns undef if no burner registred with the extension.

=cut

sub get_by_ext
{
    my( $this, $ext ) = @_;

    $ext or confess "ext missing";

    if( my $burner = $EXT{$ext} )
    {
	my $type = $burner->{'type'};
	debug 5, "Looked up burner for $ext: $type";
	return $burner;
    }
    else
    {
#	debug "No burner found for ext '$ext'";
	return undef;
    }
}

#######################################################################

=head2 add_ext

  $burner->add_ext( $ext )

Adds an extension handler to a burner.

Returns the number of extensions added.

=cut

sub add_ext
{
    my( $burner, $ext ) = @_;

    $ext or confess "ext missing";

    if( my $burner_old = $EXT{$ext} )
    {
	if( $burner eq $burner_old )
	{
	    return 0;
	}
	else
	{
	    confess "Ext $ext already assigned to burner ".
	      $burner_old->type;
	}
    }
    else
    {
	$EXT{$ext} = $burner;
	debug "Regestring ext $ext to burner ".$burner->type;
	return 1;
    }
}

#######################################################################

=head2 get_by_type

  Para::Frame::Burner->get_by_type( $type )

Returns the burner registred for the type.

Returns undef if no burner registred with the type.

=cut

sub get_by_type
{
    return $TYPE{($_[1]||'')};
}

#######################################################################

=head2 th

  $burner->th()

=cut


sub th
{
    # Send the params to new_th()
    return $_[0]->{'used'}{$Para::Frame::REQ} ||= $_[0]->new_th();
}

sub new_th
{
    my( $th );
    if( $th = pop(@{$_[0]->{'free'}}) )
    {
	debug 2, "TH retrieved from stack";
    }
    else
    {
	debug 2, "TH created from config";
	$th = Template->new($_[0]->{config});

	# Set up shortcut to modify include path
	$th->{'pf_include_path'} = [];
	$th->context->load_templates->[0]->
	  include_path($th->{'pf_include_path'});
    }

    return $th;
}


#######################################################################

=head2 free_th

=cut

sub free_th
{
    my( $burner ) = @_;
    my( $th ) = delete $burner->{'used'}{$Para::Frame::REQ};
    if( $th )
    {
	debug 2, "TH released to stack";
	$th->{ _ERROR } = '';
	push @{$burner->{'free'}}, $th;
    }
}


#######################################################################

=head2 add_filters

  $burner->add_filters( \%filters )

  $burner->add_filters( \%filters, $dynamic )

Adds a filter to the burner. Availible in all templates that uses the
burner. If C<$dynamic> is true, adds all the filters as dynamic
filters. Default is to add them as static filters.

C<%filters> is a hash with the filter name and the coderef.

Example:

  Para::Frame::Burner->get_by_type('html')->add_filters({
      'upper_case' => sub{ return uc($_[0]) },
  });


=cut

sub add_filters
{
    my( $burner, $params, $dynamic ) = @_;

    my $filters = $burner->{'config'}{FILTERS} ||= {};

    $dynamic ||= 0;

    foreach my $name ( keys %$params )
    {
	$filters->{$name} = [$params->{$name}, $dynamic];
    }
}


#######################################################################

=head2 context

=cut

sub context
{
    return $_[0]->th->context;
}


#######################################################################

=head2 compile_dir

=cut

sub compile_dir
{
    die datadump($_[0]->{'config'}) unless $_[0]->{'config'}{ COMPILE_DIR };
    return $_[0]->{'config'}{ COMPILE_DIR };
}


#######################################################################

=head2 parser

=cut

sub parser
{
    return Template::Config->parser($_[0]->{'config'});
}


#######################################################################

=head2 provider

=cut

sub providers
{
    return $_[0]->th->context->load_templates();
}


#######################################################################

sub error_hash #not used
{
    return $_[0]->th->{ _ERROR };
}


#######################################################################

=head2 burn

  $burner->burn( $renderer, @tt_process_params )

Calls L<Template/process> with the given params.

Example:

  $burner->burn( $renderer, $in, $page->{'params'}, \$out)

=cut

sub burn
{
    my( $burner, $renderer, $in, $params, $out ) = @_;
    my $th = $burner->th();
    $th->{'pf_include_path'}[0] = $renderer;
    my $res = $th->process($in, $params, $out, {binmode=>':utf8'});
    if( $res )
    {
#	debug "Burning successful";
	return $res;
    }
    else
    {
	my $err = $th->error();
#	debug "Checking out error: ".datadump($err);
	die( $err );
    }

}

#######################################################################

=head2 error

  $burner->error

Returns the L<Template::Exception> from the burning, if any.

# TODO: Take care of result early, and save the info

=cut

sub error
{
    return undef unless $Para::Frame::REQ;
    my $th = $_[0]->{'used'}{$Para::Frame::REQ};
    return undef unless $th;
    my $error = $th->error or return 0;
    $error = Template::Exception->new('template',$error) unless ref $error;
    return $error;
}


#######################################################################

=head2 subdir_suffix

=cut

sub subdir_suffix
{
     return $_[0]->{'subdir_suffix'} || '';
}


#######################################################################

=head2 pre_dir

=cut

sub pre_dir
{
     return $_[0]->{'pre_dir'};
}


#######################################################################

=head2 inc_dir

=cut

sub inc_dir
{
     return $_[0]->{'inc_dir'};
}


#######################################################################

=head2 type

=cut

sub type
{
     return $_[0]->{'type'};
}


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
