#  $Id$  -*-perl-*-
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
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
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
use Data::Dumper;
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
use Para::Frame::Utils qw( compile throw debug catch idn_decode );

our %URI2FILE;

=head1 DESCRIPTION

Para::Frame::Request is the central class for most operations. The
current request object can be reached as C<$Para::Frame::REQ>.

=cut

sub new
{
    my( $class, $reqnum, $client, $recordref ) = @_;

    my( $value ) = thaw( $$recordref );
    my( $params, $env, $orig_uri, $orig_filename, $content_type, $dirconfig ) = @$value;

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
	jobs           => [],             ## queue of actions to perform
	'q'            => $q,
	env            => $env,
	's'            => undef,          ## Session object
	lang           => undef,          ## Chosen language
	browser        => undef,          ## browser detection object
	result         => undef,
	orig_uri       => $orig_uri,
	orig_ctype     => $content_type,
	referer        => $q->referer,    ## The referer of this page
	dirconfig      => $dirconfig,     ## Apache $r->dir_config
        page           => undef,          ## The page requested
	childs         => 0,              ## counter in parent
	in_yield       => 0,              ## inside a yield
	child_result   => undef,          ## the child res if in child
	reqnum         => $reqnum,        ## The request serial number
	wait           => 0,              ## Asked to wait?
	cancel         => undef,          ## True if we should abort
	change         => undef,
    }, $class;

    # Cache uri2file translation
    $req->uri2file( $orig_uri, $orig_filename, $req);

    # Log some info
    warn "# http://".$req->http_host."$orig_uri\n";

    return $req;
}

sub init
{
    my( $req ) = @_;

#    debug "Initializing req";

    my $env = $req->{'env'};

    ### Further initialization that requires $REQ
    $req->{'cookies'} = new Para::Frame::Cookies($req);

    if( $env->{'HTTP_USER_AGENT'} )
    {
	$req->{'browser'} = new HTTP::BrowserDetect($env->{'HTTP_USER_AGENT'});
    }
    $req->{'result'}  = new Para::Frame::Result;  # Before Session
    $req->{'s'}       = Para::Frame->Session->new($req);

    $req->{'page'} = Para::Frame::Page->new();
    $req->{'page'}->init;

    $req->set_language;


    $req->{'s'}->route->init;
}


=head2 new_subrequest

Sets up a subrequest using new_minimal.

A subrequest must make sure that it finishes BEFORE the parent, unless
it is decoupled to become a background request.

The parent will be made to wait for the subrequest result. But if the
subrequest sets up additional jobs, you have to take care of either
makeing it a background request or making the parent wait.

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

    my $req = Para::Frame::Request->new_minimal($Para::Frame::REQNUM, $client);

    $req->{'original_request'} = $original_req;
    $original_req->{'wait'} ++; # Wait for subreq
    debug "$original_req->{reqnum} now waits on $original_req->{'wait'} things";
    Para::Frame::switch_req( $req, 1 );
    warn "\n$Para::Frame::REQNUM Starting subrequest\n";

    ### Register the client, if it was created now
    $Para::Frame::REQUEST{$client} ||= $req;

    $req->minimal_init( $args ); ### <<--- INIT


    my $res = eval
    {
	&$coderef( $req, @params );
    };

    my $err = catch($@);

    $original_req->{'wait'} --;
    debug "$original_req->{reqnum} now waits on $original_req->{'wait'} things";
    Para::Frame::switch_req( $original_req );

    if( $err )
    {
	debug "Got error from processing subrequest:\n";
	debug $err->as_string;

	die $err;
    }

    return $res;
}

=head2 new_minimal

Used for background jobs, without a calling browser client

=cut

sub new_minimal
{
    my( $class, $reqnum, $client ) = @_;

    my $req =  bless
    {
	client         => $client,        ## Just the unique name
	indent         => 1,              ## debug indentation
	jobs           => [],             ## queue of actions to perform
	env            => {},             ## No env mor minimals!
	's'            => undef,          ## Session object
	result         => undef,
	childs         => 0,              ## counter in parent
	in_yield       => 0,              ## inside a yield
	child_result   => undef,          ## the child res if in child
	reqnum         => $reqnum,        ## The request serial number
	wait           => 0,              ## Asked to wait?
    }, $class;

    $req->{'params'} = {%$Para::Frame::PARAMS};

    return $req;
}

sub minimal_init
{
    my( $req, $args ) = @_;

    $req->{'result'}  = new Para::Frame::Result;  # Before Session
    $req->{'s'}       = Para::Frame->Session->new_minimal();

    my $page = $req->{'page'} = Para::Frame::Page->new();
    if( my $site_in = $args->{'site'} )
    {
	$page->set_site( $site_in );
    }

    $req->set_language( $args->{'language'} );

    return $req;
}


#######################################################################

=head2 q

  $req->q

Returns the L<CGI> object.

=cut

sub q { shift->{'q'} }

=head2 session

  $req->session

Returns the L<Para::Frame::Session> object.

=cut

sub s { shift->{'s'} }
sub session { shift->{'s'} }

=head2 env

  $req->env

Returns a hashref of the environment variables passed given by Apache
for the request.

=cut

sub env { shift->{'env'} }

=head2 client

  $req->client

Returns the object representing the connection to the client that made
this request. The stringification of this object is used as a key in
several places.

=cut

sub client { shift->{'client'} }

=head2 cookies

  $req->cookies

Returns the L<Para::Frame::Cookies> object for this request.

=cut

sub cookies { shift->{'cookies'} }

=head2 result

  $req->result

Returns the L<Para::Frame::Result> object for this request.

=cut

sub result { shift->{'result'} }
sub uri { $_[0]->page->uri }

=head2 language

  $req->language

Returns a ref to a list of language code strings.  For example
C<['en']>. This is a prioritized list of languages that the sithe
handles and that the client prefere.

=cut

sub lang { $_[0]->{'lang'} }
sub language { $_[0]->{'lang'} }

=head2 page

  $req->page

Returns the L<Para::Frame::Page> object.

=cut

sub page
{
    return $_[0]->{'page'} or confess;
}

=head2 original

  $req->original

If this is a subrequest; return the original request.

=cut

sub original
{
    return $_[0]->{'original_request'};
}

=head2 equals

  $req->equals( $req2 )

Returns true if the two requests are the same.

=cut

sub equals
{
    return( $_[0]->{'reqnum'} == $_[1]->{'reqnum'} );
}

=head2 user

  $req->user

Returns the L<Para::Frame::User> object. Or probably a object of a
subclass of that class.

This is short for calling C<$req-E<gt>session-E<gt>user>

=cut

sub user
{
    return shift->session->user;
}

=head2 change

  $req->change

Returns the L<Para::Frame::Change> object for this request.

=cut

sub change
{
    return $_[0]->{'change'} ||= Para::Frame::Change->new();
}

=head2 is_from_client

  $req->is_from_client

Returns true if this request is from a client and not a bacground
server job or something else.

=cut

sub is_from_client
{
    return $_[0]->{'q'} ? 1 : 0;
}

=head2 dirconfig

  $req->dirconfig

Returns the dirconfig hashref. See L<Apache/SERVER CONFIGURATION
INFORMATION> C<dir_config>.

=cut

sub dirconfig
{
    return $_[0]->{'dirconfig'};
}



### Transitional methods
###

sub template
{
    return $_[0]->page->url_path_tmpl;
}

sub template_uri
{
    return $_[0]->page->url_path_full;
}

sub filename
{
    return $_[0]->page->sys_path_tmpl;
}

sub error_page_selected { $_[0]->page->error_page_selected }

sub error_page_not_selected { $_[0]->page->error_page_not_selected }

###
###########################################

=head2 in_yield

  $req->in_yield

Returns true if some other request has yielded for this request.

=cut

sub in_yield
{
    return $_[0]->{'in_yield'};
}

=head2 uri2file

  $req->uri2file( $uri )

  $req->uri2file( $uri, $file )

This does the Apache URI to filename translation

The answer is cached.

If given a C<$file> uses that as a translation and caches is.

(This method may have to create a pseudoclient connection to get the
information.)

=cut

sub uri2file
{
    my( $req, $uri, $file ) = @_;

    # This will return file without '/' for dirs

    my $key = $req->host . $uri;

    if( $file )
    {
	return $URI2FILE{ $key } = $file;
    }

    if( $file = $URI2FILE{ $key } )
    {
	return $file;
    }

#    debug "uri2file key $key";

    confess "uri missing" unless $uri;

#    warn "    From client\n";
    $req->send_code( 'URI2FILE', $uri );
    $file = Para::Frame::get_value( $req );

    debug(4, "Storing URI2FILE in key $key");
    $URI2FILE{ $key } = $file;
    return $file;
}

=head2 normalized_uri

  $req->normalized_uri( $uri )

Gives the proper version of the URI. Ending index.tt will be
removed. This is used for redirecting (forward) the browser if
nesessary.

C<$uri> must be the path part as a string.

Returns the path part as a string.

=cut

sub normalized_uri
{
    my( $req, $uri ) = @_;

    $uri ||= $req->uri;

    if( $uri =~ s/\/index.tt$/\// )
    {
	return $uri;
    }

    my $uri_file = $req->uri2file( $uri );
    if( -d $uri_file and $uri !~ /\/(\?.*)?$/ )
    {
	$uri =~ s/\?/\/?/
	    or $uri .= '/';
	return $uri;
    }

    return $uri;
}


##############################################
# Set language
#
sub set_language
{
    my( $req, $language_in ) = @_;

    debug 2, "Decide on a language";

    if( $req->is_from_client )
    {
	$language_in ||= $req->q->param('lang')
	             ||  $req->q->cookie('lang')
                     ||  $req->env->{HTTP_ACCEPT_LANGUAGE}
                     ||  '';
    }
    else
    {
	$language_in ||= '';
    }
    debug 3, "  Lang prefs are $language_in";

    confess "page not defined" unless $req->{'page'};
    my $site_languages = $req->page->site->languages;

    unless( @$site_languages )
    {
	$req->{'lang'} = ['en'];
	return;
    }


    my @alts;
    if( UNIVERSAL::isa($language_in, "ARRAY") )
    {
	@alts = @$language_in;
    }
    else
    {
	@alts = split /,\s*/, $language_in;
    }

    my %priority;

    foreach my $alt ( @alts )
    {
	my( $code, @info ) = split /\s*;\s*/, $alt;
	my $q;
	foreach my $pair ( @info )
	{
	    my( $key, $value ) = split /\s*=\s*/, $pair;
	    $q = $value if $key eq 'q';
	}
	$q ||= 1;

	push @{$priority{$q}}, $code;
    }

    my %accept = map { $_, 1 } @$site_languages;

#    warn "Acceptable choices are: ".Dumper(\%accept)."\n";

    my @alternatives;
    foreach my $prio ( sort {$b <=> $a} keys %priority )
    {
	foreach my $lang ( @{$priority{$prio}} )
	{
	    push @alternatives, $lang if $accept{$lang};
	}
    }

    ## Add default lang, if not already there
    my @defaults = $site_languages->[0];
    foreach my $lang ( @$site_languages )
    {
	unless( grep {$_ eq $lang} @alternatives )
	{
	    push @alternatives, $lang;
	}
    }

    if( $req->is_from_client )
    {
	$req->send_code( 'AR-PUT', 'header_out', 'Vary', 'negotiate,accept-language' );
	$req->send_code( 'AR-PUT', 'header_out', 'Content-Language', $alternatives[0] );
    }

    $req->{'lang'} = \@alternatives;
    debug 2, "Lang priority is: @alternatives";
}


#######################################################################

=head2 preferred_language

  $req->preferred_language()

  $req->preferred_language( $lang1, $lang2, ... )

Returns the language form the list that the user preferes. C<$langX>
is the language code, like C<sv> or C<en>.

The list will always be restircted to the languages supported by the
site, ie C<$req-E<gt>site-E<gt>languages>.  The parameters should only
be used to restrict the choises futher.

=head3 Default

The first language in the list of languages supported by the
application.

=head3 Example

  [% SWITCH lang %]
  [% CASE 'sv' %]
     <p>Valkommen ska ni vara!</p>
  [% CASE %]
     <p>Welcome, poor thing.</p>
  [% END %]

=cut

sub preferred_language
{
    my( $req, @lim_langs ) = @_;

    my $site = $req->page->site;

    my @langs;
    if( @lim_langs )
    {
      LANG:
	foreach my $lang (@{$site->languages})
	{
	    foreach( @lim_langs )
	    {
		if( $lang eq $_ )
		{
		    push @langs, $lang;
		    next LANG;
		}
	    }
	}
    }
    else
    {
	@langs = @{$site->languages};
    }

    if( $req->is_from_client )
    {
	if( my $clang = $req->q->cookie('lang') )
	{
	    unshift @langs, $clang;
	}
    }

    foreach my $lang (@{$req->language})
    {
	foreach( @langs )
	{
	    if( $lang eq $_ )
	    {
		return $lang;
	    }
	}
    }

    return $site->languages->[0];
}


#######################################################################
# Set up things from params
#
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
#    warn "Actions are now ".Dumper($actions);
}

sub add_job
{
    debug(2,"Added the job $_[1] for $_[0]->{reqnum}");
    push @{ shift->{'jobs'} }, [@_];
}

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

sub run_action
{
    my( $req, $run, @args ) = @_;

    return 1 if $run eq 'nop'; #shortcut

    my $page = $req->page;
    my $site = $page->site;

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
    eval
    {
	debug(3,"using $actionroot",1);
	no strict 'refs';
	$req->result->message( &{$actionroot.'::'.$c_run.'::handler'}($req, @args) );
	### Other info is stored in $req->result->{'info'}

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
		    my $error_tt = $site->home."/login.tt";
		    $part->hide(1);
		    $req->session->route->bookmark;
		    $page->set_error_template( $error_tt );
		}
	    }
	}
	return 0;
    };

    debug(-1);
    return 1; # All OK
}

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
	    debug "$req->{reqnum} stays open, was asked to wait for $req->{'wait'} things";
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

sub done
{
    my( $req ) = @_;
    $req->session->after_request( $req );

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

sub in_last_job
{
    return not scalar @{$_[0]->{'jobs'}};
}

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
	    $page->set_template( $previous );

	    # It must be a template
	    unless( $req->template =~ /\.tt/ )
	    {
		$previous = $page->site->home."/error.tt";
	    }

	    debug(3,"Previous is $previous");
	}
	return 1;
    }
    return 0;
}

=head2 referer

  $req->referer

Returns the LOCAL referer. Just the path part. If the referer
was from another website, fall back to default

Returns the URI path part as a string.

=cut

sub referer
{
    my( $req ) = @_;

    my $site = $req->page->site;

  TRY:
    {
	# Explicit caller_page could be given
	if( my $uri = $req->q->param('caller_page') )
	{
	    debug "Referer from caller_page";
	    return Para::Frame::URI->new($uri)->path;
	}

	# The query could have been changed by route
	if( my $uri = $req->q->referer )
	{
	    $uri = Para::Frame::URI->new($uri);
	    last if $uri->host_port ne $req->host_with_port;

	    debug "Referer from current http req ($uri)";
	    return $uri->path;
	}

	# The actual referer is more acurate in this order
	if( my $uri = $req->{'referer'} )
	{
	    $uri = Para::Frame::URI->new($uri);
	    last if $uri->host_port ne $req->host_with_port;

	    debug "Referer from original http req";
	    return $uri->path;
	}

	# This could be confusing if several browser windows uses the same
	# session
	#
	debug "Referer from session";
	return $req->session->referer->path if $req->session->referer;
    }

    debug "Referer from default value";
    return $site->last_step if $site->last_step;

    # Last try. Should always be defined
    return $site->webhome.'/';
}


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
	if( my $uri = $req->q->param('caller_page') )
	{
	    debug "Referer query from caller_page";
	    return Para::Frame::URI->new($uri)->query;
	}

	# The query could have been changed by route
	if( my $uri = $req->q->referer )
	{
	    $uri = Para::Frame::URI->new($uri);
	    last if $uri->host_port ne $req->host_with_port;

	    if( my $query = $uri->query )
	    {
		debug "Referer query from current http req ($query)";
		return $query;
	    }
	}

	# The actual referer is more acurate in this order
	if( my $uri = $req->{'referer'} )
	{
	    $uri = Para::Frame::URI->new($uri);
	    last if $uri->host_port ne $req->host_with_port;

	    if( my $query = $uri->query )
	    {
		debug "Referer query from original http req";
		return $query;
	    }
	}

	# This could be confusing if several browser windows uses the same
	# session
	#
	debug "Referer query from session";
	return $req->session->referer->query if $req->session->referer;
    }

    debug "Referer query from default value";
    return '';
}

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

#############################################

sub send_code
{
    my $req = shift;

    my $site = $req->page->site;

    # To get a response, use get_cmd_val()

    debug(3, "Sending code: ".join("-", @_));

    if( $Para::Frame::FORK )
    {
	debug("redirecting to parent");
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

	debug "Req $req->{reqnum} will now considering starting an UA";

	# Use existing
	$req->{'wait_for_active_reqest'} ||= 0;
	debug "  It waits for $req->{'wait_for_active_reqest'} active requests";
	unless( $req->{'wait_for_active_reqest'} ++ )
	{
	    debug "  So we prepares for starting an UA";
	    debug "  Now it waits for 1 active request";

	    my $origreq = $req->{'original_request'};

#	    # The site should have been set before...
#	    if( $origreq )
#	    {
#		$req->{'site'} = $origreq->{'site'};
#		debug "Using host ".$req->site->host;
#	    }

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
	debug "We got the active request $req->{'active_reqest'}{reqnum} now";
	my $aclient = $req->{'active_reqest'}->client;

	$aclient->send(join "\0", @_ );
	$aclient->send("\n");

	# Set up release code
	$req->add_job('release_active_request');
    }
    else
    {
	$client->send(join "\0", @_ );
	$client->send("\n");
    }
}

sub release_active_request
{
    my( $req ) = @_;

    debug "$req->{reqnum} is now waiting for one active req less";

    $req->{'wait_for_active_reqest'} --;

    if( $req->{'wait_for_active_reqest'} )
    {
	debug "More jobs for active request ($req->{'wait_for_active_reqest'})";
    }
    else
    {
        debug "Releasing active_request $req->{'active_reqest'}{'reqnum'}";
	$req->{'active_reqest'}{'wait'} --;
	debug "That request is now waiting for $req->{'active_reqest'}{'wait'} things";

	debug "Removing the referens to that request";
	delete $req->{'active_reqest'};
    }
}

sub get_cmd_val
{
    my $req = shift;

    $req->send_code( 'AR-GET', @_ );
    return Para::Frame::get_value( $req );
}

#############################################################

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
    $req->{'in_yield'} --;
    Para::Frame::switch_req( $req );
}

=head2 http_host

  $req->http_host

Returns the host name the client requested. It tells with which of the
alternatives names the site was requested

=cut

sub http_host
{
    if( my $server_port = $ENV{SERVER_PORT} )
    {
	if( $server_port == 80 )
	{
	    return idn_decode( $ENV{SERVER_NAME} );
	}
	else
	{
	    return idn_decode( "$ENV{SERVER_NAME}:$server_port" );
	}
    }

    return undef;
}

=head2 http_port

  $req->http_port

Returns the port the client used in this request.

=cut

sub http_port
{
    return $ENV{SERVER_PORT} || undef;
}

=head2 client_ip

  $req->client_ip

Returns the ip address of the client as a string with dot-separated
numbers.

=cut

sub client_ip
{
    return $_[0]->env->{REMOTE_ADDR} || $_[0]->{'client'}->peerhost;
}

=head2 site

  $req->site

Returns the L<Para::Frame::Site> object for this request.

=cut

sub site
{
    return $_[0]->page->site;
}

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

sub register_child
{
    my( $req, $pid, $fh ) = @_;

    return Para::Frame::Child->register( $req, $pid, $fh );
}

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

#    warn Dumper $result;

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

sub run_hook
{
    Para::Frame->run_hook(@_);
}

sub debug_data
{
    my( $req ) = @_;

    my $page = $req->page;

    my $out = "";
    my $reqnum = $req->{'reqnum'};
    $out .= "This is request $reqnum\n";

    $out .= $req->session->debug_data;

    if( $req->is_from_client )
    {
	$out .= "Orig uri: $req->{orig_uri}\n";

	if( my $redirect = $page->{'redirect'} )
	{
	    $out .= "Redirect is set to $redirect\n";
	}

	if( my $browser = $req->env->{'HTTP_USER_AGENT'} )
	{
	    $out .= "Browser is $browser\n";
	}

	if( my $errtmpl = $page->{'error_template'} )
	{
	    $out .= "Error template is set to $errtmpl\n";
	}

	if( my $referer = $req->referer )
	{
	    $out .= "Referer is $referer\n"
	}

	if( $page->{'in_body'} )
	{
	    $out .= "We have already sent the http header\n"
	}

    }

    if( my $chldnum = $req->{'childs'} )
    {
	$out .= "This request waits for $chldnum children\n";

	foreach my $child ( values %Para::Frame::CHILD )
	{
	    my $creq = $child->req;
	    my $creqnum = $creq->{'reqnum'};
	    my $cclient = $creq->client;
	    my $cpid = $child->pid;
	    $out .= "  Req $creqnum $cclient has a child with pid $cpid\n";
	}
    }

    if( $req->{'in_yield'} )
    {
	$out .= "This request is in yield now\n";
    }

    if( $req->{'wait'} )
    {
	$out .= "This request waits for something\n";
    }

    if( my $jobcnt = @{ $req->{'jobs'} } )
    {
	$out .= "Has $jobcnt jobs\n";
	foreach my $job ( @{ $req->{'jobs'} } )
	{
	    my( $cmd, @args ) = @$job;
	    $out .= "  $cmd with args @args\n";
	}
    }

    if( my $acnt = @{ $req->{'actions'} } )
    {
	$out .= "Has $acnt a\n";
	foreach my $action ( @{ $req->{'actions'} } )
	{
	    $out .= "  $action\n";
	}
    }

    if( $req->result )
    {
	$out .= "Result:\n".$req->result->as_string;
    }

}


#######################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>

=cut
