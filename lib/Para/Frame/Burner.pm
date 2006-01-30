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
use Para::Frame::Utils qw( throw debug dirsteps );

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

    unless( $config_in->{'INCLUDE_PATH'} )
    {
	$config->{'INCLUDE_PATH'} = [ $burner ];
    }


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

sub th
{
    return $_[0]->{'used'}{$Para::Frame::REQ} ||= $_[0]->new_th();
#    debug "Using $Para::Frame::REQ: $_[0]->{'used'}{$Para::Frame::REQ}";
#    $_[0]->{'used'}{$Para::Frame::REQ} ||= $_[0]->new_th();
#    debug "Now   $Para::Frame::REQ: $_[0]->{'used'}{$Para::Frame::REQ}";
#    return $_[0]->{'used'}{$Para::Frame::REQ};
}

sub new_th
{
    if( my $th = pop(@{$_[0]->{'free'}}) )
    {
	debug 2, "TH retrieved from stack";
	return $th;
    }
    else
    {
	debug 2, "TH created from config";
#	debug "  for $Para::Frame::REQ";
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
	debug 2, "TH released to stack";
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
#    my( $burner ) = shift;
#    return $burner->th->process(@_);
    debug 2, "Burning using $_[0]->{type}";
    return shift->th->process(@_);
}

sub error
{
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
    my( $burner ) = @_;

    my $req = $Para::Frame::REQ;

    unless( $req->{'incpath'} )
    {
	my $type = $burner->{'type'};

	my $site = $req->site;
	my $subdir = 'inc' . $burner->subdir_suffix;

 	my $path_full = $req->{'dirsteps'}[0];
	my $destroot = $req->uri2file($site->home.'/');
	my $dir = $path_full;
	$dir =~ s/^$destroot// or
	  die "destroot $destroot not part of $dir";
	my $paraframedir = $Para::Frame::CFG->{'paraframe'};
	my $htmlsrc = $site->htmlsrc;
	my $backdir = $site->is_compiled ? '/dev' : '/html';

	debug 3, "Creating incpath for $dir with $backdir under $destroot ($type)";

	my @searchpath;

	foreach my $step ( dirsteps($dir), '/' )
	{
	    debug 4, "Adding $step to path";

	    push @searchpath, $htmlsrc.$step.$subdir.'/';

	    foreach my $appback (@{$site->appback})
	    {
		push @searchpath, $appback.$backdir.$step.$subdir.'/';
	    }

	    if( $site->is_compiled )
	    {
		push @searchpath,  $paraframedir.'/dev'.$step.$subdir.'/';
	    }

	    push @searchpath,  $paraframedir.'/html'.$step.'inc/';
	}


	$req->{'incpath'} = [ @searchpath ];


	if( debug > 2 )
	{
	    my $incpathstring = join "", map "- $_\n", @{$req->{'incpath'}};
	    debug "Include path:";
	    debug $incpathstring;
	}

    }

    return $req->{'incpath'};
}



1;

=head1 SEE ALSO

L<Para::Frame>

=cut
