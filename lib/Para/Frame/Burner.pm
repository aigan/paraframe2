#  $Id$  -*-perl-*-
package Para::Frame::Burner;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Burner class
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

Para::Frame::Burner - Creates output from a template

=cut

use strict;
use Carp qw( croak cluck );
use Data::Dumper;
use Template;
use Template::Exception;
use Template::Config;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

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

    $config->{'INCLUDE_PATH'}
      = $config_in->{'INCLUDE_PATH'} || [ $burner ];

    $burner->{'type'} = $config_in->{'type'} or
      croak "No type given for burner";

    $burner->{'subdir_suffix'} = $config_in->{'subdir_suffix'} || '';


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


=head2 get_by_ext

  Para::Frame::Burner->get_by_ext( $ext )

Returns the burner registred for the extension.

Returns undef if no burner registred with the extension.

=cut

sub get_by_ext
{
    my( $this, $ext ) = @_;

    $ext or die "ext missing";

    if( my $burner = $EXT{$ext} )
    {
	my $type = $burner->{'type'};
	debug 2, "Looked up burner for $ext: $type";
	return $burner;
    }
    else
    {
	debug "No burner found for ext '$ext'";
	return undef;
    }


#    return $EXT{($_[1]||'')};
}

=head2 get_by_type

  Para::Frame::Burner->get_by_type( $type )

Returns the burner registred for the type.

Returns undef if no burner registred with the type.

=cut

sub get_by_type
{
    return $TYPE{($_[1]||'')};
}


sub th
{
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
    }

    return $th;
}

sub free_th
{
    my( $burner ) = @_;
    my $req = $Para::Frame::REQ;
    my( $th ) = delete $burner->{'used'}{$req};
    if( $th )
    {
	debug 2, "TH released to stack";
	$th->{ _ERROR } = '';
	push @{$burner->{'free'}}, $th;
    }
}

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

sub context
{
    return $_[0]->th->context;
}

sub compile_dir
{
    die Dumper $_[0]->{'config'} unless $_[0]->{'config'}{ COMPILE_DIR };
    return $_[0]->{'config'}{ COMPILE_DIR };
}

sub parser
{
    return Template::Config->parser($_[0]->{'config'});
}

sub providers
{
    return $_[0]->th->context->load_templates();
}

sub error_hash #not used
{
    return $_[0]->th->{ _ERROR };
}

=head2 burn

  $burner->burn( @params )

Calls L<Template/process> with the given params.

Example:

  $burner->burn( $in, $page->{'params'}, \$out)

=cut

sub burn
{
#    my $th = shift->th;
#    my $reqnum = $Para::Frame::REQ->id;
#    my $page = $Para::Frame::REQ->page;
#    debug "Burning with $th in req $reqnum with page $page";
#    if( $page->incpath )
#    {
#	my $incpathstring = join "", map "- $_\n", @{$page->incpath};
#	debug "Include path:";
#	debug $incpathstring;
#    }
#    return $th->process(@_);

    return shift->th->process(@_);

#### It's not possible to generate page in fork, since it returns
#### resulting page by modifying the page ref sent as an param

#    my $fork = $Para::Frame::REQ->create_fork;
#    if( $fork->in_child )
#    {
#	debug 2, "Burning using $_[0]->{type}";
#	my $res = $_[0]->th->process(@_);
#	$fork->return( $res );
#    }
#    $fork->yield;
}

=head2 error

  $burner->error

Returns the L<Template::Exception> from the burning, if any.

=cut

sub error
{
    return undef unless $Para::Frame::REQ;
    my $th = $_[0]->{'used'}{$Para::Frame::REQ};
    return undef unless $th;
    my $error = $th->error or return 0;
#    warn Dumper $error;
    $error = Template::Exception->new('template',$error) unless ref $error;
    return $error;
}

sub subdir_suffix
{
     return $_[0]->{'subdir_suffix'} || '';
}

sub paths
{
    return $Para::Frame::REQ->page->paths($_[0]);
}

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
