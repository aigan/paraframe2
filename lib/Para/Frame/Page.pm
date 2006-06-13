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

There is no clear distinction between Para::Frame::Request and
Para::Frame::Page.

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

=head2 new

  Para::Frame::Page->new($req)

Creates a Page object. It should be initiated after the request has
been registred. (Done by L<Para::Frame>.)

=cut

sub new
{
    my( $this, $req ) = @_;
    my $class = ref($this) || $this;
    ref $req or die "req missing";

    my $page = bless
    {
     headers        => [],             ## Headers to be sent to the client
     uri            => undef,
     template       => undef,          ## if diffrent from URI
     template_uri   => undef,          ## if diffrent from URI
     error_template => undef,          ## if diffrent from template
     moved_temporarily => 0,           ## ... or permanently?
     redirect       => undef,          ## ... to other server
     ctype          => undef,          ## The response content-type
     in_body        => 0,              ## flag then headers sent
     page_content   => undef,          ## Ref to the generated page
     page_sender    => undef,          ## The mode of sending the page
     incpath        => undef,
     dirsteps       => undef,
     params         => undef,
     renderer       => undef,
     site           => undef,          ## The site for the request
     req            => $req,
    }, $class;
    weaken( $page->{'req'} );

    $page->{'params'} = {%$Para::Frame::PARAMS};

    return $page;
}

sub req { $_[0]->{'req'} }


=head2 init

  $page->init()

Initiates the page object for the request. (Not used for page objects
not to be used as the response page.)

=cut

sub init
{
    my( $page ) = @_;

    my $req = $page->req;

    my $site_name = $req->dirconfig->{'site'} || $req->host_from_env;
    $page->{'site'} = Para::Frame::Site->get( $site_name );


    $page->ctype( $req->{'orig_ctype'} );
    $page->set_uri();
}

#######################################################################

=head1 Accessors

Prefix url_ gives the path of the page in http on the host

Prefix sys_ gives the path of the page in the filesystem

No prefix gives the path of the page relative the site root in url_path

path_tmpl gives the path and filename

path_full gives the preffered URI for the file

path_base excludes the suffix of the filename

dir excludes the trailing slash (and the filename)


 # url_path_tmpl  template
 # url_path_full  template_uri
 # url_path_base
 # url_dir
 # filename
 # basename
 # path_tmpl     site_uri
 # path_full
 # path_base     site_file
 # dir           site_dir
 # sys_path_tmpl
 # sys_path_base
 # sys_dir

Some of these are not yet implemented...

=cut

=head2 url_path_tmpl

The path and filename in http on the host. With the language part
removed.

=cut

sub url_path_tmpl
{
    return $_[0]->{'template'} || $_[0]->uri;
}

sub template
{
    return $_[0]->{'template'} || $_[0]->uri;
}

=head2 url_path_full

The preffered URI for the file in http on the host.

=cut

sub url_path_full
{
    return $_[0]->{'template_uri'} || $_[0]->uri;
}

sub template_uri
{
    return $_[0]->{'template_uri'} || $_[0]->uri;
}


=head2 url_dir

The URI excluding the trailing slash (and the filename). If The URI is
a dir, the C<url_dir> will be the same, minus the ending '/'.

=cut

sub url_dir
{
    my( $dir ) = $_[0]->{'template_uri'} =~ /^(.*)\//;
    return $dir;
}


=head2 url_dir_path

The same as L</url_dir>, but ends with a '/'.

=cut

sub url_dir_path
{
    my( $dir ) = $_[0]->{'template_uri'} =~ /^(.*\/)/;
    return $dir;
}


=head2 url_parent

Same as L</url_dir>, except that if the template is a dir, we will instead get the previous dir. Excluding the trailing slash.

=cut

sub url_parent
{
    my( $dir ) = $_[0]->{'template_uri'} =~ /^(.*)\/./;
    return $dir;
}


=head2 url_parent_path

The same as L</url_parent>, but ends with a '/'.

=cut

sub url_parent_path
{
    my( $dir ) = $_[0]->{'template_uri'} =~ /^(.*\/)./;
    return $dir;
}


=head2 filename

The template filename without the path.

=cut

sub filename
{
    $_[0]->url_path_tmpl =~ /\/([^\/]+)$/
	or die "Couldn't get filename from ".$_[0]->url_path_tmpl;
    return $1;
}

=head2 path_base

The path to the template, including the filename, relative the site
home, begining with a slash. But excluding the suffixes of the file
along with the dots.

=cut

sub path_base
{
    my( $page ) = @_;

    my $home = $page->site->home;
    my $template = $page->url_path_tmpl;
    $template =~ /^$home(.*?)(\.\w\w)?\.\w{2,3}$/
      or die "Couldn't get path_base from $template under $home";
    return $1;
}

=head2 path_full

The preffered URI for the file, relative the site home, begining with
a slash.

=cut

sub path_full
{
    my( $page ) = @_;

    my $home = $page->site->home;
    my $template_uri = $page->url_path_full;
    my( $site_uri ) = $template_uri =~ /^$home(.+?)$/
      or die "Couldn't get site_uri from $template_uri under $home";
    return $site_uri;
}

=head2 path_tmpl

The path to the template, including the filename, relative the site
home, begining with a slash.

=cut

sub path_tmpl
{
    my( $page ) = @_;

    my $home = $page->site->home;
    my $template = $page->url_path_tmpl;
    my( $site_uri ) = $template =~ /^$home(.+?)$/
      or confess "Couldn't get site_uri from $template under $home";
    return $site_uri;
}

=head2 dir

The path to the template, excluding the filename, relative the site
home, begining but not ending with a slash.

=cut

sub dir
{
    my( $page ) = @_;

    my $home = $page->site->home;
    my $template = $page->url_path_tmpl;
    $template =~ /^$home(.*?)\/[^\/]*$/
      or confess "Couldn't get site_dir from $template under $home";
    return $1;
}

=head2 sys_path_tmpl

The path and filename from system root.

=cut

sub sys_path_tmpl
{
    return $_[0]->req->uri2file($_[0]->{'template'});
}

=head2 sys_dir

The path and from system root. Excluding the last '/'

=cut

sub sys_dir
{
    my $sys_path_tmpl = $_[0]->sys_path_tmpl;
    my( $dir ) = $sys_path_tmpl =~ /^(.*\/)/;

    return $dir;
}

=head2 is_index

True if this is a C</index.tt>

=cut

sub is_index
{
    if( $_[0]->{'template_uri'} =~ /\/$/ )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}


#############################################
#############################################

=head2 site

  $page->site

Returns the L<Para::Frame::Site> this page is located in.

=cut

sub site
{
    return $_[0]->{'site'} ||= Para::Frame::Site->get();
}


=head2 set_site

  $page->set_site( $site )

Sets the site to use for this request.

C<$site> should be the name of a registred L<Para::Frame::Site>.

The site must use the same host as the request.

=cut

sub set_site
{
    my( $page, $site_in ) = @_;
    my $req = $page->req;

    my $site = Para::Frame::Site->get( $site_in );

    # Check that site mathces the client
    #
    unless( $req->client =~ /^background/ )
    {
	if( my $orig = $req->original )
	{
	    unless( $orig->site->host eq $site->host )
	    {
		my $site_name = $site->name;
		my $orig_name = $orig->site->name;
		debug "Host mismatch";
		debug "orig site: $orig_name";
		debug "New name : $site_name";
		confess "set_site called";
	    }
	}
    }

    return $page->{'site'} = $site;
}


=head2 error_page_selected

  $page->erro_page_selected

True if an error page has been selected

=cut

sub error_page_selected
{
    return $_[0]->{'error_template'} ? 1 : 0;
}

=head2 error_page_not_selected

  $page->error_page_not_selected

True if an error page has not been selected

=cut

sub error_page_not_selected
{
    return $_[0]->{'error_template'} ? 0 : 1;
}

sub find_template
{
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
    }

    # Reasonable default?
    my $language = $req->language->alternatives || ['en'];

    # We should not try to find templates including lang
    if( $ext_full =~ /^\.(\w\w)\.tt$/ )
    {
	debug "Trying to get template with specific lang ext";
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
	my $destroot = $req->uri2file($site->home.'/');
	my $dir = $req->uri2file( $path_full );
	$dir =~ s/^$destroot// or
	  die "destroot $destroot not part of $dir";
#	debug "destroot: $destroot";
#	debug "dir: $dir";



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
		my $burner = Para::Frame::Burner->get_by_type('html');
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
			my $parsedoc = $parser->parse( $filetext )
			    or throw('template', "parse error:\nFile: $filename\n".
				     $parser->error);

			$parsedoc->{ METADATA }{'name'} = $filename;
			$parsedoc->{ METADATA }{'modtime'} = $mod_time;

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
			if( $template eq $site->home.'/error.tt' )
			{
			    $page->{'error_template'} = $template;
			    $page->{'page_content'} = $page->fallback_error_page;
			    return undef;
			}
			debug(2,"Using /error.tt");
			($in) = $page->find_template($site->home.'/error.tt');
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
	my $sample_template = $site->home . "/def/page_not_found.$lang.tt";
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


sub load_compiled  ############ function!
{
    my( $file ) = @_;
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
	my $path = $page->uri->path;
	$out .= "<p>Try to get the page from  <a href=\"http://$backup$path\">$backup</a> instead</p>\n"
	}
    return \$out;
}


sub set_headers
{
    my( $page, $headers ) = @_;

    $page->{'headers'} = $headers;
}

=head2 add_header

  $page->add_header( [[$key,$val], [$key2,$val2], ... ] )

Adds one or more http response headers.

=cut

sub add_header
{
    push @{ shift->{'headers'}}, [@_];
}

=head2 headers

  $page->headers

Returns the http headers to be sent to the client as a listref to
listrefs of key/val pairs.

=cut

sub headers
{
    return @{$_[0]->{'headers'}};
}

sub set_uri
{
    my( $page, $uri_in ) = @_;

    # Only used by Para::Frame to set uri from original uri. Never
    # changes from that original uri.

    $uri_in ||= $page->req->{'orig_uri'};

    my $uri = Para::Frame::URI->new($uri_in);

    debug(3,"Setting URI to $uri");
    $page->{uri} = $uri;
    $page->set_template( $uri, 1 );

    return $uri;
}

sub uri
{
    return $_[0]->{'uri'};
}

=head2 set_template

  $page->set_template( $template )

  $page->set_template( $template, $always_move_flag )

C<$template> should be the URL path including the filename. This can
later be retrieved by L</url_path_tmpl>.

Redirection to other pages can be done by using this method. Even from
inside a page being generated.

Apache can possibly be rewriting the name of the file. For example the
uri C</this.tt> may be translated to, based on Apache config, to
C</var/www/that.tt>.

The template to file translation is used for getting the directory of
the template. But we assume that the filename part of the URI
represents an actual file, regardless of the uri2file translation. If
the translation goes to another file, that file will be ignored and
the file named like that in the URI will be used.

For example: If the site path is C</var/www> and we have a path
translation in the apache config that translates C</one/two.tt> to
C</var/www/three/four.tt> we will be using the template
C</var/www/three/two.tt> using the dir but disregarding the filename
change.

We want to tell browsers/spiders if any redirection is a permanent or
temporary one. We assume it's a temporary one unless
C<$always_move_flag> is true. But if just one move is of temporary
nature, keep that value. This will only be used if we are ending up
redirecting to another page.

The content type is set to C<text/html> if this is a C<.tt> file.

=cut

sub set_template
{
    my( $page, $template, $always_move ) = @_;

    # For setting a template diffrent from the URI

    if( UNIVERSAL::isa $template, 'URI' )
    {
	$template = $template->path;
    }

    # To forward to a page not handled by the paraframe, use
    # redirect()

    if( $template =~ /^http/ )
    {
	# template param should NOT include the http://hostname part
	croak "Tried to set a template to $template";
    }

    $template =~ s/\/index(\.\w\w)?.tt$/\//;

    my $template_uri = $template;


    $page->{'moved_temporarily'} ||= 1 unless $always_move;

    my $file = $page->req->uri2file( $template );
    debug(3,"The template $template represents the file $file");
    if( -d $file )
    {
	debug(3,"  It's a dir!");
	unless( $template =~ /\/$/ )
	{
	    $template .= "/";
	    $template_uri .= "/";
	}
    }

    if( $template =~ /\/$/ )
    {
	# Template indicates a dir. Make it so
	$template .= "index.tt";
    }
    else
    {
	# Remove language part
	$template_uri =~ s/\.\w\w(\.\w{2,3})$/$1/;
    }

    debug(3,"setting template to $template");
    debug(3,"setting template_uri to $template_uri");

    $page->ctype->set("text/html") if $template =~ /\.tt$/;

    $page->{template}     = $template;
    $page->{template_uri} = $template_uri;

    return $template;
}

=head2 set_error_template

  $page->set_error_template( $path_tmpl )

Calls L</set_template> for setting the template. Sets a flag for
remembering that this is an error response page.

NB! Should be called with a L</path_tmpl> and not a
L<url_path_tmpl>. We will prepend the L<Para::Frame::Site/home>
part.

This is done because we may change site that displays the error page.
That also means that the site changed to, must find that template.

=cut

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

    my $home = $page->site->home;
    return $page->{'error_template'} =
      $page->set_template( $home . $error_tt );
}

=head2 ctype

  $page->ctype

  $page->ctype( $content_type )

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

=head2 add_params

  $page->add_params( \%params )

  $page->add_params( \%params, $keep_old_flag )

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

sub render_output
{
    my( $page ) = @_;

    my $req = $page->req;

    ### Output page
    my $client = $req->client;
    my $template = $page->template;
    my $out = "";

    my $site = $page->site;
    my $home = $site->home;


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
	$burner->burn($in, $page->{'params'}, \$out)
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
	    my $error_tt = $page->template; # Could have changed
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





=head2 precompile

  $req->precompile( $srcfile, $destfile_web )

  $req->precompile( $srcfile, $destfile_web, \%args )

  arg type defaults to html_pre
  arg language defaults to undef

$srcfile is the absolute system path to the template.

$destfile_web is the URL path in the current site for the destination
file.

=cut

sub precompile
{
    my( $page, $srcfile, $destfile_web, $args ) = @_;

    my $req = $page->req;

    $args ||= {};

    # Check that destfile_web matches given site
    my $home = $page->site->home;
    if( length( $home ) )
    {
	$destfile_web =~ /^$home/ or
	  die "The file $destfile_web is not placed in $home";
    }

    my( $res, $error );

    my $type = $args->{'type'} || 'html_pre';

    $destfile_web =~ /([^\/])$/ or die "oh no";
    my $filename = $1;

    my $destfile =  $req->uri2file( $destfile_web );
    my $safecnt = 0;
    while( $destfile !~ /$filename$/ )
    {
	die "Loop" if $safecnt++ > 100;
	debug "Creating dir $destfile";
	create_dir($destfile);
	$req->uri2file_clear( $destfile_web );
	$destfile =  $req->uri2file( $destfile_web );
    }

    my $destdir = dirname( $destfile );

    # The URI shoule be the dir and not index.tt
    # TODO: Handle this in another place?
    my $uri = $req->normalized_uri($destfile_web);
    $uri =~ s/\/index(\.\w\w)?\.tt$/\//;

    if( debug > 1 )
    {
	debug "srcfile     : $srcfile";
	debug "destfile_web: $destfile_web";
	debug "destfile    : $destfile";
	debug "destdir     : $destdir";
	debug "type        : $type";
	debug "uri         : $uri";
    }


    $page->set_uri( $uri );
    $page->set_template( $destfile_web );
    $page->{'params'}{'me'} = $page->url_path_full;

    $page->set_dirsteps($destdir.'/');

    my $fh = new IO::File;
    $fh->open( "$srcfile" ) or die "Failed to open '$srcfile': $!\n";

    $page->set_tt_params;

    my $burner = Para::Frame::Burner->get_by_type($type);
    $res = $burner->burn($fh, $page->{'params'}, $destfile );
    $fh->close;
    $error = $burner->error;

    if( $error )
    {
	debug "ERROR WHILE PRECOMPILING PAGE";
	debug 2, $error;
	my $part = $req->result->exception($error);
	if( ref $error and $error->info =~ /not found/ )
	{
	    debug "Subtemplate for precompile not found";
	    my $incpathstring = join "", map "- $_\n", @{$page->incpath};
	    $part->add_message("Include path is\n$incpathstring");
	}

	die $part;
    }

    return 1;
}

sub send_output
{
    my( $page ) = @_;

    my $req = $page->req;

    # Forward if URL differs from template_url

    if( debug > 2 )
    {
	debug(0,"Sending output to ".$page->uri);
	debug(0,"Sending the page ".$page->template_uri);
	unless( $page->error_page_not_selected )
	{
	    debug(0,"An error page was selected");
	}
    }


    # forward if requested uri ends in '/index.tt' or if it is a dir
    # without an ending '/'

    my $uri = $page->uri;
    my $uri_norm = $req->normalized_uri( $uri );
    if( $uri ne $uri_norm )
    {
	$page->forward($uri_norm);
    }
    elsif( $page->error_page_not_selected and
	$uri ne $page->template_uri )
    {
	$page->forward();
    }
    else
    {
	# If not set, find out best way to send page
	if( $page->{'page_sender'} )
	{
	    unless( $page->{'page_sender'} =~ /^(utf8|bytes)$/ )
	    {
		debug "Page sender $page->{page_sender} not recogized";
	    }
	}
	else
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

	if( $page->{'page_sender'} eq 'utf8' )
	{
	    $page->ctype->set_charset("UTF-8");
	    $page->send_headers;
	    binmode( $req->client, ':utf8');
	    debug(4,"Transmitting in utf8 mode");
	    $req->send_in_chunks( $page->{'page_content'} );
	    binmode( $req->client, ':bytes');
	}
	else # Default
	{
	    $page->send_headers;
	    $page->send_in_chunks( $page->{'page_content'} );
	}
    }
}

sub forward
{
    my( $page, $uri ) = @_;
    my $req = $page->req;

    # Should only be called AFTER the page has been generated

    # To request a forward, just set the set_template($uri) before the
    # page is generated.

    # To forward to a page not handled by the paraframe, use
    # redirect()

    my $site = $page->site;

    $uri ||= $page->template_uri;


    debug "Forwarding to $uri";

    if( not $page->{'page_content'} )
    {
	cluck "forward() called without a generated page";
	unless( $uri =~ /\.html$/ )
	{
	    $uri = $site->home."/error.tt";
	}
    }
    elsif( $uri =~ /\.html$/ )
    {
	debug "Forward to html page: $uri";
	my $referer = $req->referer;
	debug "  Referer is $referer";
	debug "  Cancelling forwarding";
	$page->{template_uri} = $req->uri;
	$page->send_output;
	return;
    }

    $page->output_redirection($uri );
    $req->session->register_result_page($uri, $page->{'headers'}, $page->{'page_content'});
}

=head2 redirect

  $page->redirect( $uri )

  $page->redirect( $uri, $permanently_flag )

This is for redirecting to a page not handled by the paraframe.

The actual redirection will be done then all the jobs are
finished. Error in the jobs could result in a redirection to an
error page instead.

The C<$uri> should be a full uri string starting with C<http:> or
C<https:> or just the path under the curent host.

If C<$permanently_flag> is true, sets the http header for indicating
that the requested page permanently hase moved to this page.

For redirection to a TT page handled by the same paraframe daemon, use
L</set_template>.

=cut

sub redirect
{
    my( $page, $uri, $permanently ) = @_;

   $page->{'moved_temporarily'} ||= 1 unless $permanently;

    $page->{'redirect'} = $uri;
}

=head2 redirection

  $page->redirection

Returns the page we eill redirect to, or undef.

=cut

sub redirection
{
    return $_[0]->{'redirect'};
}

sub output_redirection
{
    my( $page, $uri_in ) = @_;
    my $req = $page->req;

    $uri_in or die "URI missing";

    # Default to temporary move.

    my $uri_out;

    # URI module doesn't support punycode. Bypass module if we
    # redirect to specified domain
    #
    if( $uri_in =~ /^ https?:\/\/ (.*?) (: | \/ | $ ) /x )
    {
	my $host_in = $1;
#	warn "  matched '$host_in' in '$uri_in'!\n";
	my $host_out = idn_encode( $host_in );
#	warn "  Encoded to '$host_out'\n";
	if( $host_in ne $host_out )
	{
	    $uri_in =~ s/$host_in/$host_out/;
	}

	$uri_out = $uri_in;
    }
    else
    {
	my $uri = Para::Frame::URI->new($uri_in, 'http');
	$uri->host( idn_encode $req->http_host ) unless $uri->host;
	$uri->port( $req->http_port ) unless $uri->port;
	$uri->scheme('http');

	$uri_out =  $uri->canonical->as_string;
    }

    debug(2,"--> Redirect to $uri_out");

    my $moved_permanently = $page->{'moved_temporarily'} ? 0 : 1;

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
    $req->send_code( 'AR-PUT', 'header_out', 'Location', $uri_out );

    my $out = "Go to $uri_out\n";
    my $length = length( $out );

    $req->send_code( 'AR-PUT', 'header_out', 'Content-Length', $length );
    $req->send_code( 'AR-PUT', 'send_http_header', 'text/plain' );
    $req->client->send( "\n" );
    $req->client->send( $out );
}

sub set_http_status
{
    my( $page, $status ) = @_;
    return 0 if $status < 100;
    return $page->req->send_code( 'AR-PUT', 'status', $status );
}

sub send_headers
{
    my( $page ) = @_;

    my $req = $page->req;

    my $client = $req->client;

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

    debug(2,"Send newline");
    $client->send( "\n" );
    $page->{'in_body'} = 1;
}

sub send_in_chunks
{
    my( $page, $dataref ) = @_;

    my $req = $page->req;

    my $client = $req->client;
    my $length = length($$dataref);
    debug(4,"Sending ".length($$dataref)." bytes of data to client");
    my $sent = 0;
    my $errcnt = 0;

    unless( $length )
    {
	confess "We got nothing to send (for req $req)";
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

		    if( $req->{'cancel'} )
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
		    debug(1,"  Failed to send data to client\n  Tries to recover...",1);
		    
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
	debug(4,"Transmitted $sent chars to client");
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



=head2 set_dirsteps

  $page->set_dirsteps()

  $page->set_dirsteps( $path_full )

path_full defaults to the current template dir. It must end with a
/. It is a filesystem path. Not the URL path

=cut

sub set_dirsteps
{
    my( $page, $path_full ) = @_;
    my $req = $page->req;

    $path_full ||= $req->uri2file( dirname( $page->template ) . "/" ) . "/";
    my $path_home = $req->uri2file( $page->site->home  . "/" );
    debug 3, "Setting dirsteps for $path_full";
    undef $page->{'incpath'};
    $page->{'dirsteps'} = [ Para::Frame::Utils::dirsteps( $path_full, $path_home ) ];
#    cluck "dirsteps for $_[0] set to ".Dumper($page->{'dirsteps'}); ### DEBUG
    return $page->{'dirsteps'};
}

=head2 dirsteps

  $page->dirsteps

Returns the current dirsteps as a ref to a list of strings.

=cut

sub dirsteps
{
    return $_[0]->{'dirsteps'};
}

sub set_incpath
{
#    cluck "incpath for $_[0] set to ".Dumper($_[1]); ### DEBUG
    return $_[0]->{'incpath'} = $_[1];
}

sub incpath
{
    return $_[0]->{'incpath'};
}


=head2 paths

  $page->paths()

Automaticly called by L<Template::Provider> via L<Para::Frame::Burner>
to get the include paths for building pages from templates.

=cut

sub paths
{
    my( $page, $burner ) = @_;

    unless( $page->incpath )
    {
	my $type = $burner->{'type'};

	my $site = $page->site;
	my $subdir = 'inc' . $burner->subdir_suffix;

 	my $path_full = $page->dirsteps->[0];
	my $destroot = $page->req->uri2file($site->home.'/');
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



=head2 set_renderer

  $page->set_renderer( \&renderer )

Sets the code to run for rendering the page, if not the standard
renderer.

Example renderer:

  my $render_hello = sub
  {
      my( $req ) = @_;
      my $page = $req->page;
      $page->ctype("text/html");
      my $out = "<h1>Hello world!</h1>";
      $page->set_content(\$out);
      return 1;
  };
  $page->set_renderer($render_hello);

=cut

sub set_renderer
{
    return $_[0]->{'renderer'} = $_[1] || undef;
}

=head2 renderer

  $page->renderer

Returns the renderer to be used, if not the standard renderer

=cut

sub renderer
{
    return $_[0]->{'renderer'};
}

=head2 set_content

  $page->set_content( \$content )

Sets the page to be returned to the client.

If you want an action to returns a special type of page, it should use
L</set_renderer> since that renderer is called after all actions been
sorted out.

But you could set the response page directly in the action by calling
this method.

=cut

sub set_content
{
    my( $page, $content_ref ) = @_;

    $page->{'page_content'} = $content_ref;
}


=head2 set_tt_params

The standard functions availible in templates.

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

Holds the L<Para::Frame::Request/template_uri>.

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

    # Keep alredy defined params  # Static within a request
    $page->add_params({
	'page'            => $page,

	'me'              => $page->url_path_full,

	'u'               => $Para::Frame::U,
	'lang'            => $req->language->preferred, # calculate once
	'req'             => $req,

	# Is allowed to change between requests
	'site'            => $site,
	'home'            => $site->home,
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

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
