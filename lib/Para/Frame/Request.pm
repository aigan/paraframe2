#  $Id$  -*-cperl-*-
package Para::Frame::Request;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2008 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Request - The request from the client

=cut

use strict;
use CGI qw( -compile );
use CGI::Cookie;
use FreezeThaw qw( thaw );
use HTTP::BrowserDetect;
use IO::File;
use Carp qw(cluck croak carp confess longmess );
use LWP::UserAgent;
use HTTP::Request;
use Template::Document;
use Time::HiRes;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Client;

use Para::Frame::Reload;
use Para::Frame::Cookies;
use Para::Frame::Session;
use Para::Frame::Result;
use Para::Frame::Child;
use Para::Frame::Child::Result;
use Para::Frame::Site;
use Para::Frame::Change;
use Para::Frame::URI;
use Para::Frame::CGI;
use Para::Frame::L10N qw( loc );
use Para::Frame::Logging;
use Para::Frame::Connection;
use Para::Frame::Uploaded;
use Para::Frame::Request::Response;
use Para::Frame::Renderer::HTML_Fallback;

use Para::Frame::Utils qw( compile throw debug catch idn_decode
                           datadump create_dir client_send );

our %URI2FILE;

#######################################################################

=head1 DESCRIPTION

Para::Frame::Request is the central class for most operations. The
current request object can be reached as C<$Para::Frame::REQ>.

=cut


#######################################################################

=head2 new

=cut

sub new
{
    my( $class, $reqnum, $client, $recordref ) = @_;

    my( $value ) = thaw( $$recordref );
    my( $params, $env, $orig_url_string, $orig_filename, $content_type, $dirconfig, $header_only, $files ) = @$value;

    # Modify $env for non-mod_perl mode
    $env->{'REQUEST_METHOD'} = 'GET';
    delete $env->{'MOD_PERL'};

    if( $Para::Frame::REQ )
    {
	# Detatch previous %ENV
	$Para::Frame::REQ->{'env'} = {%ENV};
    }

    %ENV = %$env;     # To make CGI happy

    # Turn back and make $env a ref to the actual %ENV symbol table
    # entry. This keeps them in sync
    #
    $env = \%ENV;

    my $q = Para::Frame::CGI->new($params);
    $q->cookie('password'); # Should cache all cookies

    my $req =  bless
    {
        resp            => undef,
	indent          => 1,              ## debug indentation
	client          => $client,
	jobs            => [],             ## queue of jobs to perform
        actions         => [],             ## queue of actions to perform
	'q'             => $q,
        'files'         => $files,         ## Uploaded files
	env             => $env,
	's'             => undef,          ## Session object
	lang            => undef,          ## Chosen language
	browser         => undef,          ## browser detection object
	result          => undef,
	orig_url_string => $orig_url_string,
        orig_url_params => $ENV{'QUERY_STRING'},
	orig_ctype      => $content_type,
        orig_resp       => undef,
        orig_page       => undef,          ## Original page requested
	referer         => $q->referer,    ## The referer of this page
	dirconfig       => $dirconfig,     ## Apache $r->dir_config
        page            => undef,          ## The page requested
	childs          => 0,              ## counter in parent
	in_yield        => 0,              ## inside a yield
	child_result    => undef,          ## the child res if in child
	reqnum          => $reqnum,        ## The request serial number
	wait            => 0,              ## Waiting for something else to finish
	cancel          => 0,              ## True if we should abort
	change          => undef,
        header_only     => $header_only,   ## true if only sending header
        site            => undef,          ## Default site for req
        in_loadpage     => 0,              ## client uses loadpage
        started         => Time::HiRes::time,
    }, $class;

    # Log some info
    warn "# http://".$req->http_host."$orig_url_string\n";

    # Handle Apache internal redirection
    if( my $redirect_uri = $ENV{REDIRECT_URL} || $ENV{'REDIRECT_SCRIPT_URI'} )
    {
	# Apache may set the file part to 'undefined'
	$redirect_uri =~ s(/undefined$)(/);
	warn "# Redirected from $redirect_uri\n";
	$req->{'orig_url_string'} = $redirect_uri;
	$req->{'orig_url_params'} = $ENV{'REDIRECT_QUERY_STRING'};

	unless( $q->param )
	{
	    $req->{'q'} = Para::Frame::CGI->new($req->{'orig_url_params'});
	}
    }


    return $req;
}


#######################################################################

=head2 get_by_id

=cut

sub get_by_id
{
    my( $class, $id ) = @_;

    $id or die "id missing";

    foreach my $req ( values %Para::Frame::REQUEST )
    {
	if( $req->{'reqnum'} == $id )
	{
	    return $req;
	}

	if( my $subreqs = $req->{'subrequest'} )
	{
	    foreach my $subreq ( @$subreqs )
	    {
		if( $subreq->{'reqnum'} == $id )
		{
		    return $subreq;
		}
	    }
	}

    }

    return undef;
}


#######################################################################

=head2 init

=cut

sub init
{
    my( $req ) = @_;

    # Ingore this req if we are in TERMINATE mode unless its a dependant subrequest or waiting for loadpage
    if( $Para::Frame::TERMINATE and not $req->q->param('req') and not $req->q->param('reqnum') )
    {
	debug "In TERMINATE!";
	client_send($req->client, "RESTARTING\x001\n");
	return 0;
    }
    elsif( $Para::Frame::LEVEL > 20 and not $req->q->param('req') and not $req->q->param('reqnum') )
    {
	debug "OVERLOADED!";
	client_send($req->client, "RESTARTING\x001\n");
	return 0;
    }

    my $env = $req->{'env'};

    ### Further initialization that requires $REQ
    $req->{'cookies'} = Para::Frame::Cookies->new($req);

    if( $env->{'HTTP_USER_AGENT'} )
    {
	local $^W = 0;
	$req->{'browser'} = new HTTP::BrowserDetect($env->{'HTTP_USER_AGENT'});
    }
    $req->{'result'}  = Para::Frame::Result->new();  # Before Session

    $req->set_site or return undef;
    $req->set_language;   # Needs site
#    $req->setup_jobs;
#    $req->reset_response; # Needs lang and jobs

    # Needs site
    $req->{'s'}       = Para::Frame->Session->new($req);


#    $req->{'s'}->route->init;

    return 1;
}


#######################################################################


=head2 new_subrequest

  $req->new_subrequest( \%args, \&code, @params )

Sets up a subrequest using L</new_minimal>.

=over

=item We switch to the new request

=item calls the C<&code> (in scalar context) with the req as the first param, followed by C<@params>

=item switch back to the callng request

=item returns the first of the returned values

=back

args:

  site: A L<Para::Frame::Site> object. If defined, and the host
differs from that of the current request, we sets ut a background
request that can be used to query apache about uri2file translations.

  user: A L<Para::Frame::User> object. Defaults to the current user.


A subrequest must make sure that it finishes BEFORE the parent, unless
it is decoupled to become a background request.

The parent will be made to wait for the subrequest result. But if the
subrequest sets up additional jobs, you have to take care of either
makeing it a background request or making the parent wait.

We creates the new request with L</new_minimal> and sends the
C<\%args> to L</minimal_init>.

=cut

sub new_subrequest
{
    my( $original_req, $args, $coderef, @params ) = @_;

    my $client = $original_req->client;

    $Para::Frame::REQNUM ++;

    if( my $site_in = $args->{'site'} )
    {
	my $site = $Para::Frame::CFG->{'site_class'}->get( $site_in );
	debug "new_subrequest in site ".$site->desig;
	if( $original_req->site->host ne $site->host )
	{
#	    debug "Host mismatch ".$site->host;
#	    debug "Changing the client of the subrequest";
	    $client = "background-$Para::Frame::REQNUM";
	}
    }

    $args->{'user'} ||= $original_req->user;
    my $req = Para::Frame::Request->new_minimal($Para::Frame::REQNUM, $client);

    $req->{'original_request'} = $original_req;
    $original_req->{'wait'} ++; # Wait for subreq
    $original_req->{'subrequest'} ||= [];
    push @{$original_req->{'subrequest'}}, $req;

    debug 2, "$original_req->{reqnum} now waits on $original_req->{'wait'} things";
    Para::Frame::switch_req( $req, 1 );
    warn "\n$Para::Frame::REQNUM Starting subrequest\n";

    ### Register the client, if it was created now
    #
    # This only registrer background requests. Other subrequests are
    # not registred
    #
    $Para::Frame::REQUEST{$client} ||= $req;
    $Para::Frame::RESPONSE{$client} ||= [];

    $req->minimal_init( $args ); ### <<--- INIT


    my $res = eval
    {
	&$coderef( $req, @params );
    };

    my $err = catch($@);

    $original_req->{'wait'} --;
    debug 2, "$original_req->{reqnum} now waits on $original_req->{'wait'} things";
    Para::Frame::switch_req( $original_req );

    # Merge the subrequest result with our result
    $original_req->result->incorporate($req->result);

    # The subreq may still have som jobs to do. Usually a job was
    # added to release active requests. I.e. release_active_request()


    if( $err )
    {
	die $err; # Subrequest failed
    }

    return $res;
}

#######################################################################

=head2 release_subreq

=cut

sub release_subreq
{
    my( $original_req, $req ) = @_;

    my @subreq;
    foreach my $sreq ( @{$original_req->{'subrequest'} ||=[]} )
    {
	if( $sreq->id != $req->id )
	{
	    push @subreq, $req;
	}
    }

    $original_req->{'subrequest'} = \@subreq;
}


#######################################################################


=head2 new_bgrequest

Sets up a background request using new_minimal

=cut

sub new_bgrequest
{
    my( $class, $msg ) = @_;

    $msg ||= "Handling new request (in background)";
    $Para::Frame::REQNUM ++;
    my $client = "background-$Para::Frame::REQNUM";
    my $req = Para::Frame::Request->new_minimal($Para::Frame::REQNUM, $client);
    $Para::Frame::REQUEST{$client} = $req;
    $Para::Frame::RESPONSE{$client} = [];
    Para::Frame::switch_req( $req, 1 );
    warn "\n\n$Para::Frame::REQNUM $msg\n";
    $req->minimal_init;
    return $req;
}


#######################################################################


=head2 new_minimal

Used for background jobs, without a calling browser client

=cut

sub new_minimal
{
    my( $class, $reqnum, $client ) = @_;

    my $req =  bless
    {
     indent         => 1,	## debug indentation
     client         => $client,	## Just the unique name
     jobs           => [],	## queue of actions to perform
     actions        => [],	## queue of actions to perform
     env            => {},	## No env for minimals!
     's'            => undef,	## Session object
     result         => undef,
     dirconfig      => {},	## Apache $r->dir_config
     childs         => 0,	## counter in parent
     in_yield       => 0,	## inside a yield
     child_result   => undef,	## the child res if in child
     reqnum         => $reqnum,	## The request serial number
     wait           => 0,	## Asked to wait?
     site           => undef,	## Default site for req
     started        => Time::HiRes::time,
    }, $class;

    $req->{'params'} = {%$Para::Frame::PARAMS};

    $req->{'result'}  = Para::Frame::Result->new($req);  # Before Session
    $req->{'s'}       = Para::Frame->Session->new_minimal();
    $req->{'q'}       = CGI->new({});


    return $req;
}


#######################################################################


=head2 minimal_init

  $req->minimal_init( \%args )

Initializes the L</new_minimal> request. A smaller version of L<init>.

args:

  site: The site for the request, set by L</set_site>. Optional.

  language: The language for the request, set by L</set_language>,
that will use a default if no input.

  user: The L<Para::Frame::User> to be in this request. Defaults to
using L<Para::Frame/bg_user_code> for getting the user.

Returns: The request

=cut

sub minimal_init
{
    my( $req, $args ) = @_;

    my $site_in = $args->{'site'};
    unless( $site_in )
    {
	if( $req->is_from_client )
	{
	    $site_in = $req->dirconfig->{'site'} || $req->host_from_env;
	}
	else
	{
	    $site_in = 'default';
#	    cluck "Site not set! Using default";
	}
    }
    $req->set_site( $site_in );

    $req->set_language( $args->{'language'} );


    my $user_class = $Para::Frame::CFG->{'user_class'};
    my $bg_user = $args->{'user'} || &{ $Para::Frame::CFG->{'bg_user_code'} };
    $user_class->change_current_user($bg_user);

    return $req;
}


#######################################################################

=head2 id

  $req->id

Returns the request number

=cut

sub id
{
    return $_[0]->{'reqnum'};
}

#######################################################################


=head2 q

  $req->q

Returns the L<CGI> object.

=cut

sub q { shift->{'q'} }

#######################################################################


=head2 session

  $req->session

Returns the L<Para::Frame::Session> object.

=cut

sub s { shift->{'s'} }             ;;## formatting
sub session { shift->{'s'} }

#######################################################################


=head2 env

  $req->env

Returns a hashref of the environment variables passed given by Apache
for the request.

=cut

sub env { shift->{'env'} }

#######################################################################


=head2 client

  $req->client

Returns the object representing the connection to the client that made
this request. The stringification of this object is used as a key in
several places.

=cut

sub client { shift->{'client'} }


#######################################################################

=head2 cookies

  $req->cookies

Returns the L<Para::Frame::Cookies> object for this request.

=cut

sub cookies { shift->{'cookies'} }


#######################################################################

=head2 result

  $req->result

Returns the L<Para::Frame::Result> object for this request.

=cut

sub result
{
    ref $_[0]->{result} or confess "The request doesn't have a result object ($_[0]->{result})";
    return $_[0]->{'result'};
}


#######################################################################

=head2 language

  $req->language

Returns the L10N language handler object.

=cut

sub lang { return $_[0]->language }
sub language
{
    return $_[0]->{'lang'} or croak "Language not initialized";
}


#######################################################################

=head2 set_language

  $req->set_language()

  $req->set_language( $language_in )

This is called during the initiation of the request.

Calls L<Para::Frame::L10N/set> or a subclass theriof defined in
L<Para::Frame/l10n_class>.

=cut

sub set_language
{
    my( $req, $language_in, $args ) = @_;

    $args ||= {};

    $args->{'req'} = $req;

#    debug "Setting language";
    $req->{'lang'} = $Para::Frame::CFG->{'l10n_class'}->
      set( $language_in, $args )
	or die "Couldn't set language";
}


#######################################################################


=head2 response

  $req->response

Returns the L<Para::Frame::Request::Response> object.

=cut

sub response
{
    return $_[0]->{'resp'} || confess "Response not set";
}


#######################################################################

=head2 response_if_existing

=cut

sub response_if_existing
{
    return $_[0]->{'resp'};
}


#######################################################################


=head2 page

  $req->page

Returns a L<Para::Frame::File> object from
L<Para::Frame::Request::Response/page>.

=cut

sub page
{
    return $_[0]->response->page || confess "Page not set";
}


#######################################################################

=head2 original

  $req->original

If this is a subrequest; return the original request.

=cut

sub original
{
    return $_[0]->{'original_request'};
}


#######################################################################

=head2 equals

  $req->equals( $req2 )

Returns true if the two requests are the same.

=cut

sub equals
{
    return( $_[0]->{'reqnum'} == $_[1]->{'reqnum'} );
}


#######################################################################

=head2 user

  $req->user

Returns the L<Para::Frame::User> object. Or probably a object of a
subclass of that class.

This is short for calling C<$req-E<gt>session-E<gt>user>

Returns undef if the request doesn't have a session.

=cut

sub user
{
    return undef unless $_[0]->{'s'};
    return shift->session->user;
}


#######################################################################

=head2 require_root_access

  $req->require_root_access

Throws a C<denied> exception if the current user hasn't root access

=cut

sub require_root_access
{
    my $user = $_[0]->user;
    unless( $user->has_root_access )
    {
	throw( 'denied', loc("Permission denied") );
    }
    return 1;
}


#######################################################################

=head2 change

  $req->change

Returns the L<Para::Frame::Change> object for this request.

=cut

sub change
{
    return $_[0]->{'change'} ||= Para::Frame::Change->new();
}


#######################################################################

=head2 is_from_client

  $req->is_from_client

Returns true if this request is from a client and not a bacground
server job or something else.

=cut

sub is_from_client
{
    return $_[0]->{'env'}{'REQUEST_METHOD'} ? 1 : 0;
}


#######################################################################

=head2 dirconfig

  $req->dirconfig

Returns the dirconfig hashref. See L<Apache/SERVER CONFIGURATION
INFORMATION> C<dir_config>.

Params:

C<site>: Used by L<Para::Frame::Request/reset_response>. If
C<site> is set to C<ignore>, the L<Para::Frame::Client> will decline
all requests and let thenext apache handler take care of it.

C<action>: Used by L</setup_jobs>

C<port>: Used by L<Para::Frame::Client>

C<backup_port>: Used by L<Para::Frame::Client>

C<backup_redirect>: Used by L<Para::Frame::Client>

C<backup>: Used by L<Para::Frame::Client>

C<find>: Used by L<Para::Frame::File/template>

C<loadpage>: Used by L<Para::Frame/handle_request>. If C<loadpage> is
set to C<no>, a loadpage will not be sent.

=cut

sub dirconfig
{
    return $_[0]->{'dirconfig'};
}


#######################################################################


=head2 browser

  $req->browser

Returns the L<HTTP::BrowserDetect> object for the request.

=cut

sub browser
{
    return $_[0]->{'browser'};
}


#######################################################################

=head2 header_only

=cut

sub header_only { $_[0]->{'header_only'} }


#######################################################################

=head2 set_header_only

=cut

sub set_header_only
{
    my( $req, $val ) = @_;
    if( defined $val )
    {
	return $_[0]->{'header_only'} = $val;
    }
    return $_[0]->{'header_only'};
}



#######################################################################

=head2 uploaded

  $req->uploaded( $filefiled )

Calls L<Para::Frame::Uploaded/new>

=cut

sub uploaded { Para::Frame::Uploaded->new($_[1]) }



#######################################################################

=head2 in_yield

  $req->in_yield

Returns true if this request has yielded for another request, or for
reading from the socket

=cut

sub in_yield
{
    return $_[0]->{'in_yield'};
}


#######################################################################

=head2 uri2file

  $req->uri2file( $url )

  $req->uri2file( $url, $file )

  $req->uri2file( $url, undef, $return_partial )

This does the Apache URL to filename translation

Directory URLs must end in '/'. The URL '' is not valid.

The answer is cached. Remove an url from the cache with
L<uri2file_clear>.

If given a C<$file> uses that as a translation and caches is.

(This method may have to create a pseudoclient connection to get the
information.)

If C<$return_partial> is true, we will return a part of the path
instead of throwing an exception.

Returns:

The file WITH '/' for dirs (NB! CHANGED)

Exceptions:

Throws a notfound exception if translation results in a file where the
last part differs from the one sent in. That would be the case when
the directory doesn't exist or for unsupported url translations.

=cut

sub uri2file
{
    my( $req, $url, $file, $may_not_exist ) = @_;

    $url =~ s/\?.*//; # Remove query part if given
    my $key = $req->host . $url;

    if( $file )
    {
#	confess "DEPRECATED";
	debug 5, "Storing URI2FILE in key $key: $file";
	return $URI2FILE{ $key } = $file;
    }

    if( $file = $URI2FILE{ $key } )
    {
#	debug "Return  URI2FILE for    $key: $file";
	return $file;
    }

    confess "url missing" unless defined $url;

    if( $url =~ m/^\/var\/ttc\// )
    {
	debug "The ttc dir shoule not reside inside a site docroot";
    }

#    warn "    From client\n";
    $file = $req->get_cmd_val( 'URI2FILE', $url );


#    # To be backward compatible, remove the last slash from client
#    # response
#    #
#    $file =~ s/\/$//;

    debug(5, "Storing URI2FILE in key $key: $file");
    $URI2FILE{ $key } = $file;
    return $file;
}


#######################################################################

=head2 uri2file_clear

  $req->uri2file( $url )

  $req->uri2file()

Clears the C<$url> from the cache for the C<$req> host.

With no C<$url>, clear all uris from the cache.

=cut

sub uri2file_clear
{
    my( $req, $url ) = @_;

    if( $url )
    {
	my $key = $req->host . $url;

	delete $URI2FILE{ $key };
    }
    else
    {
	%URI2FILE = ();
    }
    return;
}



#######################################################################


=head2 normalized_url

  $req->normalized_url( $url )

  $req->normalized_url( $url, $params )

Gives the proper version of the URL. Ending index.tt will be
removed. This is used for redirecting (forward) the browser if
nesessary.

C<$url> must be the path part as a string.

params:

  no_check

Returns:

  the path part as a string

=cut

sub normalized_url
{
    my( $req, $url, $params ) = @_;

    unless( defined $url )
    {
	confess "deprecated";
    }

    $params ||= {};

#    debug "Normalizing $url";

    if( $params->{keep_langpart} )
    {
	$url =~ s/\/index.tt(\?.*)?$/\/$1/;
    }
    else
    {
	$url =~ s/\/index(\.\w{2})?\.tt(\?.*)?$/\/$2/ or
	  $url =~ s/\.\w{2}\.tt(\?.*)?$/.tt$1/;

    }



    unless( $params->{no_check} )
    {
	my $url_file = $req->uri2file( $url );

	if( -d $url_file and $url !~ /\/(\?.*)?$/ )
	{
	    $url =~ s/\?/\/?/
	      or $url .= '/';
	    return $url;
	}
    }

#    debug "Normal   url: $url";
    return $url;
}

#######################################################################

=head2 setup_jobs

  $req->setup_jobs()

Set up things from params.

=cut

sub setup_jobs
{
    my( $req ) = @_;

    my $q = $req->q;

    # Setup actions
    my $actions = [];
    if( $req->{'dirconfig'}{'action'} )
    {
	push @$actions, $req->{'dirconfig'}{'action'};
    }
    foreach my $run_str ( $q->param('run') )
    {
	foreach my $run ( split /&/, $run_str )
	{
	    push @$actions, $run;
#	    $req->add_job('run_action', $run);
	}
    }
    # We will not execute later actions if one of them fail
    $req->{'actions'} = $actions;
#    cluck "Actions are now ".datadump($actions); ### DEBUG
}


#######################################################################

=head2 add_action

=cut

sub add_action
{
    my( $req ) = shift;
    debug(2,"Added action @_ for $req->{reqnum}");
    push @{ $req->{'actions'} }, @_;
    if( $req->in_last_job )
    {
	$req->add_job('after_jobs');
    }
}


#######################################################################

=head2 prepend_action

=cut

sub prepend_action
{
    my( $req ) = shift;
#    debug("====> Prepended action @_ for $req->{reqnum}");
    unshift @{ $req->{'actions'} }, @_;
    if( $req->in_last_job )
    {
	$req->add_job('after_jobs');
    }
#    debug "Jobs: @{${$req->{'jobs'}}[0]}";
#    debug "ACTIONS: @{ $req->{'actions'} }";

}


#######################################################################

=head2 add_job

=cut

sub add_job
{
    debug(5,"Added the job $_[1] for $_[0]->{reqnum}");
    push @{ shift->{'jobs'} }, [@_];
}


#######################################################################

=head2 add_background_job

  $req->add_background_job( $label, \&code, @params )

Runs the C<&code> in the background with the given C<@params>.

C<$label> is used for keeping metadata about what jobs are in queue.

Background jobs are done B<in between> regular requests.

The C<$req> is given as the first param.

Example:

  my $idle_job = sub
  {
      my( $req, $thing ) = @_;
      debug "I'm idling now like a $thing...";
  };
  $req->add_background_job( 'ideling', $idle_job, 'Kangaroo' );

=cut

sub add_background_job
{
    debug(5,"Added the background job $_[1] for $_[0]->{reqnum}");
    push @Para::Frame::BGJOBS_PENDING, [@_];
}


#######################################################################

=head2 run_code

  $req->run_code( $label, $codered, @args )

=cut

sub run_code
{
    my( $req, $label, $coderef ) = (shift, shift, shift );
    # Add this job to run given code

    my $res;
    eval
    {
	$res = &{$coderef}($req, @_) ;
    };
    if( $@ )
    {
	my $err = catch($@);
	debug(0,"RUN CODE FAILED");
	debug(0,$err->as_string);
	Para::Frame->run_hook($req, 'on_error_detect',
			      \ $err->type, \ $err->info );
	return 0;
    };
    return $res;
}


#######################################################################

=head2 run_action

=cut

sub run_action
{
    my( $req, $run, @args ) = @_;

    return 1 if $run eq 'nop'; #shortcut

#    debug "==> RUN ACTION $run";

    my $site = $req->site;
    debug 2, "Site appbase is ".$site->appbase;

    my $actionroots = [$site->appbase."::Action"];

    my $appfmly = $site->appfmly;

    foreach my $family ( @$appfmly )
    {
	push @$actionroots, "${family}::Action";
    }
    push @$actionroots, "Para::Frame::Action";

    my( $c_run ) = $run =~ m/^([\w\-]+)$/
	or do
    {
	debug "bad chars in run: $run";
	return 0;
    };
    debug(2,"Will now require $c_run");

    # Only keep error if all tries failed

    my( $actionroot, %errors );
    foreach my $tryroot ( @$actionroots )
    {
	my $path = $tryroot;
	$path =~ s/::/\//g;
	my $file = "$path/${c_run}.pm";
	debug(3,"testing $file",1);
	eval
	{
	    compile($file);
	    # exceptions will be rewritten: "Can't locate $filename: $@"
	};
	if( $@ )
	{
	    # What went wrong?
	    debug(3,$@);

	    if( $@ =~ /.*Can\'t locate (.*?) in \@INC/ )
	    {
		if( $1 eq $file )
		{
		    push @{$errors{'notfound'}}, "$c_run wasn't found in  $tryroot";
		    debug(-1);
		    next; # Try next
		}

		my $info = "";
		my $notfound = $1;
		if( $@ =~ /^BEGIN failed--compilation aborted at (.*?) line (\d+)/m )
		{
		    my $source_file = $1;
		    my $source_line = $2;

		    # Propagate error if no match
		    $source_file =~ /((?:\/[^\/]+){1,4})$/ or die;
		    my $part_path = $1;
		    $part_path =~ s/^\///;
		    $info .= "Problem in $part_path, row $source_line:\n";
		    $info .= "Can't find $notfound\n\n";
		}
		else
		{
		    debug(3,"Not matching BEGIN failed");
		    $info = $@;
		}
		push @{$errors{'compilation'}}, $info;
	    }
	    elsif( $@ =~ /(syntax error at .*?)$/m )
	    {
		debug(2,"Syntax error in require $file");
		push @{$errors{'compilation'}}, $1;
	    }
	    elsif( $@ =~ /^Can\'t locate $file/ )
	    {
		push @{$errors{'notfound'}}, "$c_run wasn't found in  $tryroot";
		debug(-1);
		next; # Try next
	    }
	    else
	    {
		debug(2,"Generic error in require $file");
		push @{$errors{'compilation'}}, $@;
	    }
	    debug(-1);
	    last; # HOLD IT
	}
	else
	{
	    $actionroot = $tryroot;
	    debug(-1);
	    last; # Success!
	}
	debug(-1);
    }


    if( not $actionroot )
    {
	debug(3,"ACTION NOT LOADED!");

	# Keep the error info from all failure
	foreach my $type ( keys %errors )
	{
	    my $info = "";
	    foreach my $result ( @{$errors{$type}} )
	    {
		$info .= $result. "\n";
	    }

	    if( $req->is_from_client )
	    {
		$req->result->exception([$type, $info]);
	    }

	    warn $info;
	}
	return 0; # Don't perform more actions
    };

    # Execute action
    #
    my @res;
    eval
    {
	debug(3,"using $actionroot",1);
	no strict 'refs';
	@res = &{$actionroot.'::'.$c_run.'::handler'}($req, @args);

	if( $Para::Frame::FORK )
	{
	    debug "  Fork failed to return result\n";
	    exit;
	}
	1;
    }
    or do
    {
	if( $Para::Frame::FORK )
	{
	    my $result = $req->{'child_result'};
	    $result->exception( $@ );
	    debug(0,"Fork child got EXCEPTION: $@");
	    $result->return;
	    exit;
	}

	# TODO: Use handle_error()

	debug(0,"ACTION FAILED!");
	debug(1,$@,-1);
	my $part = $req->result->exception;
	if( my $error = $part->error )
	{
	    if( $error->type eq 'denied' )
	    {
		if( $req->session->u->level == 0 )
		{
		    # Ask to log in
		    my $error_tt = "/login.tt";
		    $part->hide(1);
		    $req->session->route->bookmark;
		    my $home = $req->site->home_url_path;
		    $req->set_error_response( $home.$error_tt );
		}
	    }
	}
	return 0;
    };

    ### Other info is stored in $req->result->{'info'}
    $req->result->message( @res );

    debug(-1);
    return 1; # All OK
}


#######################################################################

=head2 after_jobs

=cut

sub after_jobs
{
    my( $req ) = @_;

#    debug 4, "In after_jobs";
#    debug "======> In after_jobs";
#    debug "ACTIONS: @{ $req->{'actions'} }";

    # Take a planned action unless an error has been encountered
    if( my $action = shift @{ $req->{'actions'} } )
    {
	unless( $req->result->errcnt )
	{
	    $req->run_action($action);
	    if( @{$req->{'actions'}} )
	    {
		$req->add_job('after_jobs');
	    }
	}
    }

    if( $req->in_last_job )
    {
	# Check for each thing. If more jobs, stop and add a new after_jobs

	### Waiting for children?
	if( $req->{'wait'} )
	{
	    # Waiting for something else to finish...
	    debug 5, "$req->{reqnum} stays open, was asked to wait for $req->{'wait'} things";
	    $req->add_job('after_jobs');
	}
	elsif( $req->{'childs'} )
	{
	    debug(2,"Waiting for childs");

	    # Remember to come back then done
	    $req->{'on_last_child_done'} = "after_jobs";
	    return;
	}

	### Do pre backtrack stuff
	if( $req->cancelled )
	{
	    throw('cancel', "Request cancelled. Stopping jobs");
	}
	### Do backtrack stuff
	$req->error_backtrack or
	    $req->session->route->check_backtrack;
	### Do last job stuff
    }

    # Backtracking could have added more jobs
    #
    if( $req->in_last_job )
    {
	# Redirection requestd?
	my $resp = $req->response; # May have changed
	if( $resp->is_no_error and $resp->redirection )
	{
 	    $resp->sender->send_redirection( $resp->redirection );
	    return $req->done;
	}


	Para::Frame->run_hook( $req, 'before_render_output');
	$req->change->before_render_output;

#	#
#	debug "----> Resp $resp";
#	debug "----> Resp page is ".$resp->page->url_path;
#	debug "----> Resp page is ".$resp->renderer->page->url_path;
#	#


	# May be a custom renderer
	my $render_result = $resp->render_output();
	if( $req->cancelled )
	{
	    throw('cancel', "Request cancelled. Not sending page result");
	}

	# The renderer may have set a redirection page
	my $new_resp = $req->response; # May have changed
	if( $new_resp->redirection )
	{
	    $new_resp->sender->send_redirection( $new_resp->redirection );
	    return $req->done;
	}
	elsif( $resp ne $new_resp )
	{
	    # Let us redo the page rendering
	}
	elsif( $render_result )
	{
 	    $new_resp->sender->send_output;
	    return $req->done;
	}
	else
	{
	    $req->handle_error({ response => $new_resp });
	}

	$req->add_job('after_jobs');
    }

    return 1;
}


#######################################################################

=head2 done

=cut

sub done
{
    my( $req ) = @_;

    if( $req->is_from_client )
    {
	$req->session->after_request( $req );
    }

    # Redundant shortcut
    unless( $req->{'wait'} or
	    $req->{'childs'} or
	    @{$req->{'jobs'}} )
    {
#	warn "\nFinishing up $req->{reqnum}\n";
#
#	warn "wait\n" if $req->{'wait'};
#	warn "in_yield\n" if $req->{'in_yield'};
#
#	my $njobs = scalar @{$req->{'jobs'}};
#	warn "jobs: $njobs\n";
#	my $nactions = scalar @{$req->{'actions'}};
#	warn "actions: $nactions\n";
#
#	warn "childs\n" if $req->{'childs'};

	$req->run_hook('done');
	Para::Frame::close_callback($req->{'client'});
    }
    return;
}


#######################################################################

=head2 in_last_job

=cut

sub in_last_job
{
    return not scalar @{$_[0]->{'jobs'}};
}


#######################################################################

=head2 in_loadpage

=cut

sub in_loadpage
{
    return $_[0]->{'in_loadpage'};
}


#######################################################################

=head2 error_backtrack

=cut

sub error_backtrack
{
    my( $req ) = @_;

    if( $req->result->backtrack and not $req->error_page_selected )
    {
	debug(2,"Backtracking to previuos page because of errors");
	my $previous = $req->referer_path;
	if( $previous )
	{
	    $req->set_response( $previous );
	}
	return 1;
    }
    return 0;
}


#######################################################################

=head2 referer_path

  $req->referer_path

Returns the LOCAL referer. Just the path part. If the referer
was from another website, fall back to default.

(This gives the previous caller page)

Returns the URL path part as a string.

=cut

sub referer_path
{
    my( $req ) = @_;

    my $site = $req->site;

#    debug "LOOKING FOR A REFERER";

  TRY:
    {
	# Explicit caller_page could be given
	if( my $url = $req->q->param('caller_page') )
	{
	    debug 2, "Referer from caller_page";
	    return Para::Frame::URI->new($url)->path;
	}

	# The query could have been changed by route
	if( my $url = $req->q->referer )
	{
	    $url = Para::Frame::URI->new($url);
#	    debug "May use referer ".$url->as_string;
	    last if $url->host_port ne $req->host_with_port;

	    debug 2, "Referer from current http req ($url)";
	    return $url->path;
	}

	# The actual referer is more acurate in this order
	if( my $url = $req->{'referer'} )
	{
	    $url = Para::Frame::URI->new($url);
#	    debug "May use referer ".$url->as_string;
	    last if $url->host_port ne $req->host_with_port;

	    debug 2, "Referer from original http req";
	    return $url->path;
	}

#	# This could be confusing if several browser windows uses the same
#	# session
#	#
#	debug 1, "Referer from session";
#	return $req->session->referer->path if $req->session->referer;
    }

    debug 1, "Referer from default value";
    return $site->last_step if $site->last_step;

    # Last try. Should always be defined
    return $site->home->url_path_slash;
}



#######################################################################

=head2 referer_query

  $req->referer_query

Returns the escaped form of the query string.  Should give the same
result regardless of GET or POST was used.

Defaults to ''.

=cut

sub referer_query
{
    my( $req ) = @_;

  TRY:
    {
	# Explicit caller_page could be given
	if( my $url = $req->q->param('caller_page') )
	{
	    debug 2, "Referer query from caller_page";
	    return Para::Frame::URI->new($url)->query;
	}

	# The query could have been changed by route
	if( my $url = $req->q->referer )
	{
	    $url = Para::Frame::URI->new($url);
	    last if $url->host_port ne $req->host_with_port;

	    if( my(%query) = $url->query_form )
	    {
		unless( $query{'backtrack'} )
		{
		    debug 2, "Referer query from current http req";
		    my $query_string = $url->query;
		    debug "Returning query $query_string";
		    return $query_string;
		}
	    }
	}

	# The actual referer is more acurate in this order
	if( my $url = $req->{'referer'} )
	{
	    $url = Para::Frame::URI->new($url);
	    last if $url->host_port ne $req->host_with_port;

	    if( my(%query) = $url->query_form )
	    {
		unless( $query{'backtrack'} )
		{
		    debug 2, "Referer query from original http req";
		    my $query_string = $url->query;
		    debug "Returning query $query_string";
		    return $query_string;
		}
	    }
	}

	# This could be confusing if several browser windows uses the same
	# session
	#
	debug 1, "Referer query from session";
	return $req->session->referer->query if $req->session->referer;
    }

    debug 1, "Referer query from default value";
    return '';
}


#######################################################################

=head2 referer_with_query

  $req->referer_with_query

Returns referer with query string as a string.

This combines L</referer> and L</referer_query>.

=cut

sub referer_with_query
{
    my( $req ) = @_;

    if( my $query = $req->referer_query )
    {
	return $req->referer_path . '?' . $query;
    }
    else
    {
	return $req->referer_path;
    }
}



#######################################################################

=head2 send_to_daemon

=cut

sub send_to_daemon
{
    my( $req, $host_in, $code, $arg ) = @_;

    my $conn = Para::Frame::Connection->new( $host_in );
    my $val = $conn->get_cmd_val( $code, $arg );
    $conn->disconnect;
    return $val;
}


#######################################################################

=head2 send_code

=cut

sub send_code
{
    my $req = shift;

    # To get a response, use get_cmd_val()

#    Para::Frame::Logging->this_level(5);
    $_[1] ||= 1; # Must be at least one param
    debug( 5, "Sending  ".join("-", @_)." ($req->{reqnum}) ".$req->client);
#    debug sprintf "  at %.2f\n", Time::HiRes::time;

    if( $Para::Frame::FORK )
    {
	debug(2, "redirecting to parent");
	my $code = shift;
	my $port = $Para::Frame::CFG->{'port'};
	my $client = $req->client;
	debug(3, "  to $client");
	my $val = $client . "\x00" . shift;
	die "Too many args in send_code($code $val @_)" if @_;

	Para::Frame::Client::connect_to_server( $port );
	$Para::Frame::Client::SOCK or die "No socket";
	Para::Frame::Client::send_to_server($code, \$val);

	# Keep open the SOCK to get response later
	return;
    }

    my $client = $req->client;
    if( $client =~ /^background/ )
    {

	# We need to access Apache. We will now act as a browser in
	# order to give ouerself a client to send this command
	# to. This will be ... entertaining...

	debug 2, "Req $req->{reqnum} will now considering starting an UA";

	# Use existing
	$req->{'wait_for_active_reqest'} ||= 0;
	debug 2, "  It waits for $req->{'wait_for_active_reqest'} active requests";

	# Validate that the active request is alive
	if( my $areq = $req->{'active_reqest'} )
	{
	    if( $areq->cancelled )
	    {
		debug "Active request CANCELLED";
		debug "Releasing active_request $req->{'reqnum'}";
		debug "Removing the referens to that request";

		$areq->{'wait'} = 0;
		$req->{'wait_for_active_reqest'} = 0;
		delete $req->{'active_reqest'};
	    }
	    elsif( not $areq->client->connected )
	    {
		debug "Active request NOT CONNECTED anymore";
		debug "Releasing active_request $req->{'reqnum'}";
		debug "Removing the referens to that request";

		$areq->{'wait'} = 0;
		$req->{'wait_for_active_reqest'} = 0;
		delete $req->{'active_reqest'};
	    }
	}

	unless( $req->{'wait_for_active_reqest'} ++ )
	{
	    debug "  So we prepares for starting an UA";
	    debug "  Now it waits for 1 active request";


#	    debug longmess();

	    my $origreq = $req->{'original_request'};

	    my $site = $req->site;

	    my $webhost = $site->webhost;
	    my $webpath = $site->loopback;
	    my $scheme = 'http';
	    if( $site->port == 443 ) # HTTPS
	    {
		$scheme = 'https';
	    }

	    my $query = "run=wait_for_req&req=$client";
	    my $url = "$scheme://$webhost$webpath?$query";

	    my $ua = LWP::UserAgent->new( timeout => 60*60 );
	    my $lwpreq = HTTP::Request->new(GET => $url);

	    # Do the request in a fork. Let that req message us in the
	    # action wait_for_req

	    my $fork = $req->create_fork;
	    if( $fork->in_child )
	    {
		debug "About to GET $url";
		my $res = $ua->request($lwpreq);
		# Might get result because of a timeout

		if( debug > 1 )
		{
		    debug "  GOT result:";
		    debug $res->as_string;
		}
		$fork->return( $res );
	    }
	}

	# Wait for the $ua to connect and give us it's $req
	while( not $req->{'active_reqest'} )
	{
	    debug 3, "Got an active_reqest yet?";
	    $req->yield(1); # Give it some time to connect
	}

	# Got it! Now send the message
	#
	debug 2, "We got the active request $req->{'active_reqest'}{reqnum} now";
	my $aclient = $req->{'active_reqest'}->client;

#	debug "Sending  @_";
	client_send( $aclient, join( "\0", @_ ) . "\n" );

	# Set up release code
	$req->add_job('release_active_request');
    }
    else
    {
#	debug "Sending  @_";
	client_send( $client, join( "\0", @_ ) . "\n" );
    }
}


#######################################################################

=head2 release_active_request

=cut

sub release_active_request
{
    my( $req ) = @_;

    if( $req->{'wait_for_active_reqest'} > 0 )
    {
	$req->{'wait_for_active_reqest'} --;
	debug 2, "$req->{reqnum} is now waiting for one active req less";
    }

    if( $req->{'wait_for_active_reqest'} )
    {
	debug 2, "More jobs for active request ($req->{'wait_for_active_reqest'})";
    }
    else
    {
        debug 1, "Releasing active_request $req->{'active_reqest'}{'reqnum'}";
	$req->{'active_reqest'}{'wait'} --;
	debug 1, "That request is now waiting for $req->{'active_reqest'}{'wait'} things";

	debug 2, "Removing the referens to that request";
	delete $req->{'active_reqest'};
    }
}


#######################################################################

=head2 get_cmd_val

=cut

sub get_cmd_val
{
    my $req = shift;

    my $queue;
    $req->{'in_yield'} ++;

    eval
    {
	$req->send_code( @_ );
	Para::Frame::get_value( $req );

	# Something besides the answer may be waiting before the answer

	if( my $areq = $req->{'active_reqest'} )
	{
	    # We expects response in the active_request
	    $queue = $Para::Frame::RESPONSE{ $areq->client };
	    unless( $queue )
	    {
		throw('cancel', "request $areq->{reqnum} decomposed");
	    }
	}
	else
	{
	    $queue = $Para::Frame::RESPONSE{ $req->client };
	    unless( $queue )
	    {
		throw('cancel', "request $req->{reqnum} decomposed");
	    }
	}


	my $cnt = 1;
	while( not @$queue )
	{
	    if( $cnt >= 20 )
	    {
		debug "We can't seem to get that answer to our code";
		debug "code: @_";
		$req->cancel;
	    }

	    if( $req->{'cancel'} )
	    {
		throw('cancel', "request cancelled");
	    }

	    Para::Frame::get_value( $req );
	    $cnt ++;
	}
    };

    $req->{'in_yield'} --;

    die $@ if $@;
    return shift @$queue;
}


#######################################################################

=head2 may_yield

  $req->may_yield

  $req->may_yield( $wait )

Calls L</yield> only if there was more than 2 seconds since the last
yield.

For operations taking a lot of time, insert this in places there a
change of request is safe.

=cut

sub may_yield
{
    my( $req, $wait ) = @_;

    if( time - ($Para::Frame::LAST||0) > 2 )
    {
	$Para::Frame::REQ->yield( $wait );
    }
}


#######################################################################

=head2 yield

  $req->yield

  $req->yield( $wait )

This calls the main loop, changing all global variables if another
request is processed.  Then that request is done, we return. If there
was nothing to do, we will come back here quickly.

If C<$wait> is given, waits a maximum of that amount of time for
another request. Mostly to be used if we know that another request is
coming and we want that to be handled before we continue.

=cut

sub yield
{
    my( $req, $wait ) = @_;

    # In case there is an exception in main_loop()...
    eval
    {
	$req->{'in_yield'} ++;
	my $done = 0;

	while( not $done )
	{
	    # The reqnum param is just for getting it in backtrace
	    Para::Frame::main_loop( 1, $wait, $req->{'reqnum'} );
	    if( $req->{'cancel'} )
	    {
		$done = 1;
	    }
	    elsif( not $req->{'wait'} )
	    {
		$done = 1;
	    }
	    else
	    {
		$wait ||= 1; # Avoids crazy fast iterations
	    }
	}
    };
    if( $@ )
    {
	debug "ERROR IN YIELD: $@";
    }
    $req->{'in_yield'} --;

    if( $req->{'cancel'} ) # DEBUG
    {
	debug 2, "Should close down this req soon";
    }

    Para::Frame::switch_req( $req );

    if( $req->{'cancel'} )
    {
	throw('cancel', "request cancelled");
    }
}


#######################################################################

=head2 http_host

  $req->http_host

Returns the host name the client requested. It tells with which of the
alternatives names the site was requested. This string does not contain
'http://'.

=cut

sub http_host
{
    my $host = $ENV{HTTP_HOST} || $ENV{SERVER_NAME};

    $host =~ s/:\d+$//; # May be empty even if not port 80 (https)

    if( my $server_port = $ENV{SERVER_PORT} )
    {
	if( $server_port == 80 )
	{
	    return idn_decode( $host );
	}
	elsif( $server_port == 443 )
	{
	    return idn_decode( $host );
	}
	else
	{
	    return idn_decode( "$host:$server_port" );
	}
    }

    return undef;
}


#######################################################################

=head2 http_port

  $req->http_port

Returns the port the client used in this request.

=cut

sub http_port
{
    return $ENV{SERVER_PORT} || undef;
}


#######################################################################

=head2 http_scheme

  $req->http_scheme

Returns the scheme the client used in this request.

Either http or https

=cut

sub http_scheme
{
    if( $ENV{SERVER_PORT} == 443 )
    {
	return "https";
    }
    else
    {
	return "http";
    }
}


#######################################################################

=head2 http_if_modified_since

  $req->http_if_modified_since

Returns the time as an L<Para::Frame::Time> object.

If no such time was given with the request, returns undef.

=cut

sub http_if_modified_since
{
    if( my $val = $ENV{HTTP_IF_MODIFIED_SINCE} )
    {
	$val =~ s/;\s*length=\d+$//; # May be part of string
	return eval # Ignoring exceptions (returns undef)
	{
	    return Para::Frame::Time->get($val);
	}
    }
    return undef;
}


#######################################################################

=head2 client_ip

  $req->client_ip

Returns the ip address of the client as a string with dot-separated
numbers.

=cut

sub client_ip
{
    return $_[0]->env->{REMOTE_ADDR} || $_[0]->{'client'}->peerhost;
}


#######################################################################

=head2 set_site

  $req->set_site( $site )

Sets the site to use for this request.

C<$site> should be the name of a registred L<Para::Frame::Site> or a
site object.

The site must use the same host as the request.

The method works similarly to L<Para::Frame::File/set_site>

Returns: The site object

=cut

sub set_site
{
    my( $req, $site_in, $args ) = @_;

    my $site;
    if( $site_in )
    {
	$site = $Para::Frame::CFG->{'site_class'}->get( $site_in );
    }
    else
    {
	 $site = $Para::Frame::CFG->{'site_class'}->get_by_req( $req );
    }

    # Check that site matches the client
    #
    unless( $req->client =~ /^background/ )
    {
	if( my $orig = $req->original )
	{
	    my $orig_site = $orig->site;
	    unless( $orig_site->host eq $site->host )
	    {
		my $site_name = $site->name;
		my $site_host = $site->host;
		my $orig_name = $orig_site->name;
		my $orig_host = $orig_site->host;
		debug "Host mismatch";
		debug "orig site: $orig_host -> $orig_name";
		debug "New name : $site_host -> $site_name";
		confess "set_site called";
	    }
	}
	else
	{
	    unless( $site->host eq $req->host_from_env )
	    {
		my $site_name = $site->name;
		my $site_host = $site->host;
		my $req_site_name = $req->host_from_env;
		debug "Host mismatch";
		debug "Req site : $req_site_name";
		debug "New name : $site_host -> $site_name";
#		carp "set_site called";
		return undef;
	    }
	}
    }

    return $req->{'site'} = $site;
}


#######################################################################

=head2 site

  $req->site

The site for the request is used for actions.

It may not be the same as the site of the response page as given by
C<$req-E<gt>page-E<gt>site>. But will in most cases be the same since
it's set in the same way as the initial site for the response page.

But in some cases there will be no page (as for background jobs), and
thus no page site.

Make sure to set the request site along with the page site, if it's to
change and any futher actions in the request should use that new site.

Returns the L<Para::Frame::Site> object for this request.

=cut

sub site
{
    return $_[0]->{site};
}


#######################################################################

=head2 host_from_env

=cut

sub host_from_env
{
    # This is the host name as given in the apache config.
    my $port = $ENV{SERVER_PORT};

    cluck "No host info" unless $port;
    if( $port == 80 )
    {
	return $ENV{SERVER_NAME};
    }
    else
    {
	return sprintf "%s:%d", $ENV{SERVER_NAME}, $port;
    }
}


#######################################################################

=head2 host

  $req->host

Returns the host name used for accessing this host. Includes C<:$port>
if port differs from 80.

=cut

sub host # Inkludes port if not :80
{
    my( $req ) = @_;

    if( $ENV{SERVER_NAME} )
    {
	return $req->host_from_env;
    }
    else
    {
	return $req->site->webhost;
    }
}


#######################################################################

=head2 host_without_port

  $req->host_without_port

Returns the host name used for accessing this host, without the port
part.

=cut

sub host_without_port
{
    my( $req ) = @_;

    my $host = $req->host;
    $host =~ s/:\d+$//;
    return $host;
}


#######################################################################

=head2 host_with_port

  $req->host_with_port

Returns the host name used for accessing this host, with the port
part.

=cut

sub host_with_port
{
    my( $req ) = @_;

    my $host = $req->host;
    if( $host =~ /:\d+$/ )
    {
	return $host;
    }
    else
    {
	return $host.":80";
    }
}


#######################################################################

=head2 create_fork

  $req->create_fork

Creates a fork.

In PARENT, returns a L<Para::Frame::Child> object.

In CHILD, returnt a L<Para::Frame::Child::Result> object.

Then the child returns. The hook C<child_result> is runt with the
L<Para::Frame::Result> object as the param after C<$req>.

You must make sure to exit the child. This is supposed to be done by
the L<Para::Frame::Result/result> method.

The hook C<on_fork> is run in the CHILD just after the
L<Para::Frame::Result> object is created.

Example 1 uses L<Para::Frame::Child::Result/on_return>. Example 2 uses
L<Para::Frame::Child/yield>. The first method (example 1) is preferred
as it is safer and faster in certain cases.

Example 1:

  my $fork = $req->create_fork;
  if( $fork->in_child )
  {
      # Do the stuff...
      $fork->on_return('process_my_data');
      $fork->return($my_result);
  }
  return "";

  sub process_my_data
  {
      my( $result ) = @_;
      # Do more stuff
      return "All done now";
  }

Example 2:

  my $fork = $req->create_fork;
  if( $fork->in_child )
  {
      # Do the stuff...
      $fork->return($my_result);
  }
  $fork->yield; # let other requests run
  return $fork->result;

=cut

sub create_fork
{
    my( $req ) = @_;

    my $sleep_count = 0;
    my $pid;
    my $fh = new IO::File;

#    $fh->autoflush(1);
#    my $af = $fh->autoflush;
#    warn "--> Autoflush is $af\n";


    # Please no signals in the middle of the forking
    $SIG{CHLD} = 'DEFAULT';

    do
    {
	eval # May throw a fatal "Can't fork"
	{
	    $pid = open($fh, "-|");
	};
	unless( defined $pid )
	{
	    debug(0,"cannot fork: $!");
	    if( $sleep_count++ > 6 )
	    {
		$SIG{CHLD} = \&Para::Frame::REAPER;
		die "Realy can't fork! bailing out";
	    }
	    sleep 1;
	}
	$@ = undef;
    } until defined $pid;

    if( $pid )
    {
	### --> parent

	# Do not block on read, since we will try reading before all
	# data are sent, so that the buffer will not get full
	#
	$fh->blocking(0);

	my $child = $req->register_child( $pid, $fh );

	# Now we can turn the signal handling back on
	$SIG{CHLD} = \&Para::Frame::REAPER;

	# See if we got any more signals
	&Para::Frame::REAPER;
	return $child;
    }
    else
    {
	### --> child

	$Para::Frame::FORK = 1;
 	my $result = Para::Frame::Child::Result->new;
	$req->{'child_result'} = $result;
	$req->run_hook('on_fork', $result );
	return $result;
   }
}


#######################################################################

=head2 register_child

=cut

sub register_child
{
    my( $req, $pid, $fh ) = @_;

    return Para::Frame::Child->register( $req, $pid, $fh );
}


#######################################################################

=head2 get_child_result

=cut

sub get_child_result
{
    my( $req, $child, $length ) = @_;

    my $result;
    eval
    {
	$result = $child->get_results( $length );
    } or do
    {
	$req->result->exception;
	return 0;
    };

#    warn datadump $result;

    foreach my $message ( $result->message )
    {
	if( $req->is_from_client )
	{
	    $req->result->message( $message );
	}
	else
	{
	    debug $message;
	}
    }

    return 1;
}


#######################################################################

=head2 run_hook

=cut

sub run_hook
{
    Para::Frame->run_hook(@_);
}


#######################################################################

=head2 logging

=cut

sub logging
{
    return Para::Frame::Logging->new();
}


#######################################################################

=head2 waiting

=cut

sub waiting
{
    return $_[0]->{'wait'};
}


#######################################################################

=head2 nop

=cut

sub nop
{
    return 0;
}


#######################################################################

=head2 cancelled

=cut

sub cancelled
{
    return $_[0]->{'cancel'};
}


#######################################################################

=head2 active

=cut

sub active
{
    return $_[0]->{'active_reqest'};
}


#######################################################################

=head2 cancel

=cut

sub cancel
{
    my( $req ) = @_;

    return if $req->{'cancel'};

    debug(0,"CANCEL req $req->{reqnum}");

    $req->{'cancel'} = 1;

    if( $req->{'childs'} )
    {
	debug "  Killing req childs";
	foreach my $child ( values %Para::Frame::CHILD )
	{
	    my $creq = $child->req;
	    my $cpid = $child->pid;
	    if( $creq->{'reqnum'} == $req->{'reqnum'} )
	    {
		kill 9, $child->pid;
	    }
	}
	$req->{'childs'} = 0;
    }

    if( my $worker = $req->{'worker'} )
    {
	debug "  Killing worker";
	unless( $Para::Frame::WORKER{ $worker->pid } )
	{
	    # See REAPER. Worker may have died
	    debug sprintf "Req %d lost a worker", $req->id;
	}
	else
	{
	    kill 9, $worker->pid;
	}
	delete $req->{'worker'};
    }

    if( my $orig_req = $req->original )
    {
	$orig_req->cancel;
    }

    if( $req->{'wait'} > 0 )
    {
	foreach my $subreq ( @{$req->{'subrequest'}} )
	{
	    debug "A servant ($subreq->{reqnum}) of req $req->{reqnum} got cancelled";
	    debug "Both uses the same client. Cancel servant also";
	    $subreq->cancel;
	}

	foreach my $oreq ( values %Para::Frame::REQUEST )
	{
	    if( $oreq->active and ( $oreq->active->id == $req->id ) )
	    {
		# The common case: The active req created this request
		# in order to communicate with the client. If this rec
		# was cancelled it can't answer questions from the
		# active request.

		debug "A servant ($req->{'reqnum'}) of req $oreq->{'reqnum'} got cancelled";

		if( $oreq->cancelled )
		{
		    debug "Master req also cancelled";
		}
		else
		{
		    debug "Master may be in the middle of getting information  from this servant";
		    debug "Keep it alive a litle longer";
		    $req->{'wait'} = 1;
		}
	    }
	}
    }

    if( my $areq = $req->{'active_reqest'} )
    {
	debug "Master ($req->{'reqnum'} of active req $areq->{'reqnum'} got cancelled";

	debug "Cancelling servant";
	$areq->cancel;
	delete $req->{'active_reqest'};
    }

#    debug "This was a cancel at ".longmess;
}


#######################################################################

=head2 note

=cut

sub note
{
    my( $req, $note ) = @_;

    debug(0, $note);
    $note =~ s/\n/\\n/g;
    utf8::encode($note);

    my $creq = $req->original || $req; # client req
    if( $creq->is_from_client )
    {
	return $creq->send_code('NOTE', $note );
    }
    else
    {
	return $note;
    }
}


#######################################################################

=head2 set_page

=cut

sub set_page
{
    my( $req, $page_in ) = @_;

    my $page_old = $req->response->page;
    my $page_old_str = $page_old->sys_path_slash;
    my $page_new;

    if( ref $page_in )
    {
	$page_new = $page_in;
    }
    else
    {
	$page_new = Para::Frame::File->new({
					    url => $page_in,
					    site => $req->site,
					    file_may_not_exist => 1,
					   });
    }

    if( $page_new->sys_path_slash ne $page_old_str )
    {
	$req->set_response( $page_in );
    }
    else
    {
	$page_new = $page_old;
    }

    return $page_new;
}


#######################################################################

=head2 set_page_path

=cut

sub set_page_path
{
    my( $req, $path ) = @_;
    my $home_path = $req->site->home_url_path;
    return $req->set_page($home_path.$path);
}

#######################################################################

=head2 set_response_path

=cut

sub set_response_path
{
    my( $req, $path ) = @_;
    my $home_path = $req->site->home_url_path;
    return $req->set_response($home_path.$path);
}

#######################################################################

=head2 set_response

  $req->set_response( $url, \%args )

=cut

sub set_response
{
    my( $req, $url_in, $args ) = @_;

    my $url = $url_in;

    my $resp;
    $args ||= {};

    $args->{'req'} = $req;
    $args->{'url'} = $url_in;
    $args->{'site'} ||= $req->site;

    if( ref $url_in )
    {
	if( UNIVERSAL::isa($url_in, 'URI') )
	{
	    $args->{'url'} = $url_in->path;
	    if( my $hostname = $url_in->host )
	    {
		my $site = $Para::Frame::CFG->{'site_class'}->get_by_url($url_in);
		$args->{'site'} = $site;
	    }
	}
	elsif( UNIVERSAL::isa($url_in, 'Para::Frame::File') )
	{
	    # Assume a page obj
	    $args->{'url'} = $url_in->url_path_slash;
	    $args->{'site'} = $url_in->site;
	}
	else
	{
	    confess "URL $url_in not recognized";
	}
    }

    eval
    {
	$resp = $req->{'resp'} = Para::Frame::Request::Response->new($args);
	1;
    };
    if( $@ )
    {
	debug "ERROR DURING RESPONSE INIT:";
	debug $@;
	debug "Handling error:";

	$req->handle_error($args);
	$resp = $req->{'resp'}; # Changed in handle_error
    }

#    debug "Response set to ".$resp->desig;
    return $resp;
}


#######################################################################

=head2 set_error_response

=cut

sub set_error_response
{
    my( $req, $url_in, $args ) = @_;

    $args ||= {};
    $args->{'is_error_response'} = 1;

    return $req->set_response( $url_in, $args );
}


#######################################################################

=head2 set_error_response_path

=cut

sub set_error_response_path
{
    my( $req, $path, $args ) = @_;
    $args ||= {};
    $args->{'is_error_response'} = 1;
    my $home_path = $req->site->home_url_path;
    return $req->set_response($home_path.$path, $args);
}


#######################################################################

=head2 reset_response

  $req->reset_response()

Uses current L</page> if existing.

If this is the first time, sets the URL from the req as the original
page. The original page can be retrieved via L</original_response>.

Should be used if we may want to use another template based on a
changed language or something else in the context htat has changed.

Calls L</set_response> and returns that response.

=cut

sub reset_response
{
    my( $req ) = @_;

    my $args = {};
    my $url;

    # Clear out page2template cache
    $Para::Frame::REQ->{'file2template'} = {};

    if( my $resp = $req->{'resp'} )
    {
	$url = $resp->page->url_path_slash;
	return $req->set_response( $url, $args );
    }
    else
    {
	$url = $req->{'orig_url_string'};
	my $resp = $req->set_response( $url, $args );
	return $req->{'orig_resp'} = $resp;
    }
}


#######################################################################

=head2 error_page_selected

  $req->error_page_selected

True if an error page has been selected

=cut

sub error_page_selected
{
    return $_[0]->response->is_error_response;
}

#######################################################################


=head2 error_page_not_selected

  $req->error_page_not_selected

True if an error page has not been selected

=cut

sub error_page_not_selected
{
    return $_[0]->response->is_error_response ? 0 : 1;
}


#######################################################################

=head2 original_response

  $req->original_response

=cut

sub original_response
{
    return $_[0]->{'orig_resp'};
}


#######################################################################

=head2 original_url_string

  $req->original_url_string

=cut

sub original_url_string
{
    return $_[0]->{'orig_url_string'};
}


#######################################################################

=head2 original_url_params

  $req->original_url_params

The query string passed as part of the URL

Not including any POST data.

Returns: the unparsed string, after the '?', as given by
$ENV{'QUERY_STRING'}. Saved on Req startup.

=cut

sub original_url_params
{
    return $_[0]->{'orig_url_params'};
}


#######################################################################

=head2 original_content_type_string

=cut

sub original_content_type_string
{
    return $_[0]->{'orig_ctype'};
}


#######################################################################

=head2 handle_error

=cut

sub handle_error
{
    my( $req, $args_in ) = @_;

    $args_in ||= {};

    my( $resp, $rend, $url, $site, $http_status );

    if( $resp = $args_in->{'response'} )
    {
	$url = $resp->page->url_path_slash;
	$site = $resp->page->site;
	$rend = $resp->renderer_if_existing;
    }
    elsif( $url = $args_in->{'url'} )
    {
	$site = $req->site;
    }
    else
    {
	confess "Missing args ".datadump($args_in,2);
    }

    unless( $@ )
    {
	$@ = "No renderer result";
    }


    ##################
    debug $@;
    ##################

    my $part = $req->result->exception();
    my $error = $part->error;

    unless( $error )
    {
	confess "Failed to retrieve the error?!";
    }

    if( $part->view_context )
    {
	$part->prefix_message(loc("During the processing of [_1]",$url)."\n");
    }

    # May not be defined yet...
    my $new_resp = $req->{'resp'}; # May have change


    # Has a new response been selected
    if( $new_resp and $resp and ($new_resp ne $resp) )
    {
	# Let the $req->after_jobs() render the new response
	return 0;
    }

    my $error_tt; # A new page to render (the path string)

    if( $error->type eq 'file' )
    {
	if( $error->info =~ /not found/ )
	{
	    debug "Subtemplate not found";
	    $error_tt = '/page_part_not_found.tt';
	    if( $rend )
	    {
		my $incpathstring = join "", map "- $_\n", @{$rend->paths};
		$part->add_message(loc("Include path is")."\n$incpathstring");
	    }
	    $part->view_context(1);
	    $part->prefix_message(loc("During the processing of [_1]",$url)."\n");
	}
	else
	{
	    debug "Other template file error";
	    $part->type('template');
	    $error_tt = '/error.tt';
	}
	debug $error->as_string();
    }
    elsif( $error->type eq 'denied' )
    {
	if( $req->session->u->level == 0 )
	{
	    # Ask to log in
	    $error_tt = "/login.tt";
	    $req->result->hide_part('denied');
	    unless( $req->{'no_bookmark_on_failed_login'} )
	    {
		$req->session->route->bookmark();
	    }
	}
	else
	{
	    $error_tt = "/denied.tt";
	    $req->session->route->plan_next($req->referer_path);
	}
    }
    elsif( $error->type eq 'notfound' )
    {
	$error_tt = "/page_not_found.tt";
	$http_status = 404;
    }
    elsif( $error->type eq 'cancel' )
    {
	throw('cancel', "request cancelled");
    }
    else
    {
	$error_tt = '/error.tt';
    }

    debug "Setting error template to $error_tt";

    my $error_tt_template = $site->home->get_virtual($error_tt)->template;

    # Avoid recursive failure (only checks for TT renderer)
    if( $resp and $resp->renderer_if_existing and
	$resp->renderer->can('template')
      )
    {
	if( my $tmpl = $resp->renderer->template )
	{
	    my $tmpl_sys_base = $tmpl->sys_base;
	    my $error_sys_base = $error_tt_template->sys_base;
	    debug sprintf "Comparing %s with %s",
	      $tmpl_sys_base, $error_sys_base;
	    # Same error page again?
	    if($tmpl_sys_base eq $error_sys_base )
	    {
		my $args =
		{
		 resp => $resp,
		 req => $req,
		};
		my $err_rend = Para::Frame::Renderer::HTML_Fallback->new($args);
		$resp->set_renderer($err_rend);
		$resp->set_is_error;
		return 1;
	    }
	}
    }

    # default URL
    $url ||= $site->home->get_virtual($error_tt);

    my $args =
    {
     'template' => $error_tt_template,
     'is_error_response' => 1,
     'req' => $req,
     'url' => $url,
     'site' => $site,
    };
    $new_resp = $req->{'resp'} = Para::Frame::Request::Response->new($args);

    if( $http_status )
    {
	$new_resp->set_http_status(404);
    }

    debug "New response set with url $url";

    return 0;
}


#######################################################################

=head2 send_stored_result

=cut

sub send_stored_result
{
    my( $req, $key ) = @_;

    $key ||= $req->{'env'}{'REQUEST_URI'}
      || $req->original_url_string;

    debug 0, "Sending stored page result for $key";

    my $resp = $req->session->{'page_result'}{ $key };
    $req->{'resp'} = $resp;
    $resp->{'req'} = $req;
    $resp->send_stored_result;
    delete $req->session->{'page_result'}{ $key };

    return 1;
}


#######################################################################

=head2 server_report

=cut

sub server_report
{
    return Para::Frame->report();
}


#######################################################################

sub test_die
{
    croak "WILL DIE";
    return "you think?";
}


#######################################################################


#warn "Loaded  Para::Frame::Request\n";
1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>

=cut
