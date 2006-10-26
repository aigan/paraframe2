#  $Id$  -*-cperl-*-
package Para::Frame::Site::Page;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Page class
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

Para::Frame::Site::Page - Represents the response page for a req

=head1 DESCRIPTION

Represents a page on a site with a specific URL.

Inherits from L<Para::Frame::File>

During lookup or generation of the page, the URL of the page can
change. We differ between the original requested URL, the resulting
URL and an URL for the template used.

A L<Para::Frame::Request> will create a L<Para::Frame::Site::Page> object
representing the response page.

A request can also create other Page objects for representing other
pages for getting information about them or for generating pages for
later use, maby not specificly copupled to the current request or
session.

The distinction between Para::Frame::Request and Para::Frame::Site::Page are
still a litle bit vauge. We should separate more clearly between the
requested URL and the URL used for the response and the template used
for the response.

Methods for generating the response page and accessing info about that
page has been collected here.

A Site can answer under many hosts. The host of a Page vary with the
request. The language given by the request is used also for actions
and not just for the response page.

Each Request has C<one> response Page object. It may first be a normal
template and then change to generate an error page if action or
template throw an exception. But it is still the same object.

I may change that so that a new Page object is created if there was a
redirection to a new page.

=cut

use strict;
use Carp qw( croak confess cluck );
use IO::File;
use Encode qw( is_utf8 );
use File::Basename; # exports fileparse, basename, dirname
use File::stat; # exports stat
use File::Slurp; # Exports read_file, write_file, append_file, overwrite_file, read_dir
use Scalar::Util qw(weaken);
use Data::Dumper;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use base qw( Para::Frame::Page );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch );
use Para::Frame::Request::Ctype;
use Para::Frame::URI;
use Para::Frame::L10N qw( loc );
use Para::Frame::Dir;
use Para::Frame::File;
use Para::Frame::Page;


#######################################################################

=head1 Constructors

=cut

#######################################################################

=head2 new

See L<Para::Frame::Page>

This constructor is usually called by L</response_page>.

=cut

#######################################################################

=head2 response_page

  Para::Frame::Site::Page->response_page( $req )

Creates and initiates the page object for the request. (Not used for
page objects not to be used as the response page.)

Gets the site to use from L<Para::Frame::Request/dirconfig> or from
L<Para::Frame::Request/host_from_env>.

Calls L</new> with the url and ctype from the request.

Returns: a L<Para::Frame::Site::Page> object

=cut

sub response_page
{
    my( $this, $req ) = @_;
    my $class = ref($this) || $this;
    unless( ref $req eq 'Para::Frame::Request' )
    {
	die "req missing";
    }

    my $site = Para::Frame::Site->get_by_req( $req );

    unless( $site->host eq $req->host_from_env )
    {
	die sprintf "Site %s doesn't match req host %s",
	    $site->host, $req->host_from_env;
    }


    my $page = $class->new({
			    site     => $site,
			    url      => $req->{'orig_url'},
			    ctype    => $req->{'orig_ctype'},
			    req      => $req,
			    language => $req->language,
			   });

    return $page;
}

#######################################################################

=head1 Accessors

See L<Para::Frame::File/Accessors>

=cut


#######################################################################


=head2 url_path_tmpl

The path and filename in http on the host. With the language part
removed.

=cut

sub url_path_tmpl
{
    return $_[0]->{'tmpl_url_name'} || $_[0]->url_path_slash;
}

#######################################################################

=head2 path_tmpl

The path to the template, including the filename, relative the site
home, begining with a slash.

=cut

sub path_tmpl
{
    my( $page ) = @_;

    my $home = $page->site->home_url_path;
    my $template = $page->url_path_tmpl;
    my( $site_url ) = $template =~ /^$home(.+?)$/
      or confess "Couldn't get site_url from $template under $home";
    return $site_url;
}



#######################################################################


=head2 is_index

True if this is a C</index.tt>

=cut

sub is_index
{
    if( $_[0]->{'url_norm'} =~ /\/$/ )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}


#######################################################################

=head2 error_page_selected

  $page->erro_page_selected

True if an error page has been selected

=cut

sub error_page_selected #error_template
{
    return $_[0]->{'error_template'} ? 1 : 0;
}

#######################################################################


=head2 error_page_not_selected

  $page->error_page_not_selected

True if an error page has not been selected

=cut

sub error_page_not_selected
{
    return $_[0]->{'error_template'} ? 0 : 1;
}

#######################################################################


=head2 headers

  $p->headers

Returns: the http headers to be sent to the client as a list of
listrefs of key/val pairs.

=cut

sub headers
{
    return @{$_[0]->{'headers'}};
}


#######################################################################

=head2 orig

  $p->orig

Returns: the original url as a L<Para::Frame::File> object.

TODO: Cache object

=cut

sub orig
{
    my( $page ) = @_;

    unless( $page->{'orig'} )
    {
	my $umask = $page->{umask} or confess "No umask";

	$page->{'orig'} =
	    Para::Frame::File->new({
				    url => $page->{orig_url_name},
				    site => $page->site,
				    no_check => 1,
				    umask => $umask,
				   });
    }
    return $page->{'orig'};
}


#######################################################################

=head2 orig_url

  $p->orig_url

Returns: the original L<URI> object (given then the pageobject was
created), including the scheme, host and port. (But using the current
site info.)

=cut

sub orig_url
{
    my( $page ) = @_;

    my $site = $page->site;
    my $scheme = $site->scheme;
    my $host = $site->host;
    my $url_string = sprintf("%s://%s%s",
			     $scheme,
			     $host,
			     $page->{orig_url_name});

    return Para::Frame::URI->new($url_string);
}


#######################################################################

=head2 orig_url_path

  $p->orig_url_path

Returns: The original URL path. Dirs may or may not have a trailing
slash.

=cut

sub orig_url_path
{
    return $_[0]->{'orig_url_name'};
}


#######################################################################

=head2 redirection

  $p->redirection

Returns the page we will redirect to, or undef.

=cut

sub redirection
{
    return $_[0]->{'redirect'};
}


#######################################################################

=head2 template

  $p->template()

  $p->template($params)

C<$params> will be sent to L</find_template>.

Returns the (current) L<Template::Document> object for this page, as
returned by L</find_template> given L</url_path_tmpl>.

The document object can be used for getting variables set in the
C<META> part of the template, via L<Template::Document/AUTOLOAD>.

Example:

If the template contains [% META section="games" %] you can get that
value by saying:

  my $section = $p->template->section;

C<section> has no special meaning in paraframe. ... You can also get
the specially used variables like C<next_action>, et al.

Returns: The L<Template::Document> object

=cut

sub template
{
    my( $page, $params ) = @_;

#    debug "->template calling find_template with ".datadump($params);
    my( $tmpl ) = $page->find_template( $page->url_path_tmpl, $params );

    return $tmpl;
}

#######################################################################

=head1 Public methods

=cut

#######################################################################

=head2 set_headers

  $p->set_headers( [[$key,$val], [$key2,$val2], ... ] )

Same as L</add_header>, but replaces any existing headers.

=cut

sub set_headers
{
    my( $page, $headers ) = @_;

    $page->{'headers'} = $headers;
}

#######################################################################

=head2 set_header

  $p->set_header( $key => $val )

Replaces any existing header with the same key.

Returns:

The number of changes

=cut

sub set_header
{
    my( $page, $key, $val ) = @_;

    my $changes = 0;
    foreach my $part ( @{$page->{'headers'}} )
    {
	if( $key eq $part->[0] )
	{
	    $part->[1] = $val;
	    $changes ++;
	}
    }

    unless( $changes )
    {
	push @{$page->{'headers'}}, [$key,$val];
	$changes ++;
    }


    return $changes;
}

#######################################################################


=head2 add_header

  $p->add_header( [[$key,$val], [$key2,$val2], ... ] )

Adds one or more http response headers.

This sets headers to be used if this page is sent to the client. They
can be changed until they are actually sent.

=cut

sub add_header
{
    push @{ shift->{'headers'}}, [@_];
}

#######################################################################

=head2 set_template

  $p->set_template( $url_path )

  $p->set_template( $url_path, $always_move_flag )

  $p->set_template( $url_path, $always_move_flag, $params )

C<$url_path> should be the URL path including the filename. This can
later be retrieved by L</url_path_tmpl>.

Redirection to other pages can be done by using this method. Even from
inside a page being generated.

To forward to a page not handled by the paraframe server, use
L</redirect>.

Apache can possibly be rewriting the name of the file. For example the
url C</this.tt> may be translated to, based on Apache config, to
C</var/www/that.tt>.

The url_path to file translation is used for getting the directory of
the url_path. But we assume that the filename part of the URL
represents an actual file, regardless of the uri2file translation. If
the translation goes to another file, that file will be ignored and
the file named like that in the URL will be used.

For example: If the site path is C</var/www> and we have a path
translation in the apache config that translates C</one/two.tt> to
C</var/www/three/four.tt> we will be using the url_path
C</var/www/three/two.tt> using the dir but disregarding the filename
change.

We want to tell browsers/spiders if any redirection is a permanent or
temporary one. We assume it's a temporary one unless
C<$always_move_flag> is true. But if just one move is of temporary
nature, keep that value. This will only be used if we are ending up
redirecting to another page.

The content type is set to C<text/html> if this is a C<.tt> file.

params:

  keep_langpart
  create_missing_dirs
  no_check

=cut

sub set_template
{
    my( $page, $url_in, $args ) = @_;

    # For setting a template diffrent from the URL

#    debug("set_template $url_in ".datadump($args,1)); ### DEBUG

    my $req = $page->req;

    my( $template, $url_norm, $url_name );

    if( UNIVERSAL::isa($url_in, 'Para::Frame::Page') )
    {
	confess "check this";

	$template = $url_in->{tmpl_url_name};
	$url_norm = $url_in->{url_norm};
	$url_name = $url_in->{url_name};
    }
    else
    {
	if( UNIVERSAL::isa $url_in, 'URI' )
	{
	    $url_in = $url_in->path;
	}

	if( $url_in =~ /^http/ )
	{
	    # template param should NOT include the http://hostname part
	    croak "Tried to set a template to $url_in";
	}


	####### URL_NORM -> url_path_slash
	#
	$url_norm = $req->normalized_url( $url_in, $args );


	####### TEMPLATE -> url_path_tmpl
	#
	$template = $url_norm;
	if( $template =~ /\/$/ )
	{
	    # Template indicates a dir. Make it so
	    $template .= "index.tt";
	}

	if( my $lang = $args->{'language'} )
	{
	    my $code = $lang->code;
	    if( $template =~ /\/([^\/]+)(\.\w{2})\.tt$/ )
	    {
		unless( $2 eq $code )
		{
		    confess "Language mismatch ($template != $code)";
		}
	    }
	    else
	    {
		debug "Setting language to $code";
		$template =~ s/\/([^\/]+)\.tt$/\/$1.$code.tt/;
	    }
	}


	####### URL_NAME -> url_path
	#
	$url_name = $url_norm;
	$url_name =~ s/\/$//; # Remove trailins slash

	#######

	debug(3,"setting template to $template");
	debug(3,"setting url_norm to $url_norm");
    }

    $page->{tmpl_url_name}     = $template;
    $page->{url_norm}          = $url_norm;
    $page->{url_name}          = $url_name;
    $page->{sys_name}          = undef;

    $page->ctype->set("text/html") if $template =~ /\.tt$/;

    my $always_move = $args->{'always_move'} || 0;
    $page->{'moved_temporarily'} ||= 1 unless $always_move;

    return $template;
}

=head2 set_error_template

  $p->set_error_template( $path_tmpl )

Calls L</set_template> for setting the template. Sets a flag for
remembering that this is an error response page.

NB! Should be called with a L</path_tmpl> and not a
L<url_path_tmpl>. We will prepend the L<Para::Frame::Site/home>
part.

This is done because we may change site that displays the error page.
That also means that the site changed to, must find that template.

=cut


#######################################################################

sub set_error_template
{
    my( $page, $error_tt ) = @_;

    # $page->{'error_template'} holds the resolved template, inkluding
    # the $home prefix

    debug 2, "Setting error template to $error_tt";

    # We want to set the error in the original request
    if( my $req = $page->req->original )
    {
	if( $req->page ne $page )
	{
	    debug "Calling original req set_error_template";
	    return $req->page->set_error_template($error_tt);
	}
	debug "The original request had the same page obj";
    }

    # TODO:
    # We may have to set a "target_template" for remembering what
    # template the error template is talking about

    my $home = $page->site->home_url_path;
    return $page->{'error_template'} =
      $page->set_template( $home . $error_tt );
}


#######################################################################

=head2 ctype

  $p->ctype

  $p->ctype( $content_type )

Returns the content type to use in the http response, in the form
of a L<Para::Frame::Request::Ctype> object.

If C<$content_type> is defiend, sets the content type using
L<Para::Frame::Request::Ctype/set>.

=cut

sub ctype
{
    my( $page, $content_type ) = @_;

    # Needs $REQ

    unless( $page->{'ctype'} )
    {
	$page->{'ctype'} = Para::Frame::Request::Ctype->new($page->req);
    }

    if( $content_type )
    {
	$page->{'ctype'}->set( $content_type );
    }

    return $page->{'ctype'};
}


#######################################################################

=head2 redirect

  $p->redirect( $url )

  $p->redirect( $url, $permanently_flag )

This is for redirecting to a page not handled by the paraframe.

The actual redirection will be done then all the jobs are
finished. Error in the jobs could result in a redirection to an
error page instead.

The C<$url> should be a full url string starting with C<http:> or
C<https:> or just the path under the curent host.

If C<$permanently_flag> is true, sets the http header for indicating
that the requested page permanently hase moved to this page.

For redirection to a TT page handled by the same paraframe daemon, use
L</set_template>.

=cut

sub redirect
{
    my( $page, $url, $permanently ) = @_;

   $page->{'moved_temporarily'} ||= 1 unless $permanently;

    $page->{'redirect'} = $url;
}


#######################################################################

=head2 set_http_status

  $p->set_http_status( $status )

Used internally by L</render_output> for sending the http_status of
the response page to the client.

=cut

sub set_http_status
{
    my( $page, $status ) = @_;
    return 0 if $status < 100;
    return $page->req->send_code( 'AR-PUT', 'status', $status );
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
    my( $page ) = @_;

    unless( $page->incpath )
    {
	my $burner = $page->burner
	  or confess "Page burner not set";
	my $type = $burner->{'type'};

	my $site = $page->site;


 	my $path_full = $page->dirsteps->[0];
	my $destroot = $site->home->sys_path;
	my $dir = $path_full;
	unless( $dir =~ s/^$destroot// )
	{
	    warn "destroot $destroot not part of $dir";
	    warn Dumper $page->dirsteps;
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


	$page->set_incpath([ @searchpath ]);


	if( debug > 2 )
	{
	    my $incpathstring = join "", map "- $_\n", @{$page->incpath};
	    debug "Include path:";
	    debug $incpathstring;
	}

    }

    return $page->incpath;
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
an L</error_page_selected> in which case we set it to
L</orig_url_path>. (For making it easier to link back to the intended
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
    my( $page ) = @_;

    my $req = $page->req;
    my $site = $page->site;
    my $me = $page->url_path_slash;
    if( $page->error_page_selected )
    {
	$me = $page->orig_url_path;
    }

    # Keep alredy defined params  # Static within a request
    $page->add_params({
	'page'            => $page,

	'me'              => $me,

	'u'               => $Para::Frame::U,
	'lang'            => $req->language->preferred, # calculate once
	'req'             => $req,

	# Is allowed to change between requests
	'site'            => $site,
	'home'            => $site->home_url_path,
    });

    if( $req->{'q'} )
    {
	$page->add_params({
			   'q'               => $req->{'q'},
			   'ENV'             => $req->env,
			  });
    }

    # Add local site params
    if( $site->params )
    {
	$page->add_params($site->params);
    }

}

#######################################################################

=head1 Private methods

=cut

#######################################################################

=head2 find_template

  $page->find_template( $path_slash )

  $page->find_template( $path_slash, $params )

params:

C<create_missing_dirs>: if true, creates missing dirs in the
filesystem up to the part there the file would have been.

Returns:

C<($doc, $ext)> where $doc is a L<Template::Document> objetct
that can be parsed to a L<Para::Frame::Burner> object.

=cut

sub find_template
{
    my( $page, $template, $params ) = @_;
    my $req = $page->req;

    $params ||= {};

#    debug("find_template $template with ".datadump($params,1));
    my( $in );

    my $site = $page->site;
#    debug("The site is".Dumper($site));


    my( $base_name, $dir_path_slash, $ext_full )
      = fileparse( $template, qr{\..*} );

    if( debug > 3 )
    {
	debug(0,"path: $dir_path_slash");
	debug(0,"name: $base_name");
	debug(0,"ext : $ext_full");
	cluck unless $ext_full;
    }

    # Reasonable default?
    my $language = $req->language->alternatives || ['en'];

    # We should not try to find templates including lang
    if( $ext_full =~ /^\.(\w\w)\.tt$/ )
    {
	debug 2, "Trying to get template with specific lang ext";
	$language = [$1];
	$ext_full = '.tt';
    }

    my( $ext ) = $ext_full =~ m/^\.(.+)/; # Skip initial dot

    # Not absolute path?
    if( $template !~ /^\// )
    {
	cluck "not implemented ($template)";
	$template = '/'.$template;
    }

    # Also used by &Para::Frame::Burner::paths
    my $dir_sys_path;
    if( $params->{'create_missing_dirs'} )
    {
#	debug "  Creating missing dirs";
	$dir_sys_path = $req->uri2file_create( $dir_path_slash );
    }
    else
    {
#	debug "  NOT creating missing dirs";
	$dir_sys_path = $req->uri2file( $dir_path_slash );
    }

#    debug "Dir sys path is $dir_sys_path";
    $page->set_dirsteps( $dir_sys_path . '/' );

    my @searchpath = $dir_sys_path . '/';

    if( $site->is_compiled )
    {
	push @searchpath, map $_."def/", @{$page->{'dirsteps'}};
    }
    else
    {
	my $destroot = $site->home->sys_path;
	my $dir = $dir_sys_path;
	debug 4, "destroot: $destroot";
	debug 4, "dir(pre): $dir";

	$dir =~ s/^$destroot// or
	  die "destroot $destroot not part of $dir";

	my $paraframedir = $Para::Frame::CFG->{'paraframe'};

	foreach my $appback (@{$site->appback})
	{
	    push @searchpath, $appback . '/html' . $dir . '/';
	}

	push @searchpath, $paraframedir . '/html' . $dir . '/';

	foreach my $path ( Para::Frame::Utils::dirsteps($dir.'/'), '/' )
	{
	    push @searchpath, $destroot . $path . "def/";
	    foreach my $appback (@{$site->appback})
	    {
		push @searchpath, $appback . '/heml' . $path . "def/";
	    }
	    push @searchpath,  $paraframedir . '/html' . $path . "def/";
	}
    }

    if( debug > 3 )
    {
	my  $searchstr = join "", map " - $_\n", @searchpath;
	debug "Looking for template in:";
	debug $searchstr;
    }

    debug(4,"Check ".($ext||'<no ext>'),1);
    foreach my $path ( @searchpath )
    {
	unless( $path )
	{
	    cluck "path undef (@searchpath)";
	    next;
	}

	# We look for both tt and html regardless of it the file was called as .html
	debug(3,"Check $path",1);
	die "dir_redirect failed" unless $base_name;

	# Handle dirs
	if( -d $path.$base_name.$ext_full )
	{
	    confess "Found a directory: $path$base_name$ext_full\nShould redirect";
	}


	# Find language specific template
	foreach my $lang ( map(".$_",@$language),'' )
	{
	    debug(4,"Check $lang");
	    my $filename = $path.$base_name.$lang.$ext_full;
	    if( -r $filename )
	    {
		debug(3,"Using $filename");

		# Static file
		if( $ext ne 'tt' )
		{
		    debug(3,"As STATIC ($ext)");
		    debug(-2);
		    return( $filename, $ext );
		}

		my $mod_time = stat( $filename )->mtime;
		my $burner = $page->set_burner_by_type('html');
		my $compdir = $burner->compile_dir;
		my $compfile = $compdir.$filename;
		debug 4, "Compdir: $compdir";

		my( $data, $ltime);

		# 1. Look in memory cache
		#
		if( my $rec = $Para::Frame::Cache::td{$filename} )
		{
		    debug(3,"Found in MEMORY");
		    ( $data, $ltime) = @$rec;
		    if( $ltime <= $mod_time )
		    {
			if( debug > 3 )
			{
			    debug(0,"     To old!");
			    debug(0,"     ltime: $ltime");
			    debug(0,"  mod_time: $mod_time");
			}
			undef $data;
		    }
		}

		# 2. Look for compiled file
		#
		unless( $data )
		{
		    if( -f $compfile )
		    {
			debug(3,"Found in COMPILED file");

			my $ltime = stat($compfile)->mtime;
			if( $ltime <= $mod_time )
			{
			    if( debug > 3 )
			    {
				debug(0,"     To old!");
				debug(0,"     ltime: $ltime");
				debug(0,"  mod_time: $mod_time");
			    }
			}
			else
			{
			    $data = $page->load_compiled( $compfile );

			    debug(3,"Loading $compfile");

			    # Save to memory cache (loadtime)
			    $Para::Frame::Cache::td{$filename} =
				[$data, $ltime];
			}
		    }
		}

		# 3. Compile the template
		#
		unless( $data )
		{
		    eval
		    {
			debug(3,"Reading file");
			$mod_time = time; # The new time of reading file
			my $filetext = read_file( $filename );
			my $parser = $burner->parser;

			debug(3,"Parsing");
			$req->note("Compiling $template");
			my $metadata =
			{
			 name => $filename,
			 time => $mod_time,
			};
			my $parsedoc = $parser->parse( $filetext, $metadata )
			    or throw('template', "parse error:\nFile: $filename\n".
				     $parser->error);

#			$parsedoc->{ METADATA }{'name'} = $filename;
#			$parsedoc->{ METADATA }{'modtime'} = $mod_time;

			debug(3,"Writing compiled file");
			create_dir(dirname $compfile);
			Template::Document->write_perl_file($compfile, $parsedoc);
			chmod_file($compfile);
			utime( $mod_time, $mod_time, $compfile );

			$data = Template::Document->new($parsedoc)
			    or throw('template', $Template::Document::ERROR);

			# Save to memory cache
			$Para::Frame::Cache::td{$filename} =
			    [$data, $mod_time];
			1;
		    } or do
		    {
			debug(2,"Error while compiling template $filename: $@");
			# FIXME
			$req->result->exception;
			if( $template eq $site->home_url_path.'/error.tt' )
			{
			    $page->{'error_template'} = $template;
			    $page->{'page_content'} = $page->fallback_error_page;
			    return undef;
			}
			debug(2,"Using /error.tt");
			($in) = $page->find_template($site->home_url_path.'/error.tt');
			debug(-2);
			return( $in, 'tt' );
		    }
		}

		debug(-2);
		return( $data, $ext );
	    }
	}
	debug(-1);
    }
    debug(-1);

    # Check if site should be compiled but hasn't been yet
    #
    if( $site->is_compiled )
    {
	my $lang = $language->[0];
	my $sample_template = $site->home_url_path . "/def/page_not_found.$lang.tt";
	unless( stat($req->uri2file($sample_template)) )
	{
	    $site->set_is_compiled(0);
	    debug "*** The site is not yet compiled";
	    my( $data, $ext ) = $page->find_template( $template );

#	    $site->set_is_compiled(1);

	    return( $data, $ext );
	}
    }


    # If we can't find the filname
    debug(1,"Not found: $template");
    return( undef );
}


#######################################################################

=head2 fallback_error_page

  $p->fallback_error_page

Returns a scalar ref with HTML to use if the normal error response
templates did not work.

=cut

sub fallback_error_page
{
    my( $page ) = @_;

    my $out = "";
    $out .= "<p>500: Failure to render failure page\n";
    $out .= "<pre>\n";
    $out .= $page->req->result->as_string;
    $out .= "</pre>\n";
    if( my $backup = $page->site->backup_host )
    {
	my $path = $page->url->path;
	$out .= "<p>Try to get the page from  <a href=\"http://$backup$path\">$backup</a> instead</p>\n"
	}
    return \$out;
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
    my( $page ) = @_;

    my $req = $page->req;

    ### Output page
    my $client = $req->client;
    my $template = $page->url_path_tmpl;
    my $out = "";

    my $site = $page->site;
    my $home = $site->home_url_path;

    $req->note("Rendering page");
#    debug "For req ".$req->id;
#    cluck datadump($page,1); ### DEBUG

    my( $in, $ext ) = $page->find_template( $template );

    # Setting tt params AFTER template was found
    $page->set_tt_params;

    if( not $in )
    {
	# Maby we have a fallback page generated
	return 1 if $page->{'page_content'};
    }

    if( not $in )
    {
	( $in, $ext ) = $page->find_template( $home.'/page_not_found.tt' );
	$page->set_http_status(404);
	$req->result->error('notfound', "Hittar inte sidan $template\n");
    }

    debug 2, "Template to render is $in ($ext)";

    if( not $in )
    {
	$out .= ( "<p>404: Not found\n" );
	$out .= ( "<p>Failed to find the file not found error page!\n" );
	$page->{'page_content'} = \$out;
	return 1;
    }

    # Don't burn if this is a HEAD request
    return 1 if $req->header_only;


    my $burner = Para::Frame::Burner->get_by_ext($ext);

    if( not $burner )
    {
	debug "Getting '$in' as a static page";
	$page->get_static( $in, \$out );
	$page->{'page_content'} = \$out;
	return 1;
    }
    else
    {
	$page->{'burner'} = $burner;
	$page->burn($in, \$out)
	  or do
	{

	    debug(0,"FALLBACK!");
	    my $part = $req->result->exception();
	    my $error = $part->error;

	    if( $part->view_context )
	    {
		$part->prefix_message(loc("During the processing of [_1]",$template)."\n");
	    }



	    ### Use error page template
	    # $error_tt and $new_error_tt EXCLUDES $home
	    #
	    my $error_tt = $page->url_path_tmpl; # Could have changed
	    $error_tt =~ s/^$home//; # Removes the $home prefix
	    my $new_error_tt;

	    if( $home.$error_tt eq $template ) # No new template specified
	    {
		if( $error->type eq 'file' )
		{
		    if( $error->info =~ /not found/ )
		    {
			debug "Subtemplate not found";
			$new_error_tt = $error_tt = '/page_part_not_found.tt';
			my $incpathstring = join "", map "- $_\n", @{$page->incpath};
			$part->add_message(loc("Include path is")."\n$incpathstring");
			$part->view_context(1);
			$part->prefix_message(loc("During the processing of [_1]",$template)."\n");
		    }
		    else
		    {
			debug "Other template file error";
			$part->type('template');
			$new_error_tt = $error_tt = '/error.tt';
		    }
		    debug $error->as_string();
		}
		elsif( $error->type eq 'denied' )
		{
		    if( $req->session->u->level == 0 )
		    {
			# Ask to log in
			$new_error_tt = $error_tt = "/login.tt";
			$req->result->hide_part('denied');
			unless( $req->{'no_bookmark_on_failed_login'} )
			{
			    $req->session->route->bookmark();
			}
		    }
		    else
		    {
			$new_error_tt = $error_tt = "/denied.tt";
			$req->session->route->plan_next($req->referer);
		    }
		}
		elsif( $error->type eq 'notfound' )
		{
		    $new_error_tt = $error_tt = "/page_not_found.tt";
		    $page->set_http_status(404);
		}
		elsif( $error->type eq 'cancel' )
		{
		    throw('cancel', "request cancelled");
		}
		else
		{
		    $new_error_tt = $error_tt = '/error.tt';
		}
	    }

	    debug(1,$burner->error());

	    # Avoid recursive failure
	    if( ($template eq $home.$error_tt) and $new_error_tt )
	    {
		$page->{'page_content'} = $page->fallback_error_page;
		return 1;
	    }

	    # The template generating this error may not ge the
	    # original URL

	    # But that template url will be forgotten if we overwrite
	    # it with the error template.

	    $page->set_error_template( $error_tt );
	    return 0;
	};
    }

#	warn Dumper $req->result;

    if( debug > 3 )
    {
	my $length = length($out);
	warn "Page with length $length placed in $req";
    }
    $page->{'page_content'} = \$out;

    return 1;
}



#######################################################################

=head2 send_output

  $p->send_output

Sends the previously generated page to the client.

If the URL should change, sends a redirection header and stores the
generated page in the session to be sent as a response to the future
request to for the new URL.

Sends the headers followd by the page content.

If the content is in UTF8, sends the page in UTF8.

For large pages, sends the page in chunks.

=cut

sub send_output
{
    my( $page ) = @_;

    my $req = $page->req;

    # Forward if URL differs from url_path

    if( debug > 2 )
    {
	debug(0,"Sending output to ".$page->orig_url_path);
	debug(0,"Sending the page ".$page->url_path);
	unless( $page->error_page_not_selected )
	{
	    debug(0,"An error page was selected");
	}
    }


    # forward if requested url ends in '/index.tt' or if it is a dir
    # without an ending '/'

    my $url = $page->orig_url_path;
    my $url_norm = $req->normalized_url( $url );

#    debug "Original url: $url";

    if( $url ne $url_norm )
    {
	debug "!!! $url ne $url_norm";
	$page->forward($url_norm);
    }
    elsif( $page->error_page_not_selected and
	$url ne $page->url_path_slash )
    {
	debug "!!! $url ne ".$page->url_path_slash;
	$page->forward();
    }
    else
    {
	my $sender = $page->sender;

	if( $req->header_only )
	{
	    my $res;
	    if( $req->in_loadpage )
	    {
		$res = "LOADPAGE";
	    }
	    else
	    {
		$page->send_headers;
		$res = $req->get_cmd_val( 'HEADER' );
	    }
	    if( $res eq 'LOADPAGE' )
	    {
		$req->session->register_result_page($page->url_path_slash, $page->{'headers'}, $page->{'page_content'}, $sender);
		$req->send_code('PAGE_READY', $page->url->as_string);
	    }
	}
	elsif( $sender eq 'utf8' )
	{
	    my $res;
	    if( $req->in_loadpage )
	    {
		$res = "LOADPAGE";
	    }
	    else
	    {
		$page->ctype->set_charset("utf-8");
		$page->send_headers;
		$res = $req->get_cmd_val( 'BODY' );
	    }
	    if( $res eq 'LOADPAGE' )
	    {
		$req->session->register_result_page($page->url_path_slash, $page->{'headers'}, $page->{'page_content'}, $sender);
		$req->send_code('PAGE_READY', $page->url->as_string);
	    }
	    elsif( $res eq 'SEND' )
	    {
		binmode( $req->client, ':utf8');
		debug(4,"Transmitting in utf8 mode");
		$page->send_in_chunks( $page->{'page_content'} );
		binmode( $req->client, ':bytes');
	    }
	    else
	    {
		die "Strange response '$res'";
	    }
	}
	else # Default
	{
	    my $res;
	    if( $req->in_loadpage )
	    {
		$res = "LOADPAGE";
	    }
	    else
	    {
		$page->send_headers;
		$res = $req->get_cmd_val( 'BODY' );
	    }
	    if( $res eq 'LOADPAGE' )
	    {
		$req->session->register_result_page($page->url_path_slash, $page->{'headers'}, $page->{'page_content'}, $sender );
		$req->send_code('PAGE_READY', $page->url->as_string);
	    }
	    elsif( $res eq 'SEND' )
	    {
		$page->send_in_chunks( $page->{'page_content'} );
	    }
	    else
	    {
		die "Strange response '$res'";
	    }
	}
    }
#    debug "send_output: done";
}

#######################################################################

=head2 sender

  $p->sender

  $p->sender( $code )

=cut

sub sender
{
    my( $page, $code ) = @_;

    if( $code )
    {
	unless( $code =~ /^(utf8|bytes)$/ )
	{
	    confess "Page sender $code not recogized";
	}
	$page->{'page_sender'} = $code;
    }
    elsif( not $page->{'page_sender'} )
    {
	if( is_utf8  ${ $page->{'page_content'} } )
	{
	    $page->{'page_sender'} = 'utf8';
	}
	else
	{
	    $page->{'page_sender'} = 'bytes';
	}
    }
    return $page->{'page_sender'};
}


#######################################################################

=head2 forward

  $p->forward( $url )

Should only be called AFTER the page has been generated. It's used by
L</send_output> and should not be used by others.

C<$url> must be a normalized url path

To request a forward, just use L</set_template> before the page is
generated.

To forward to a page not handled by the paraframe, use L</redirect>.

=cut

sub forward
{
    my( $page, $url_norm ) = @_;
    my $req = $page->req;

    my $site = $page->site;

    $url_norm ||= $page->url_path_slash;


    debug "Forwarding to $url_norm";

    if( not( $page->{'page_content'} or $req->header_only ) )
    {
	cluck "forward() called without a generated page";
	unless( $url_norm =~ /\.html$/ )
	{
	    $url_norm = $site->home_url_path."/error.tt";
	}
    }
    elsif( $url_norm =~ /\.html$/ )
    {
	debug "Forward to html page: $url_norm";
	my $referer = $req->referer;
	debug "  Referer is $referer";
	debug "  Cancelling forwarding";
	$page->{url_norm} = $page->orig_url_path;
	$page->{sys_name} = undef;
	$page->send_output;
	return;
    }

    $page->output_redirection($url_norm );

    $req->session->register_result_page($url_norm, $page->{'headers'}, $page->{'page_content'}, $page->sender);
}


#######################################################################

=head2 output_redirection

  $p->output_redirection( $url )

Internally used by L</forward> for sending redirection headers to the
client.

=cut

sub output_redirection
{
    my( $page, $url_in ) = @_;
    my $req = $page->req;

    $url_in or die "URL missing";

    # Default to temporary move.

    my $url_out;

    # URL module doesn't support punycode. Bypass module if we
    # redirect to specified domain
    #
    if( $url_in =~ /^ https?:\/\/ (.*?) (: | \/ | $ ) /x )
    {
	my $host_in = $1;
#	warn "  matched '$host_in' in '$url_in'!\n";
	my $host_out = idn_encode( $host_in );
#	warn "  Encoded to '$host_out'\n";
	if( $host_in ne $host_out )
	{
	    $url_in =~ s/$host_in/$host_out/;
	}

	$url_out = $url_in;
    }
    else
    {
	my $url = Para::Frame::URI->new($url_in, 'http');
	$url->host( idn_encode $req->http_host ) unless $url->host;
	$url->port( $req->http_port ) unless $url->port;
	$url->scheme('http');

	$url_out =  $url->canonical->as_string;
    }

    debug(2,"--> Redirect to $url_out");

    my $moved_permanently = $page->{'moved_temporarily'} ? 0 : 1;


    my $res = $req->get_cmd_val( 'WAIT' );
    if( $res eq 'LOADPAGE' )
    {
	$req->send_code('PAGE_READY', $url_out );
	return;
    }

    if( $moved_permanently )
    {
	debug "MOVED PERMANENTLY";
	$req->send_code( 'AR-PUT', 'status', 301 );
	$req->send_code( 'AR-PUT', 'header_out', 'Cache-Control', 'public' );
    }
    else # moved temporarily
    {
	$req->send_code( 'AR-PUT', 'status', 302 );
	$req->send_code( 'AR-PUT', 'header_out', 'Pragma', 'no-cache' );
	$req->send_code( 'AR-PUT', 'header_out', 'Cache-Control', 'no-cache' );
    }
    $req->send_code( 'AR-PUT', 'header_out', 'Location', $url_out );

    my $out = "Go to $url_out\n";
    my $length = length( $out );

    $req->send_code( 'AR-PUT', 'send_http_header', 'text/plain' );

    if( $req->header_only )
    {
	$req->send_code( 'HEADER' );
    }
    else
    {
	$req->send_code( 'AR-PUT', 'header_out', 'Content-Length', $length );
	$req->send_code( 'BODY' );
	$req->client->send( $out );
    }
}


#######################################################################

=head2 send_headers

  $p->send_headers()

Used internally by L</send_output> for sending the HTTP headers to the
client.

=cut

sub send_headers
{
    my( $page ) = @_;

    my $req = $page->req;

    my $client = $req->client;

    $req->lang->set_headers;               # lang

    if( my $last_modified = $page->last_modified )
    {
	$page->set_header('Last-Modified' => $last_modified->internet_date);
    }

    $page->ctype->commit;

    my %multiple; # Replace first, but add later headers
    foreach my $header ( $page->headers )
    {
	if( $multiple{$header->[0]} ++ )
	{
	    debug(3,"Send header add @$header");
	    $req->send_code( 'AT-PUT', 'add', @$header);
	}
	else
	{
	    debug(3,"Send header_out @$header");
	    $req->send_code( 'AR-PUT', 'header_out', @$header);
	}
    }
}


#######################################################################

=head2 send_in_chunks

  $p->send_in_chunks( $dataref )

Used internally by L</send_output> for sending the page in C<$dataref>
to the client.

It will try many times sending part by part. If a part failed to be
sent, it will check if the connection has been canceled. It will also
wait about a second for the client to recover, by doing a
L<Para::Frame::Request/yield>.

Returns: The number of characters sent. (That may be UTF8 characters.)

=cut

sub send_in_chunks
{
    my( $page, $dataref ) = @_;

    my $req = $page->req;

    my $client = $req->client;
    my $length = length($$dataref);
    debug(4,"Sending ".length($$dataref)." bytes of data to client");
#    debug(1, "Sending ".length($$dataref)." bytes of data to client");
    my $sent = 0;
    my $errcnt = 0;

    unless( $length )
    {
	debug "We got nothing to send (for req $req)";
	return 1;
    }

    eval
    {
	if( $length > 64000 )
	{
	    my $chunk = 16384; # POSIX::BUFSIZ * 2
	    for( my $i=0; $i<$length; $i+= $chunk )
	    {
		debug(4,"  Transmitting chunk from $i\n");
		my $res = $client->send( substr $$dataref, $i, $chunk );
		if( $res )
		{
		    $sent += $res;
		    $errcnt = 0;
		}
		else
		{
		    debug(1,"  Failed to send chunk $i");

		    if( $req->cancelled )
		    {
			debug("Request was cancelled. Giving up");
			return $sent;
		    }

		    debug(1,"  Tries to recover...",1);

		    $errcnt++;
		    $req->yield( 0.9 );

		    if( $errcnt >= 100 )
		    {
			debug(0,"Got over 100 failures to send chunk $i");
			last;
		    }
		    debug(-1);
		    redo;
		}
	    }
	}
	else
	{
	    while(1)
	    {
		$sent = $client->send( $$dataref );
		if( $sent )
		{
		    last;
		}
		else
		{
		    debug("  Failed to send data to client\n  Tries to recover...",1);

		    $errcnt++;
		    $req->yield( 1.2 );

		    if( $errcnt >= 10 )
		    {
			debug(0,"Got over 10 failures to send $length chars of data");
			last;
		    }
		    debug(-1);
		    redo;
		}
	    }
	}
	debug(4, "Transmitted $sent chars to client");
    };
    if( $@ )
    {
	my $err = catch($@);
	unless( $Para::Frame::REQUEST{$client} )
	{
	    return 0;
	}

	debug "Faild to transmit to client";
	debug $err->as_string;
	return 0;
    }

    return $sent;
}



#######################################################################

sub send_stored_result
{
    my( $page, $page_result ) = @_;

    my $req = $Para::Frame::REQ;
    $page_result ||=
      $req->session->{'page_result'}{ $page->orig_url_path };

    debug 0, "Sending stored page result";
    $page->set_headers( $page_result->[0] );
    if( length ${$page_result->[1]} ) # May be header only
    {
	if( $page_result->[2] eq 'utf8' )
	{
	    debug 4, "  in UTF8";
	    $page->ctype->set_charset("utf-8");
	    $page->send_headers;
	    my $res = $req->get_cmd_val( 'BODY' );
	    if( $res eq 'LOADPAGE' )
	    {
		die "Was to slow to send the pregenerated page";
	    }
	    else
	    {
		binmode( $req->client, ':utf8');
		debug(4,"Transmitting in utf8 mode");
		$page->send_in_chunks( $page_result->[1] );
		binmode( $req->client, ':bytes');
	    }
	}
	else
	{
	    debug 4, "  in Latin-1";
	    $page->send_headers;
	    my $res = $req->get_cmd_val( 'BODY' );
	    if( $res eq 'LOADPAGE' )
	    {
		die "Was to slow to send the pregenerated page";
	    }
	    else
	    {
		$page->send_in_chunks( $page_result->[1] );
	    }
	}
    }
    else
    {
	debug 4, "  as HEADER";
	$page->send_headers;
	my $res = $req->get_cmd_val( 'HEADER' );
	if( $res eq 'LOADPAGE' )
	{
	    die "Was to slow to send the pregenerated page";
	};
    }

    delete $req->session->{'page_result'}{ $req->page->orig_url_path };

    #debug "Sending stored page result: done";
}


#######################################################################

=head2 last_modified

  $p->last_modified()

This method should return the last modification date of the page in
its rendered form.

This function currently only works for CSS pages.

For other pages, returns undef

=cut

sub last_modified
{
    my( $page ) = @_;

    if( $page->ctype->is('text/css') )
    {
	my $updated = $page->site->css->updated;
#	debug "CSS updated $updated";
	my $page_updated = $page->mtime;
#	debug "CSS template updated $page_updated";
	if( $page_updated > $updated )
	{
	    $updated = $page_updated;
	}
	return $updated;
    }

    return undef;
}


#######################################################################

=head2 send_not_modified

  $p->send_not_modified()


Just as send_output, but sends a header saying that the requested page
has not been modified.

=cut

sub send_not_modified
{
    my( $page ) = @_;

    debug "Not modified";
    $page->set_http_status(304);
    $page->req->set_header_only(1);
    $page->send_output;

    return 1;
}


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
