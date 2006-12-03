#  $Id$  -*-cperl-*-
package Para::Frame::Site;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Web Site class
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

Para::Frame::Site - Represents a particular website

=head1 DESCRIPTION

A Paraframe server can serv many websites. (And a apache server can
use any number of paraframe servers.)

One website can have several diffrent host names, like www.name1.org,
www.name2.org.

The mapping of URL to file is done by Apache. Apache also give a
canonical name of the webserver.

Background jobs may not be coupled to a specific site.

Information about each specific site is looked up by L</get> using
L</host> as param.

=cut

use strict;
use Carp qw( croak cluck confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug fqdn datadump );
use Para::Frame::Dir;
use Para::Frame::CSS;

our %DATA; # hostname -> siteobj
our %ALIAS; # secondary names

#######################################################

sub _new
{
    my( $this, $params ) = @_;
    my $class = ref($this) || $this;

    my $home_in = delete $params->{home};
    $home_in ||= delete $params->{home_url_path};
    $home_in ||= delete $params->{webhome};
    $home_in ||= '';

    my $site = bless $params, $class;

    if( $site->webhost =~ /^http/ )
    {
	croak "Do not include http in webhost";
    }

    if( $home_in =~ /\/$/ )
    {
	croak "Do not end home_url_path wit a '/'";
    }

    if( ref $home_in )
    {
	$home_in = $home_in->url_path;
    }

    $site->{'home_url_path'} = $home_in;

    return $site;
}

#######################################################

=head2 add

  Para::Frame::Site->add( \%params )

Adds a site with the given params. Should be called before
startup. The params are stored as the properties of the object, to be
used later.

Special params are:

=over

C<webhost      > = See L</host>

C<aliases      > = a listref of site aliases

C<name         > = See L</name>

C<code         > = See L</code>

C<home         > = See L</home>

C<home_url_path> = See L</home_url_path>

C<last_step    > = See L</last_step>

C<login_page   > = See L</login_page>

C<logout_page  > = See L</logout_page>

C<loopback     > = See L</loopback>

C<backup_host  > = See L</backup_host>

C<appbase      > = See L</appbase>

C<appfmly      > = See L</appfmly>

C<approot      > = See L</approot>

C<appback      > = See L</appback>

C<params       > = See L</params>

C<languages    > = See L</languages>

C<htmlsrc      > = See L</htmlsrc>

C<is_compiled  > = See L</is_compiled>

C<send_email   > = See L</send_email>

=back

The site is registred under the L</host>, L</code> and all given
C<aliases>.

The B<first> site registred under a given L</host> is the default
site used for requests under that domain.

The first site registred will be the C<default> site, used for
background jobs then no other site are specified.

=cut

sub add
{
    my( $this, $params ) = @_;

    my $site = $this->_new( $params );

    debug "Registring site ".$site->name;

    my $home = $site->home_url_path || '';
    my $key = $site->host . $home;

    $DATA{ $key }        ||= $site;
    $ALIAS{ $key }       ||= $site;
    $ALIAS{ $site->host }||= $site;
    $ALIAS{'default'}    ||= $site;

    foreach my $alias (@{$params->{'aliases'}})
    {
	$ALIAS{ $alias } ||= $site;
    }

    if( my $alias = $params->{'code'} )
    {
	$ALIAS{ $alias } ||= $site;
    }

    return $site;
}

#######################################################

=head2 clone

  $site->clone( $hostname )

  $site->clone( \%params )

Adds a site based on C<$site>, but for a new host.

Returns: the new site

=cut

sub clone
{
    my( $site, $params_in ) = @_;

    my $params;
    if( ref $params_in )
    {
	$params = $params_in;
    }
    else
    {
	$params =
	{
	 webhost => $params_in,
	};
    }

    debug sprintf "Cloning %s as %s", $site->host, $params->{'webhost'};

    foreach my $key ( keys %$site )
    {
	next if $key =~ /^(webhost|aliases|name|code|home)$/;
	$params->{$key} = $site->{$key};
    }

    return Para::Frame::Site->add($params);
}

#######################################################

=head2 get

  Para::Frame::Site->get( $name )

Returns the site registred (by L</add>) under the given C<$name>.

If $name is a site object, retuns it.

Returns: A L<Para::Frame::Site> object

Exceptions: Croaks if site nor found

=cut

sub get
{
    my( $this, $name ) = @_;

    return $name if UNIVERSAL::isa($name, 'Para::Frame::Site');

    no warnings 'uninitialized';

#    cluck "getting default" if $name eq 'default'; ### DEBUG

    debug 3, "Looking up site $name";
#    debug "Returning ".datadump($DATA{$name});

    return $DATA{$name} || $ALIAS{$name} ||
	croak "Site $name is not registred";
}

#######################################################

=head2 get_by_url

  Para::Frame::Site->get_by_url( $url )

Returns the site registred (by L</add>) under the given C<$url>.

Handles multiple site under the same host.

Returns: A L<Para::Frame::Site> object

Exceptions: Croaks if site nor found

TODO: Handle other ports

=cut

sub get_by_url
{
    my( $this, $url_in ) = @_;

    my $url;
    if( UNIVERSAL::isa($url_in, 'URI') )
    {
	if( my $port = $url_in->port )
	{
	    if( $port != 80 )
	    {
		confess "FIXME";
	    }
	}
	$url = $url_in->host . $url_in->path;
    }
    elsif( ref $url_in )
    {
	confess "Can't handle $url_in";
    }
    else
    {
	$url = lc( $url_in );
	$url =~ s/^https?://;
	$url =~ s/\/\///g; # Both host identifier and double in path
	$url =~ s/\/$//;
    }

    my $url_given = $url;
    while( length $url )
    {
	if( my $site = $DATA{ $url } )
	{
	    return $site;
	}

	$url =~ s/\/[^\/]+$// or last;
    }

    croak "Site $url_given is not registred";
}

#######################################################

=head2 get_by_req

  Para::Frame::Site->get_by_req( $req )

Gets the site matching the req

If a site match is not found, and L<Para::Frame/site_auto> is set,
creating a new site for the host. It will use the first match of a)
the host without the port part, b) L<Para::Frame/site_auto> and c)
C<default>.

Returns: A L<Para::Frame::Site> object

=cut

sub get_by_req
{
    my( $this, $req ) = @_;

    die unless $req->isa('Para::Frame::Request');

    if( my $site_name = $req->dirconfig->{'site'} )
    {
	return Para::Frame::Site->get( $site_name );
    }

    my $hostname = $req->host_from_env;
    if( my $site = $DATA{ $hostname } )
    {
	return $site;
    }

    my $auto = $Para::Frame::CFG->{'site_auto'};

    unless( $auto )
    {
	die sprintf "No site for %s registred", $hostname;
    }

    if( my $site_alt = $ALIAS{ $hostname } )
    {
	return $site_alt->clone($hostname);
    }

    if($hostname =~ /:\d+$/)
    {
	my $hostname_alt = $req->host_without_port;
	if( my $site_alt = $DATA{ $hostname_alt } || $ALIAS{ $hostname_alt } )
	{
	    return $site_alt->clone($hostname);
	}
    }

    if( $auto =~ /\w/ )
    {
	if( my $site_alt = $DATA{ $auto } || $ALIAS{ $auto } )
	{
	    return $site_alt->clone($hostname);
	}
    }

    return $this->get('default')->clone($hostname);
}

#######################################################################

=head2 get_page

=cut

sub get_page
{
    my( $site, $url_in, $args ) = @_;

    $args ||= {};

    $args->{'site'} = $site;
    $args->{'url'}  = $site->home_url_path . $url_in;

    return Para::Frame::File->new($args);
}


#######################################################################

=head2 get_possible_page

=cut

sub get_possible_page
{
    my( $site, $url_in, $args ) = @_;

    $args ||= {};
    $args->{'file_may_not_exist'} = 1;
    $args->{'site'} = $site;
    $args->{'url'}  = $site->home_url_path . $url_in;

    return Para::Frame::File->new($args);
}


#######################################################################

=head2 name

  $site->name

Returns the C<name> of the site.

Default to L</host>.

=cut

sub name
{
    return $_[0]->{'name'} || $_[0]->webhost;
}

#######################################################################

=head2 desig

  $site->desig

Returns the C<name> of the site.

Default to L</host>.

=cut

sub desig
{
    return $_[0]->{'name'} || $_[0]->webhost;
}

#######################################################

=head2 code

  $site->code

Returns the C<code> of the site.

Defaults to L</host>.

=cut

sub code
{
    return $_[0]->{'code'} || $_[0]->webhost;
}


#######################################################################

=head2 uri2file

  $site->uri2file( $uri )

  $site->uri2file( $uri, $file )

  $site->uri2file( $uri, $file, $may_not_exist )

Same as L<Para::Frame::Request/uri2file>, but looks up the file for
the current site.

We will use the current request or create a new request if the sites
doesn't match.

=cut

sub uri2file
{
    my( $site ) = shift;

    my $req = $Para::Frame::REQ;
    my $req_site = $req->site;

    if( $site->equals($req_site) )
    {
#	debug "Getting uri2file from request";
	return $req->uri2file(@_);
    }
    else
    {
	my $args = {};
	$args->{'site'} = $site;
	debug "Getting uri2file from SUBREQUEST";
	debug "URI site is: ".$site->code;
	debug "Req site is: ".$req_site->code;
	debug "For $_[0]";

	return $req->new_subrequest($args,
				    \&Para::Frame::Request::uri2file,
				    @_ );
    }
}


#######################################################


=head2 home

  $site->home

Returns the L<Para::Frame::Dir> object for the L</home>.

=cut

sub home
{
    if( defined $_[0]->{'home'} )
    {
	return $_[0]->{'home'};
    }
    else
    {
#	debug "Creating dir obj for home '$_[0]->{home_url_path}/' for $_[0]";
#	debug "Looking for home";
	$_[0]->{'home'} =
	  Para::Frame::Dir->new({site => $_[0],
				 url  => $_[0]->{'home_url_path'}.'/',
				});
#	debug "Site home: ".$_[0]->{'home'}->sys_path_slash;
	return $_[0]->{'home'};
    }
}

#######################################################

=head2 home_url_path

  $site->home_url_path

Returns the home dir of the site as URL path, excluding the last '/'.

Should be an URL path.

TODO: rework PerlSetVar home config

This can be overridden by setting C<home> in dirconfig; Example
from .htaccess:

  PerlSetVar home /~myuser

B<Important> Do not end home with a C</>

=cut

sub home_url_path
{
    return $_[0]->{'home_url_path'};
}


#######################################################################


=head2 last_step

  $site->last_step

Returns the C<last_step> to be used if no mere steps are found in the
route. Used by L<Para::Frame::Route>.

Should be an URL path.

Defaults to C<undef>.

=cut

sub last_step
{
    return $_[0]->{'last_step'};
}

#######################################################

=head2 loadpage

  $site->loadpage

Returns the C<loadpage> to be used while generatiung the result for
pages that takes more than a couple of seconds to prepare. This should
be a html page set up in the same way as the default.

Should be an URL path.

Defaults to C<$home/pf/loading.html>.

=cut

sub loadpage
{
    return $_[0]->home_url_path .
      ( $_[0]->{'loadpage'} || "/pf/loading.html" );
}

#######################################################

=head2 login_page

  $site->login_page

Returns the C<login_page> to be used.

Should be an URL path.

Defaults to L</last_step> if defined.

Otherwise, defaults to L</home_url_path> + slash.

=cut

sub login_page
{
    return
	$_[0]->{'login_page'} ||
	$_[0]->{'last_step'}  ||
	$_[0]->home_url_path.'/';
}

#######################################################

=head2 logout_page

  $site->logout_page

Returns the C<logout_page> to be used.

Should be an URL path.

Defaults to L</home> + slash.

=cut

sub logout_page
{
    return $_[0]->{'logout_page'} ||
	$_[0]->home_url_path.'/';
}

#######################################################

=head2 host

  $site->host

Returns the C<webhost>.

This shold be the canonical name of the host of the site. This is the
main hostname of the apache virtual host. If the port is anything else
than 80, the port is apended. This string does not contain
'http://'. This is the value returned by
L<Para::Frame::Request/host>.

L<Para::Frame::Request/http_host> gives the name used in the request,
and may differ from the main hostname of the site.

Example: C<frame.para.se> or C<frame.para.se:81>

Defaults to the fully qualified domain name as returned by
L<Para::Frame::Utils/fqdn>.

=cut

sub host
{
    return $_[0]->webhost;
}

#######################################################

=head2 webhost

  $site->webhost

Same as L</host>

=cut

sub webhost
{
    return $_[0]->{'webhost'} || fqdn();
}

#######################################################

=head2 scheme

  $site->scheme

Returns the scheme part of the request uri. It's probably either http
or https.

We currently just returns the string 'http'.

Use this in the L<Para::Frame::URI> constructor.

=cut

sub scheme
{
    return "http";
}

#######################################################

=head2 loopback

  $site->loopback

Returns the C<loopback> path to use then Para::Frame connects to
itself via Apache (for getting info from mod_perl). This should be a
lightweight page.

Should be an URL path.

Defaults to L</home>.

=cut

sub loopback
{
    return $_[0]->{'loopback'} || $_[0]->home_url_path.'/';
}

#######################################################

=head2 backup_host

  $site->backup_host

Returns the C<backup_host> used by
L<Para::Frame::Request/fallback_error_page> for redirecting the user
to a backup website in cases then the site is severily broken.

=cut

sub backup_host
{
    return $_[0]->{'backup_host'};
}

#######################################################

=head2 host_without_port

  $site->host_without_port

Returns the L</host> without the port part.

=cut

sub host_without_port
{
    my $webhost = $_[0]->{'webhost'};

    $webhost =~ s/:\d+$//;
    return $webhost;
}

#######################################################

=head2 host_with_port

  $site->howt_with_port

Returns the L</host> B<with> the port part. For example
C<frame.para.se:80>.

=cut

sub host_with_port
{
    my $host = $_[0]->{'webhost'};

    if( $host =~ /:\d+$/ )
    {
	return $host;
    }
    else
    {
	return $host.":80";
    }
}

#######################################################

=head2 port

  $site->port

Returns the port of the L</host>.

=cut

sub port
{
    my $webhost = $_[0]->{'webhost'};
    $webhost =~ m/:(\d+)$/;
    return $1 || 80;
}

#######################################################

=head2 appbase

  $site->appbase

Returns the C<appbase> of the site.

This should be a prefix for Perl modules. If appbase is set to
C<MyProj>, the actions would have the prefix C<MyProj::Action::> and
be placed in C<lib/MyProj/Action/>.

Defaults to L<Para::Frame/CFG> C<appbase>.

=cut

sub appbase
{
    my( $site ) = @_;

    return $site->{'appbase'} || $Para::Frame::CFG->{'appbase'};
}

#######################################################

=head2 appfmly

  $site->appfmly

Returns the C<appfmly> for the site.

This should be a listref of elements, each to be treated ass fallbacks
for L</appbase>.  If no actions are found under L</appbase> one after
one of the elements in C<appfmly> are tried.

Defaults to L<Para::Frame/CFG> C<appfmly>.

=cut

sub appfmly
{
    my( $site ) = @_;
    my $family = $site->{'appfmly'} || $Para::Frame::CFG->{'appfmly'};
    unless( ref $family )
    {
	my @list = ();
	if( $family )
	{
	    push @list, $family;
	}
	return $site->{'appfmly'} = \@list;
    }

    return $family;
}

#######################################################

=head2 approot

  $site->approot

Returns the path to application. This is the dir that holds the C<lib>
and possibly the C<var> dirs.

Defaults to L<Para::Frame/CFG> C<approot>.

=cut

sub approot
{
    my( $site ) = @_;

    return $site->{'approot'} || $Para::Frame::CFG->{'approot'};
}

#######################################################

=head2 appback

  $site->appback

Returns the C<appback> of the site.

This is a listref of server paths. Each path should bee a dir that
holds a C<html> dir, or a C<dev> dir, for compiled sites.

These dirs can hold C<inc> and C<def> dirs that will be used in
template searches.

See L<Para::Frame::Request/find_template> and
L<Para::Frame::Burner/paths>.

Defaults to L<Para::Frame/CFG> C<appback>.

=cut

sub appback
{
    my( $site ) = @_;

    return $site->{'appback'} || $Para::Frame::CFG->{'appback'};
}

#######################################################


=head2 send_email

  $site->send_email

Returns C<send_email> of the site. True or false.

=cut

sub send_email
{
    if( defined $_[0]->{'send_email'} )
    {
	return $_[0]->{'send_email'};
    }
    else
    {
	if( defined $Para::Frame::CFG->{'send_email'} )
	{
	    return $Para::Frame::CFG->{'send_email'};
	}
    }

    return 1;
}

#######################################################

=head2 backup_redirect

  $site->backup_redirect

Returns the backup_redirect

=cut

sub backup_redirect
{
    return $_[0]->{'backup_redirect'};
}

#######################################################

=head2 params

  $site->params

The TT params to be added for each request in this site.

=cut

sub params
{
    return $_[0]->{'params'} || {};
}


#######################################################

=head2 dir

  $site->dir( $url )

Returns a L<Rit::Frame::Dir> object.

TODO: What is this used for?!

=cut

sub dir
{
    return Para::Frame::Dir->new({site => $_[0],
				  url  => $_[1],
				 });
}


#######################################################

=head2 languages

  $site->languages

Returns a listref of languages this site supports.

Each element should be the language code as a two letter string.

Defaults to L<Para::Frame/CFG> C<languages>.

=cut

sub languages
{
    return $_[0]->{'languages'} || $Para::Frame::CFG->{'languages'} || [];
}

#######################################################

=head2 supports_language

  $site->support_language( $langcode )

Returns true if given code is one of the supported

=cut

sub supports_language
{
    my( $site, $code_in ) = @_;

    foreach my $langcode (@{$site->languages})
    {
	return 1 if $langcode eq $code_in;
    }
    return 0;
}

#######################################################


sub htmlsrc # src dir for precompile or for getting inc files
{
    my( $site ) = @_;
    return $site->{'htmlsrc'} ||
      $site->{'is_compiled'} ?
	($site->approot . "/dev") :
	  $site->home->sys_path;
}

#######################################################

sub is_compiled
{
    return $_[0]->{'is_compiled'} || 0;
}

#######################################################

sub set_is_compiled
{
    return $_[0]->{'is_compiled'} = $_[1];
}

#######################################################

=head2 equals

  $site->equals( $site2 )

Returns true if C<$site> and C<$site2> is the same object.

=cut

sub equals
{
    # Uses perl obj stringification
    return( $_[0] eq $_[1] );
}

#######################################################

=head2 css

  $site->css

Returns a L<Para::Frame::CSS> object for the site.

=cut

sub css
{
    return $_[0]->{'css_obj'} ||=
      Para::Frame::CSS->new($_[0]->{'css'});
}


#######################################################

sub find_class
{
    return $_[0]->{'find_class'} ||
      $Para::Frame::CFG->{'find_class'};
}

#######################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
