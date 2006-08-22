#  $Id$  -*-cperl-*-
package Para::Frame::Request;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Request class
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

Para::Frame::Request - The request from the client

=cut

use strict;
use CGI qw( -compile );
use CGI::Cookie;
use FreezeThaw qw( thaw );
use HTTP::BrowserDetect;
use IO::File;
use Carp qw(cluck croak carp confess );
use LWP::UserAgent;
use HTTP::Request;
use Template::Document;

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
use Para::Frame::Page;
use Para::Frame::Utils qw( compile throw debug catch idn_decode datadump );
use Para::Frame::L10N;
use Para::Frame::Logging;
use Para::Frame::Connection;
use Para::Frame::Uploaded;

our %URI2FILE;

#######################################################################

=head1 DESCRIPTION

Para::Frame::Request is the central class for most operations. The
current request object can be reached as C<$Para::Frame::REQ>.

=cut

#######################################################################


sub new
{
    my( $class, $reqnum, $client, $recordref ) = @_;

    my( $value ) = thaw( $$recordref );
    my( $params, $env, $orig_url, $orig_filename, $content_type, $dirconfig, $header_only, $files ) = @$value;

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
    # entry. This keeps them synced
    #
    $env = \%ENV;

    my $q = new CGI($params);
    $q->cookie('password'); # Should cache all cookies

    my $req =  bless
    {
	indent         => 1,              ## debug indentation
	client         => $client,
	jobs           => [],             ## queue of jobs to perform
        actions        => [],             ## queue of actions to perform
	'q'            => $q,
        'files'        => $files,         ## Uploaded files
	env            => $env,
	's'            => undef,          ## Session object
	lang           => undef,          ## Chosen language
	browser        => undef,          ## browser detection object
	result         => undef,
	orig_url       => $orig_url,
	orig_ctype     => $content_type,
	referer        => $q->referer,    ## The referer of this page
	dirconfig      => $dirconfig,     ## Apache $r->dir_config
        page           => undef,          ## The page requested
	childs         => 0,              ## counter in parent
	in_yield       => 0,              ## inside a yield
	child_result   => undef,          ## the child res if in child
	reqnum         => $reqnum,        ## The request serial number
	wait           => 0,              ## Asked to wait?
	cancel         => 0,              ## True if we should abort
	change         => undef,
        header_only    => $header_only,   ## true if only sending header
        site           => undef,          ## Default site for req
        in_loadpage    => 0,              ## client uses loadpage
    }, $class;

    # Cache uri2file translation
    $req->uri2file( $orig_url, $orig_filename, $req);

    # Log some info
    warn "# http://".$req->http_host."$orig_url\n";

    return $req;
}

#######################################################################


sub init
{
    my( $req ) = @_;

    my $env = $req->{'env'};

    ### Further initialization that requires $REQ
    $req->{'cookies'} = Para::Frame::Cookies->new($req);

    if( $env->{'HTTP_USER_AGENT'} )
    {
	local $^W = 0;
	$req->{'browser'} = new HTTP::BrowserDetect($env->{'HTTP_USER_AGENT'});
    }
    $req->{'result'}  = Para::Frame::Result->new();  # Before Session

    $req->{'page'}    = Para::Frame::Page->response_page($req);

    $req->{'site'}    = $req->{'page'}->site;

    $req->{'s'}       = Para::Frame->Session->new($req);

    $req->set_language;


    $req->{'s'}->route->init;
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
	my $site = Para::Frame::Site->get( $site_in );
	if( $original_req->site->host ne $site->host )
	{
	    debug "Host mismatch ".$site->host;
	    debug "Changing the client of the subrequest";
	    $client = "background-$Para::Frame::REQNUM";
	}
    }

    $args->{'user'} ||= $original_req->user;
    my $req = Para::Frame::Request->new_minimal($Para::Frame::REQNUM, $client);

    $req->{'original_request'} = $original_req;
    $original_req->{'wait'} ++; # Wait for subreq
    debug 2, "$original_req->{reqnum} now waits on $original_req->{'wait'} things";
    Para::Frame::switch_req( $req, 1 );
    warn "\n$Para::Frame::REQNUM Starting subrequest\n";

    ### Register the client, if it was created now
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

    if( $err )
    {
	die $err; # Subrequest failed
    }

    return $res;
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
    $req->minimal_init;
    warn "\n\n$Para::Frame::REQNUM $msg\n";
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
	indent         => 1,              ## debug indentation
	client         => $client,        ## Just the unique name
	jobs           => [],             ## queue of actions to perform
        actions        => [],             ## queue of actions to perform
	env            => {},             ## No env mor minimals!
	's'            => undef,          ## Session object
	result         => undef,
	childs         => 0,              ## counter in parent
	in_yield       => 0,              ## inside a yield
	child_result   => undef,          ## the child res if in child
	reqnum         => $reqnum,        ## The request serial number
	wait           => 0,              ## Asked to wait?
        site           => undef,          ## Default site for req
    }, $class;

    $req->{'params'} = {%$Para::Frame::PARAMS};

    $req->{'result'}  = Para::Frame::Result->new($req);  # Before Session
    $req->{'s'}       = Para::Frame->Session->new_minimal();

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

#    my $page = $req->{'page'} = Para::Frame::Page->new($req);

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
	    debug "Site not set! Using default";
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
#    carp "Returning language obj $_[0]->{'lang'}";
#    unless( UNIVERSAL::isa $_[0]->{'lang'},'Para::Frame::L10N')
#    {
#	croak "Lanugage obj of wrong type: ".datadump($_[0]->{'lang'});
#    }
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
    my( $req, $language_in ) = @_;

#    debug "Setting language";
    $req->{'lang'} = $Para::Frame::CFG->{'l10n_class'}->set( $language_in )
      or die "Couldn't set language";
}


#######################################################################


=head2 page

  $req->page

Returns the L<Para::Frame::Page> object.

=cut

sub page
{
    return $_[0]->{'page'} or confess "Page not set";
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
    return $_[0]->{'q'} ? 1 : 0;
}


#######################################################################

=head2 dirconfig

  $req->dirconfig

Returns the dirconfig hashref. See L<Apache/SERVER CONFIGURATION
INFORMATION> C<dir_config>.

Params:

C<site>: Used by L<Para::Frame::Page/response_page>. If C<site> is set
to C<ignore>, the L<Para::Frame::Client> will decline all requests and
let thenext apache handler take care of it.

C<action>: Used by L</setup_jobs>

C<port>: Used by L<Para::Frame::Client>

C<backup_port>: Used by L<Para::Frame::Client>

C<backup_redirect>: Used by L<Para::Frame::Client>

C<backup>: Used by L<Para::Frame::Client>


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

sub header_only { $_[0]->{'header_only'} }



#######################################################################

=head2 uploaded

  $req->uploaded( $filefiled )

Calls L<Para::Frame::Uploaded/new>

=cut

sub uploaded { Para::Frame::Uploaded->new($_[1]) }



#######################################################################

=head2 in_yield

  $req->in_yield

Returns true if some other request has yielded for this request.

=cut

sub in_yield
{
    return $_[0]->{'in_yield'};
}


#######################################################################

=head2 uri2file

  $req->uri2file( $url )

  $req->uri2file( $url, $file )

This does the Apache URL to filename translation

Directory URLs must end in '/'. The URL '' is not valid.

The answer is cached.

If given a C<$file> uses that as a translation and caches is.

(This method may have to create a pseudoclient connection to get the
information.)

=cut

sub uri2file
{
    my( $req, $url, $file ) = @_;

    # This will return file without '/' for dirs

    my $key = $req->host . $url;

    if( $file )
    {
#	debug "Storing URI2FILE in key $key: $file";
	return $URI2FILE{ $key } = $file;
    }

    if( $file = $URI2FILE{ $key } )
    {
#	debug "Return  URI2FILE for    $key: $file";
	return $file;
    }

    confess "url missing" unless $url;

#    warn "    From client\n";
    $file = $req->get_cmd_val( 'URI2FILE', $url );

    debug(4, "Storing URI2FILE in key $key: $file");
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

Gives the proper version of the URL. Ending index.tt will be
removed. This is used for redirecting (forward) the browser if
nesessary.

C<$url> must be the path part as a string.

Returns the path part as a string.

=cut

sub normalized_url
{
    my( $req, $url ) = @_;

    $url ||= $req->page->orig_url_path;

#    if( $url =~ s/\/index.tt$/\// )
    if( $url =~ s/\/index(\.\w{2,3})?\.tt$/\// )
    {
#	debug "Normal   url: $url";
	return $url;
    }

    my $url_file = $req->uri2file( $url );
    if( -d $url_file and $url !~ /\/(\?.*)?$/ )
    {
	$url =~ s/\?/\/?/
	    or $url .= '/';
#	debug "Normal   url: $url";
	return $url;
    }

#    debug "Normal   url: $url";
    return $url;
}

#######################################################################

=head2 setup_jobs

Set up things from params.

=cut

sub setup_jobs
{
    my( $req ) = @_;

    my $q = $req->q;

    # Custom renderer?
    $req->page->set_renderer( $q->param('renderer') );

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
#    warn "Actions are now ".datadump($actions);
}


#######################################################################

sub add_job
{
    debug(2,"Added the job $_[1] for $_[0]->{reqnum}");
    push @{ shift->{'jobs'} }, [@_];
}


#######################################################################

=head2 add_background_job

  $req->add_background_job( \&code, @params )

Runs the C<&code> in the background with the given C<@params>.

Background jobs are done B<in between> regular requests.

The C<$req> is given as the first param.

Example:

  my $idle_job = sub
  {
      my( $req, $thing ) = @_;
      debug "I'm idling now like a $thing...";
  };
  $req->add_background_job( $idle_job, 'Kangaroo' );

=cut

sub add_background_job
{
    debug(2,"Added the background job $_[1] for $_[0]->{reqnum}");
    push @Para::Frame::BGJOBS_PENDING, [@_];
}


#######################################################################

sub run_code
{
    my( $req, $coderef ) = (shift, shift );
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

sub run_action
{
    my( $req, $run, @args ) = @_;

    return 1 if $run eq 'nop'; #shortcut

    my $site = $req->site;

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
	};
	if( $@ )
	{
	    # What went wrong?
	    debug(3,$@);

	    if( $@ =~ /^Can\'t locate $file/ )
	    {
		push @{$errors{'notfound'}}, "$c_run hittades inte under $tryroot";
		debug(-1);
		next; # Try next
	    }
	    elsif( $@ =~ /^Can\'t locate (.*?) in \@INC/ )
	    {
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
		    $info .= "Problem i $part_path, rad $source_line:\n";
		    $info .= "Hittar inte $notfound\n\n";
		}
		else
		{
		    debug(3,"Not matching BEGIN failed");
		    $info = $@;
		}
		push @{$errors{'compilation'}}, $info;
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
	    $req->result->exception([$type, $info]);
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
	    warn "  Fork failed to return result\n";
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
		    $req->page->set_error_template( $error_tt );
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

sub after_jobs
{
    my( $req ) = @_;
    my $page = $req->page;

    debug 4, "In after_jobs";

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
	    debug 2, "$req->{reqnum} stays open, was asked to wait for $req->{'wait'} things";
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
	if( $page->error_page_not_selected and $page->redirection )
	{
	    $req->cookies->add_to_header;
 	    $page->output_redirection( $page->redirection );
	    return $req->done;
	}


	Para::Frame->run_hook( $req, 'before_render_output');

	my $render_result = 0;
	if( $page->renderer )
	{
	    # Using custom renderer
	    $render_result = &{$page->renderer}( $req );

	    # TODO: Handle error...
	}
	else
	{
	    $render_result = $page->render_output;
	}

	# The renderer may have set a redirection page
	if( $page->redirection )
	{
	    $req->cookies->add_to_header;
 	    $page->output_redirection( $page->redirection );
	    return $req->done;
	}
	elsif( $render_result )
	{
	    $req->cookies->add_to_header;
 	    $page->send_output;
	    return $req->done;
	}
	$req->add_job('after_jobs');
    }

    return 1;
}


#######################################################################

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

sub in_last_job
{
    return not scalar @{$_[0]->{'jobs'}};
}


#######################################################################

sub in_loadpage
{
    return $_[0]->{'in_loadpage'};
}


#######################################################################

sub error_backtrack
{
    my( $req ) = @_;
    my $page = $req->page;

    if( $req->result->backtrack and not $page->error_page_selected )
    {
	debug(2,"Backtracking to previuos page because of errors");
	my $previous = $req->referer;
	if( $previous )
	{
	    # It must be in the site dir
	    my $destroot = $page->site->home->sys_path;
	    my $dir = $req->uri2file( $previous );
	    unless( $dir =~ m/^$destroot/ )
	    {
		$previous = $page->site->home_url_path."/error.tt";
	    }

	    $page->set_template( $previous );

	    # It must be a template
	    unless( $page->url_path_tmpl =~ /\.tt/ )
	    {
		$previous = $page->site->home_url_path."/error.tt";
		$page->set_template( $previous );
	    }

	    debug(3,"Previous is $previous");
	}
	return 1;
    }
    return 0;
}


#######################################################################

=head2 referer

  $req->referer

Returns the LOCAL referer. Just the path part. If the referer
was from another website, fall back to default

Returns the URL path part as a string.

=cut

sub referer
{
    my( $req ) = @_;

    my $site = $req->page->site;

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
	    last if $url->host_port ne $req->host_with_port;

	    debug 2, "Referer from current http req ($url)";
	    return $url->path;
	}

	# The actual referer is more acurate in this order
	if( my $url = $req->{'referer'} )
	{
	    $url = Para::Frame::URI->new($url);
	    last if $url->host_port ne $req->host_with_port;

	    debug 2, "Referer from original http req";
	    return $url->path;
	}

	# This could be confusing if several browser windows uses the same
	# session
	#
	debug 1, "Referer from session";
	return $req->session->referer->path if $req->session->referer;
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

	    if( defined( my $query = $url->query) )
	    {
		debug 2, "Referer query from current http req ($query)";
		return $query;
	    }
	}

	# The actual referer is more acurate in this order
	if( my $url = $req->{'referer'} )
	{
	    $url = Para::Frame::URI->new($url);
	    last if $url->host_port ne $req->host_with_port;

	    if( defined(my $query = $url->query) )
	    {
		debug 2, "Referer query from original http req";
		return $query;
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
	return $req->referer . '?' . $query;
    }
    else
    {
	return $req->referer;
    }
}



#######################################################################

sub send_to_daemon
{
    my( $req, $host_in, $code, $arg ) = @_;

    my $conn = Para::Frame::Connection->new( $host_in );
    my $val = $conn->get_cmd_val( $code, $arg );
    $conn->disconnect;
    return $val;
}


#######################################################################

sub send_code
{
    my $req = shift;

    # To get a response, use get_cmd_val()

    $_[1] ||= 1; # Must be at least one param
    debug( 3, "Sending code: ".join("-", @_)." ($req->{reqnum}) ".$req->client);
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
	unless( $req->{'wait_for_active_reqest'} ++ )
	{
	    debug "  So we prepares for starting an UA";
	    debug "  Now it waits for 1 active request";

	    my $origreq = $req->{'original_request'};

	    my $site = $req->site;

	    my $webhost = $site->webhost;
	    my $webpath = $site->loopback;

	    my $query = "run=wait_for_req&req=$client";
	    my $url = "http://$webhost$webpath?$query";

	    my $ua = LWP::UserAgent->new;
	    my $lwpreq = HTTP::Request->new(GET => $url);

	    # Do the request in a fork. Let that req message us in the
	    # action wait_for_req

	    my $fork = $req->create_fork;
	    if( $fork->in_child )
	    {
		debug "About to GET $url";
		my $res = $ua->request($lwpreq);
		debug "  GOT result: $res";
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

	$aclient->send( join( "\0", @_ ) . "\n" );

	# Set up release code
	$req->add_job('release_active_request');
    }
    else
    {
	$client->send( join( "\0", @_ ) . "\n" );
    }
}


#######################################################################

sub release_active_request
{
    my( $req ) = @_;

    debug 2, "$req->{reqnum} is now waiting for one active req less";

    $req->{'wait_for_active_reqest'} --;

    if( $req->{'wait_for_active_reqest'} )
    {
	debug 2, "More jobs for active request ($req->{'wait_for_active_reqest'})";
    }
    else
    {
        debug 2, "Releasing active_request $req->{'active_reqest'}{'reqnum'}";
	$req->{'active_reqest'}{'wait'} --;
	debug 2, "That request is now waiting for $req->{'active_reqest'}{'wait'} things";

	debug 2, "Removing the referens to that request";
	delete $req->{'active_reqest'};
    }
}


#######################################################################

sub get_cmd_val
{
    my $req = shift;

    $req->send_code( @_ );
    Para::Frame::get_value( $req );

    # Something besides the answer may be waiting before the answer

    my $queue;
    if( my $areq = $req->{'active_reqest'} )
    {
	# We expects response in the active_request
	$queue = $Para::Frame::RESPONSE{ $areq->client };
	unless( $queue )
	{
	    throw('cancel', "request $areq->{reqnum} decomposed");
	}
#	debug "Looking for response in areq ".$areq->client;
    }
    else
    {
	$queue = $Para::Frame::RESPONSE{ $req->client };
	unless( $queue )
	{
	    throw('cancel', "request $req->{reqnum} decomposed");
	}
#	debug "Looking for response in req ".$req->client;
    }

    while( not @$queue )
    {
	if( $req->{'cancel'} )
	{
	    throw('cancel', "request cancelled");
	}
#	debug "No response registred. Getting next value:";
	Para::Frame::get_value( $req );
    }

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

    if( time - $Para::Frame::LAST > 2 )
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
	    unless( $req->{'wait'} )
	    {
		$done = 1;
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
    my( $req, $site_in ) = @_;

    $site_in or confess "site param missing";

    my $site = Para::Frame::Site->get( $site_in );

    # Check that site matches the client
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

  sub
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

    do
    {
	$pid = open($fh, "-|");
	unless( defined $pid )
	{
	    debug(0,"cannot fork: $!");
	    die "bailing out" if $sleep_count++ > 6;
	    sleep 1;
	}
    } until defined $pid;

    if( $pid )
    {
	### --> parent

	# Do not block on read, since we will try reading before all
	# data are sent, so that the buffer will not get full
	#
	$fh->blocking(0);

	return $req->register_child( $pid, $fh );
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

sub register_child
{
    my( $req, $pid, $fh ) = @_;

    return Para::Frame::Child->register( $req, $pid, $fh );
}


#######################################################################

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

sub run_hook
{
    Para::Frame->run_hook(@_);
}


#######################################################################

sub logging
{
    return Para::Frame::Logging->new();
}


#######################################################################

sub waiting
{
    return $_[0]->{'wait'};
}


#######################################################################

sub cancelled
{
    return $_[0]->{'cancel'};
}


#######################################################################

sub active
{
    return $_[0]->{'active_reqest'};
}


#######################################################################

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

    if( my $orig_req = $req->original )
    {
	$orig_req->cancel;
    }

    if( $req->{'wait'} )
    {
	foreach my $oreq ( values %Para::Frame::REQUEST )
	{
	    if( $oreq->original and ( $oreq->original->id == $req->id ) )
	    {
		$oreq->cancel;
	    }
	}
	$req->{'wait'} = 0;
    }

    if( $req->{'active_reqest'} )
    {
	$req->{'active_reqest'}->cancel;
	delete $req->{'active_reqest'};
    }

#    if( $req->{'in_yield'} )
#    {
#	debug "This req is in yield";
#    }
}


#######################################################################

sub note
{
    my( $req, $note ) = @_;

    debug($note);
    $note =~ s/\n/\\n/g;
    my $creq = $req->original || $req; # client req
    return $creq->send_code('NOTE', $note );
}


#######################################################################



1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>

=cut
