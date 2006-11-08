#  $Id$  -*-cperl-*-
package Para::Frame::Renderer::TT;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework TT Renderer
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Renderer::TT - Renders a TT page

=cut

use strict;
use Carp qw( croak confess cluck );
#use IO::File;
#use Encode qw( is_utf8 );
#use File::Basename; # exports fileparse, basename, dirname
#use File::stat; # exports stat
#use File::Slurp; # Exports read_file, write_file, append_file, overwrite_file, read_dir
#use Scalar::Util qw(weaken);
#use Data::Dumper;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch );
use Scalar::Util qw(weaken);


#######################################################################

=head1 Constructors

=cut

#######################################################################

=head2 new

params:

  umask

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    $args ||= {};

    my $rend = bless
    {
     'page'           => undef,
     'template'       => undef,
     'incpath'        => undef,
     'params'         => undef,
     'burner'         => undef,          ## burner used for page
    };


    my $page = $rend->{'page'} = $args->{'page'}
      or confess "page param missing";

#    debug "=======> Created renderer for page ".$page->url_path;

    # Cache template
    my $tmpl = $rend->{'template'} = $args->{'template'} || $page->template;

    unless( ref $tmpl )
    {
	unless( $tmpl )
	{
	    throw('notfound', "No template found for ".$page->url_path);
	}

	confess "Template $tmpl not an object";
    }


    $rend->{'params'} = {%$Para::Frame::PARAMS};
#    $rend->{'umask'} = $args->{'umask'} || 002;

    return $rend;
}


#######################################################################

=head2 render_output

  $p->render_output()

Burns the page and stores the result.

If the rendering failes, may change the template and URL. The new URL
can be used for another call to this method.

This method is called by L<Para::Frame::Request/after_jobs>.

Returns: True on success and 0 on failure

=cut

sub render_output
{
    my( $rend ) = @_;

#    # Maby we have a page generated already
#    return 1 if $resp->{'content'};

#    # Don't burn if this is a HEAD request
#    return 1 if $req->header_only;

    ### Output page
    my $page = $rend->page;
    unless( $page )
    {
	confess "No page ".datadump($rend,2);
    }

    my $out = "";

    my $site = $page->site;
    my $home = $site->home_url_path;

    $Para::Frame::REQ->note("Rendering page");

    my $tmpl = $rend->template;
    unless( $tmpl )
    {
	cluck "Template not found";
	throw('notfound', "Couldn't find a template for ".$rend->page->url_path);
    }

    my $in = $tmpl->document;

    my $burner = $rend->burner;
    if( not $burner )
    {
	debug "Getting '$in' as a static page";
	$rend->get_static( $in, \$out );
    }
    else
    {
	$rend->set_tt_params;

	$rend->burn($in, \$out) or return 0;
    }

    return( \$out );
}



#######################################################################

=head2 burner

  $p->burner

Returns: the L<Para::Frame::Burner> selected for this page

=cut

sub burner
{
    unless( $_[0]->{'burner'} )
    {
	my( $rend ) = @_;
	my $ext = $rend->template->suffix;
	$rend->set_burner_by_ext( $ext );
    }

    return $_[0]->{'burner'};
}

#######################################################################

=head2 set_burner_by_type

  $p->set_burner_by_type( $type )

Calls L<Para::Frame::Burner/get_by_type> and store it in the page
object.

Returns: the burner

=cut

sub set_burner_by_type
{
    return $_[0]->{'burner'} =
      Para::Frame::Burner->get_by_type($_[1])
	  or die "Burner type $_[1] not found";
}

#######################################################################

=head2 set_burner_by_ext

  $p->set_burner_by_ext( $ext )

Calls L<Para::Frame::Burner/get_by_ext> and store it in the page
object.

Returns: the burner

=cut

sub set_burner_by_ext
{
    return $_[0]->{'burner'} =
      Para::Frame::Burner->get_by_ext($_[1])
	  or die "Burner ext $_[1] not found";
}

#######################################################################

=head2 burn

  $p->burn( $in, $out );

Calls L<Para::Frame::Burner/burn> with C<($in, $params, $out)> there
C<$params> are set by L</set_tt_params>.

Returns: the burner

=cut

sub burn
{
    my( $rend, $in, $out ) = @_;
    return $rend->{'burner'}->burn($rend, $in, $rend->{'params'}, $out );
}

#######################################################################

=head2 set_tt_params

The standard functions availible in templates. This is called before
the page is rendered. You should not call it by yourself.

=over

=item browser

The L<HTTP::BrowserDetect> object.  Not in StandAlone mode.

=item dir

The directory part of the filename, including the last '/'.  Symlinks
resolved.

=item u

$req->{'user'} : The L<Para::Frame::User> object.

=item ENV

$req->env: The Environment hash (L<http://hoohoo.ncsa.uiuc.edu/cgi/env.html>).  Only in client mode.

=item filename

Holds the L<Para::Frame::Request/filename>.

=item home

$req->site->home : L<Para::Frame::Site/home>

=item lang

The L<Para::Frame::Request/preffered_language> value.

=item me

Holds the L<Para::Frame::File/url_path_slash> for the page, except if
an L<Para::Frame::Request/error_page_selected> in which case we set it
to L<Para::Frame::Request/original_response> C<page>
C<url_path_slash>.  (For making it easier to link back to the intended
page)

=item q

The L<CGI> object.  You will probably mostly use
[% q.param() %] method. Only in client mode.

=item req

The C<req> object.

=item reqnum

The paraframe server request number

=item result

$req->{'result'} : The L<Para::Frame::Result> object

=item site

The <Para;;Frame::Site> object.

=back

=cut

sub set_tt_params
{
    my( $rend ) = @_;

    my $req = $Para::Frame::REQ;
    my $page = $rend->page;
    my $site = $page->site or confess "no site: ".$page->sysdesig;
    my $me = $page->url_path_slash;

    if( $req->{'q'} )
    {
	if( $req->error_page_selected )
	{
	    $me = $req->original_response->page->url_path;
	}

	$rend->add_params({
			   'q'               => $req->{'q'},
			   'ENV'             => $req->env,
			  });
    }

    # Keep alredy defined params  # Static within a request
    $rend->add_params({
	'page'            => $page,

	'me'              => $me,

	'u'               => $Para::Frame::U,
	'lang'            => $req->language->preferred, # calculate once
	'req'             => $req,

	# Is allowed to change between requests
	'site'            => $site,
	'home'            => $site->home_url_path,
    });

    # Add local site params
    if( $site->params )
    {
	$rend->add_params($site->params);
    }
}


#######################################################################

=head2 add_params

  $resp->add_params( \%params )

  $resp->add_params( \%params, $keep_old_flag )

Adds template params. This can be variabls, objects, functions.

If C<$keep_old_flag> is true, we will not replace existing params with
the same name.

=cut

sub add_params
{
    my( $resp, $extra, $keep_old ) = @_;

    my $param = $resp->{'params'} ||= {};

    if( $keep_old )
    {
	while( my($key, $val) = each %$extra )
	{
	    next if $param->{$key};
	    unless( defined $val )
	    {
		debug "The TT param $key has no defined value";
		next;
	    }
	    $param->{$key} = $val;
	    debug(4,"Add TT param $key: $val") if $val;
	}
    }
    else
    {
	while( my($key, $val) = each %$extra )
	{
	    unless( defined $val )
	    {
		debug "The TT param $key has no defined value";
		next;
	    }
	    $param->{$key} = $val;
	    debug(2, "Add TT param $key: $val");
	}
     }
}


#######################################################################

=head2 get_static

  $rend->get_static( $in, $pageref )

C<$pageref> must be a scalar ref.

C<$in> must be a L<IO::File> or a filename to be sent to
L<IO::File/new>.

Places the content of the file in C<$pageref>.

Returns: C<$pageref>

=cut

sub get_static
{
    my( $page, $in, $pageref ) = @_;

    $pageref or die "No pageref given";
    my $out = "";

    unless( ref $in )
    {
	$in = IO::File->new( $in );
    }


    if( ref $in eq 'IO::File' )
    {
	$out .= $_ while <$in>;
    }
    else
    {
	warn "in: $in\n";
	die "What can I do";
    }

    my $length = length($out);
    debug "Returning page with $length bytes";

    # Use the same scalar thingy
    return $$pageref = $out;
}


#######################################################################

sub page
{
    return $_[0]->{'page'};
}

#######################################################################

sub template
{
    return $_[0]->{'template'};
}


#######################################################################


=head2 paths

  $p->paths( $burner )

Automaticly called by L<Template::Provider>
to get the include paths for building pages from templates.

Returns: L</incpath>

=cut

sub paths
{
    my( $rend ) = @_;

    unless( $rend->{'incpath'} )
    {
	my $burner = $rend->burner
	  or confess "Page burner not set";
	my $type = $burner->{'type'};

	my $page = $rend->page;
	my $site = $page->site;


 	my $path_full = $page->dirsteps->[0];
	my $destroot = $site->home->sys_path;
	my $dir = $path_full;
	unless( $dir =~ s/^$destroot// )
	{
	    warn "destroot $destroot not part of $dir";
	    warn datadump($page->dirsteps);
	    warn datadump($page,2);
	    die;
	}
	my $paraframedir = $Para::Frame::CFG->{'paraframe'};
	my $htmlsrc = $site->htmlsrc;

	my $subdir = 'inc' . $burner->subdir_suffix;

	my @places;
	if( $site->is_compiled )
	{
	    @places =
	      (
	       {
		subdir => $subdir,
		backdir => '/dev',
	       },
	       {
		subdir => 'inc',
		backdir => '/html',
	       },
	      );
	}
	else
	{
	    @places =
	      (
	       {
		subdir => $subdir,
		backdir => '/html',
	       },
	      );
	}


	debug 3, "Creating incpath for $dir under $destroot ($type)";

	my @searchpath;

	foreach my $step ( Para::Frame::Utils::dirsteps($dir), '/' )
	{
	    push @searchpath, $htmlsrc.$step.$subdir.'/';

	    foreach my $appback (@{$site->appback})
	    {
		foreach my $place (@places)
		{
		    push @searchpath, ( $appback.$place->{'backdir'}.
					$step.$place->{'subdir'}.'/'
				      );
		}
	    }

	    foreach my $place (@places)
	    {
		push @searchpath, ($paraframedir.$place->{'backdir'}.
				   $step.$place->{'subdir'}.'/'
				  );
	    }
	}


	$rend->{'incpath'} = [ @searchpath ];


	if( debug > 2 )
	{
	    my $incpathstring = join "", map "- $_\n", @searchpath;
	    debug "Include path:";
	    debug $incpathstring;
	}

    }

    return $rend->{'incpath'};
}


#######################################################################


1;

=head1 SEE ALSO

L<Para::Frame>

=cut
