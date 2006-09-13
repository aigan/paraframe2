#  $Id$  -*-cperl-*-
package Para::Frame::Page;
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

Para::Frame::Page - Represents the response page for a req

=head1 DESCRIPTION

Represents a page on a site with a specific URL.

Inherits from L<Para::Frame::File>

This is the superclass of <Para::Frame::Site::Page>.

During lookup or generation of the page, the URL of the page can
change. We differ between the original requested URL, the resulting
URL and an URL for the template used.

A L<Para::Frame::Request> will create a L<Para::Frame::Page> object
representing the response page.

A request can also create other Page objects for representing other
pages for getting information about them or for generating pages for
later use, maby not specificly copupled to the current request or
session.

The distinction between Para::Frame::Request and Para::Frame::Page are
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

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch );
use Para::Frame::Request::Ctype;
use Para::Frame::URI;
use Para::Frame::L10N qw( loc );
use Para::Frame::Dir;
use Para::Frame::Time qw( now );


#######################################################################

=head1 Constructors

=cut

#######################################################################

=head2 new

  Para::Frame::Page->new( \%args )

Creates a Page object.

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;
    die "DEPRECATED" unless ref $args eq 'HASH';

    if( $class eq 'Para::Frame::Page' )
    {
	croak "class should be Site or Nonsite";
    }

    $args ||= {};

    my $page = bless
    {
     orig_url_name  => undef, ## prev url_name
     orig           => undef, ## a File obj for the orig url
     tmpl_url_name  => undef, ## prev template
     url_name       => undef, ## prev template_url
     url_norm       => undef, ## ends in slash for dirs

     error_template => undef,          ## if diffrent from template


     headers        => [],             ## Headers to be sent to the client
     moved_temporarily => 0,           ## ... or permanently?
     redirect       => undef,          ## ... to other server
     ctype          => undef,          ## The response content-type
     page_content   => undef,          ## Ref to the generated page
     page_sender    => undef,          ## The mode of sending the page
     incpath        => undef,
     dirsteps       => undef,
     params         => undef,
     renderer       => undef,
     site           => undef,          ## The site for the request
     req            => undef,
     dir            => undef,          ## Cached Para::Frame::Dir obj
     initiated      => 0,              ## Initiating file info
     sys_name       => undef,          ## Cached sys path
     burner         => undef,          ## burner used for page
    }, $class;

    $page->{'params'} = {%$Para::Frame::PARAMS};

    if( my $req = $args->{req} )
    {
	$page->{req} = $req;
	weaken( $page->{'req'} );
    }

    if( my $ctype = $args->{ctype} )
    {
	$page->ctype( $ctype );
    }


    if( $args->{url} )
    {
	if( $args->{'filename'} )
	{
	    die "Don't specify filename with url";
	}
    }
    elsif( my $filename = $args->{'filename'} )
    {
	-r $filename or die "Can't read $filename: $!";
	$page->{'sys_name'} = $filename;
    }
    else
    {
	die "Filename missing";
    }

    return $page;
}


#######################################################################

=head1 Accessors

See L<Para::Frame::File/Accessors>

=cut


#######################################################################


=head2 is_index

True if this is a C</index.tt>

=cut

sub is_index
{
    die "not implemented";
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

=head2 template

  $p->template()

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
    die "not implemented";
    my( $page ) = @_;

    my( $tmpl ) = $page->find_template( $page->url_path_tmpl );

    return $tmpl;
}

#######################################################################

=head2 title

  $p->title()

Returns the L</template> C<otitle> or L<title> or in the last case
just the L<Para::Frame::File/name>.

=cut

sub title
{
    my( $page ) = @_;

    my $tmpl = $page->template;

    return $tmpl->otitle || $tmpl->title || $page->name;
}

#######################################################################

=head2 is_page

  $p->is_page()

Returns: true

=cut

sub is_page
{
    return 1;
}

#######################################################################

=head2 renderer

  $p->renderer

Returns: the renderer to be used, if not the standard renderer

=cut

sub renderer
{
    return $_[0]->{'renderer'};
}


#######################################################################

=head1 Public methods

=cut

#######################################################################

=head2 add_params

  $p->add_params( \%params )

  $p->add_params( \%params, $keep_old_flag )

Adds template params. This can be variabls, objects, functions.

If C<$keep_old_flag> is true, we will not replace existing params with
the same name.

=cut

sub add_params
{
    my( $page, $extra, $keep_old ) = @_;

    my $param = $page->{'params'};

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
	    debug(4,"Add TT param $key: $val");
	}
     }
}

#######################################################################


=head2 precompile

  $page->precompile( \%args )

Send same args as for L</new> for creating the new page from thre
source C<$page>. Also takes:

  arg type defaults to html_pre
  arg language defaults to undef

Returns: The new compiled page

=cut

sub precompile
{
    my( $page, $args ) = @_;

    my $req = $page->req;

    $args ||= {};

    my $srcfile = $page->sys_path;
    my $page_dest = Para::Frame::Site::Page->new($args);

    my( $res, $error );

    my $type = $args->{'type'} || 'html_pre';

    my $filename = $page_dest->orig->name;

    my $destfile = $page_dest->orig->sys_path;
#    debug "Compiling from $srcfile -> $destfile";

    my $safecnt = 0;
    while( $destfile !~ /$filename$/ )
    {
	debug "$destfile doesn't end with $filename";
	# TODO: Make this into a method
	die "Loop" if $safecnt++ > 100;
	debug "Creating dir $destfile";
	create_dir($destfile);
	$page_dest->{'sys_name'} = undef;
	$page_dest->{'orig'} = undef;
	$req->uri2file_clear( $page_dest->orig->url_path );
	$destfile = $page_dest->orig->sys_path;
    }

    my $dir = $page_dest->dir;

    if( debug > 1 )
    {
	debug "srcfile     : $srcfile";
	debug "destfile_web: ".$page_dest->orig->url_path_slash;
	debug "destfile    : $destfile";
	debug "destdir     : ".$dir->sys_path;
	debug "type        : $type";
    }


    $page_dest->set_dirsteps( $dir->sys_path_slash );



    my $fh = new IO::File;
    $fh->open( "$srcfile" ) or die "Failed to open '$srcfile': $!\n";
    $page_dest->add_params({
			    pf_source_file => $srcfile,
			    pf_compiled_date => now->iso8601,
			    pf_source_version => $page->vcs_version(),
			   });

    $page_dest->set_tt_params;

    $page_dest->set_burner_by_type($type);
    $res = $page_dest->burn( $fh, $destfile );
    $fh->close;
    $error = $page_dest->burner->error unless $res;

    if( $error )
    {
	debug "ERROR WHILE PRECOMPILING PAGE";
	debug 0, $error;
	my $part = $req->result->exception($error);
	if( ref $error and $error->info =~ /not found/ )
	{
	    debug "Subtemplate for precompile not found";
	    my $incpathstring = join "", map "- $_\n",
		@{$page_dest->incpath};
	    $part->add_message("Include path is\n$incpathstring");
	}

	die $part;
    }

    return $page_dest;
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
    die "not implemented";
    my( $page ) = @_;

    unless( $page->incpath )
    {
	my $burner = $page->burner
	  or confess "Page burner not set";
	my $type = $burner->{'type'};

	my $site = $page->site;
	my $subdir = 'inc' . $burner->subdir_suffix;

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
	my $backdir = $site->is_compiled ? '/dev' : '/html';

	debug 3, "Creating incpath for $dir with $backdir under $destroot ($type)";

	my @searchpath;

	foreach my $step ( Para::Frame::Utils::dirsteps($dir), '/' )
	{
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


=head2 set_renderer

  $p->set_renderer( \&renderer )

Sets the code to run for rendering the page, if not the standard
renderer.

Example renderer:

  my $render_hello = sub
  {
      my( $req ) = @_;
      my $p = $req->page;
      $p->ctype("text/html");
      my $out = "<h1>Hello world!</h1>";
      $p->set_content(\$out);
      return 1;
  };
  $p->set_renderer($render_hello);

Returns: L</renderer>

=cut

sub set_renderer
{
    return $_[0]->{'renderer'} = $_[1] || undef;
}


#######################################################################

=head2 set_content

  $p->set_content( \$content )

Sets the page to be returned to the client.

If you want an action to returns a special type of page, it should use
L</set_renderer> since that renderer is called after all actions been
sorted out.

But you could set the response page directly in the action by calling
this method.

Returns: The reference to the content, stored in the page object.

=cut

sub set_content
{
    my( $page, $content_ref ) = @_;

    $page->{'page_content'} = $content_ref;
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
    die "not implemented";
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

=head2 burner

  $p->burner

Returns: the L<Para::Frame::Burner> selected for this page

=cut

sub burner
{
    return $_[0]->{'burner'} or confess "No burner set";
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
    my( $page, $in, $out ) = @_;
    return $_[0]->{'burner'}->burn($in, $page->{'params'}, $out );
}

#######################################################################

=head2 find_template

  returns ($doc, $ext) where $doc is a L<Template::Document> objetct
that can be parsed to a L<Para::Frame::Burner> object.

=cut

sub find_template
{
    die "not implemented";
    my( $page, $template ) = @_;
    my $req = $page->req;

    debug(2,"Finding template $template");
    my( $in );

    my $site = $page->site;
#    debug("The site is".Dumper($site));


    my( $base_name, $path_full, $ext_full ) = fileparse( $template, qr{\..*} );

    if( debug > 3 )
    {
	debug(0,"path: $path_full");
	debug(0,"name: $base_name");
	debug(0,"ext : $ext_full");
	cluck unless $ext_full;
    }

    # Reasonable default?
    my $language = $req->language->alternatives || ['en'];

    # We should not try to find templates including lang
    if( $ext_full =~ /^\.(\w\w)\.tt$/ )
    {
	debug "Trying to get template with specific lang ext ($template)";
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
    $page->set_dirsteps( $req->uri2file( $path_full )."/" );

    my @searchpath = $req->uri2file($path_full)."/";

    if( $site->is_compiled )
    {
	push @searchpath, map $_."def/", @{$page->{'dirsteps'}};
    }
    else
    {
	my $destroot = $site->home->sys_path;
	my $dir = $req->uri2file( $path_full );
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

    debug(4,"Check $ext",1);
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
	    die "Found a directory: $path$base_name$ext_full\nShould redirect";
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
			    $data = load_compiled( $compfile );

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

sub load_compiled
{
    my( $page, $file ) = @_;
    my $compiled;

    # From Template::Provider::_load_compiled:
    # load compiled template via require();  we zap any
    # %INC entry to ensure it is reloaded (we don't 
    # want 1 returned by require() to say it's in memory)
    delete $INC{ $file };
    eval { $compiled = require $file; };
    if( $@ )
    {
	throw('compile', "compiled template $compiled: $@");
    }
    return $compiled;
}


#######################################################################

=head2 get_static

  $p->get_static( $in, $pageref )

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
    die "not implemented";
    my( $page ) = @_;

    my $req = $page->req;

    ### Output page
    my $client = $req->client;
    my $template = $page->url_path_tmpl;
    my $out = "";

    my $site = $page->site;
    my $home = $site->home_url_path;

    $req->note("Rendering page");


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
			my $incpathstring = join "", map "- $_\n", @{$req->{'incpath'}};
			$part->add_message("Include path is\n$incpathstring");
		    }
		    else
		    {
			debug "Other template error";
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


=head2 set_dirsteps

  $p->set_dirsteps()

  $p->set_dirsteps( $path_full )

path_full defaults to the current template dir. It must end with a
/. It is a filesystem path. Not the URL path

Returns: L</dirsteps>

=cut

sub set_dirsteps
{
    my( $page, $path_full ) = @_;
    my $req = $page->req;

    $path_full ||= $page->dir->sys_path_slash;
#    $path_full ||= $req->uri2file( dirname( $page->url_path_tmpl ) . "/" ) . "/";
    my $path_home = $page->site->home->sys_path;
    debug 3, "Setting dirsteps for $path_full";
    undef $page->{'incpath'};
    $page->{'dirsteps'} = [ Para::Frame::Utils::dirsteps( $path_full, $path_home ) ];
#    cluck "dirsteps for $_[0] set to ".Dumper($page->{'dirsteps'}); ### DEBUG
    return $page->{'dirsteps'};
}


#######################################################################

=head2 dirsteps

  $p->dirsteps

Returns: the current dirsteps as a ref to a list of strings.

=cut

sub dirsteps
{
    return $_[0]->{'dirsteps'};
}

#######################################################################


=head2 set_incpath

  $p->set_incpath( \@incpath )

Internally used by L</incpath>.

The param should be a ref to an array of absolute paths (from the
system root) to dirs with template include files.

Places the L<Para::Frame::Burner> should look for templates to
include.

Returns: L</incpath>

=cut

sub set_incpath
{
#    cluck "incpath for $_[0] set to ".Dumper($_[1]); ### DEBUG
    return $_[0]->{'incpath'} = $_[1];
}

#######################################################################

=head2 incpath

  $p->incpath()

Internally used by L</paths>, that sets up the incpath. Use L</paths>
instead of this method.

Returns: A ref to an array of absolute paths (from the system root) to
dirs with template include files.

=cut


sub incpath
{
    return $_[0]->{'incpath'};
}


#######################################################################

=head1 Removed methods

=head2 url_dir

use .dir.url_path instead

=head2 url_dir_path

use .dir.url_path_slash instead

=head2 url_parent

use .parent.url_path instead

=head2 url_parent_path

use .parent.url_path_slash instead

=head2 sys_dir

use .dir.sys_path instead

=cut

#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
