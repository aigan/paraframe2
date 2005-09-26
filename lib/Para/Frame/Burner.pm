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
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Burner - Creates output from a template

=cut

use strict;
use Carp qw( croak );
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
use Para::Frame::Utils qw( throw debug uri2file );

sub new
{
    my( $this, $config_in ) = @_;
    my $class = ref($this) || $this;

    my $burner = bless {}, $class;

    my %th_default =
	(
	 INCLUDE_PATH => [ \&incpath_generator ],
	 PRE_PROCESS => 'header_prepare.tt',
	 POST_PROCESS => 'footer.tt',
	 TRIM => 1,
	 PRE_CHOMP => 1,
	 POST_CHOMP => 1,
	 RECURSION => 1,
	 PLUGIN_BASE => 'Para::Frame::Template::Plugin',
	 ABSOLUTE => 1,
	 );

    my $config = {};

    foreach my $key ( keys %th_default )
    {
	$config->{$key} = $th_default{$key};
    }

    foreach my $key ( keys %$config_in )
    {
	$config->{$key} = $config_in->{$key};
    }

    $burner->{'config_in'} = $config_in;
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

sub th
{
    return $_[0]->{'used'}{$Para::Frame::REQ} ||= $_[0]->new_th();
#    my $th = $_[0]->{'used'}{$Para::Frame::REQ} ||= $_[0]->new_th();
#    debug "Using $th";
#    return $th;
}

sub new_th
{
    if( my $th = pop(@{$_[0]->{'free'}}) )
    {
	debug "Getting th from stack";
	return $th;
    }
    else
    {
	debug "Creating new th from config";
	return Template->new($_[0]->{config});
    }
#    return pop(@{$_[0]->{'free'}}) || Template->new($_[0]->{config});
}

sub free_th
{
    my( $burner ) = @_;
    my $req = $Para::Frame::REQ;
    my( $th ) = delete $burner->{'used'}{$req};
    if( $th )
    {
	debug "Releasing th to stack";
	$th->{ _ERROR } = '';
	push @{$burner->{'free'}}, $th;
    }
}

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

sub burn
{
    return shift->th->process(@_);
}

sub error
{
    return $_[0]->th->error;
}

sub incpath_generator
{
    my $req = $Para::Frame::REQ;

    unless( $req->{'incpath'} )
    {
	$req->{'incpath'} = [ map uri2file( $_."inc" )."/", @{$req->{'dirsteps'}} ];
	push @{$req->{'incpath'}}, $Para::Frame::CFG->{'paraframe'}."/inc";
#	debug(0,"Incpath: @{$req->{'incpath'}}");
    }
    return $req->{'incpath'};
}



1;

=head1 SEE ALSO

L<Para::Frame>

=cut
