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

use strict;
use CGI qw( -compile );
use CGI::Cookie;
use FreezeThaw qw( thaw );
use Data::Dumper;
use HTTP::BrowserDetect;
use Clone qw( clone );
use File::stat;
use File::Slurp;
use File::Basename;
use IO::File;
use URI;
use Carp qw(cluck croak carp confess );
use Encode qw( is_utf8 );
use LWP::UserAgent;
use HTTP::Request;

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
use Para::Frame::Request::Ctype;
use Para::Frame::Utils qw( create_dir chmod_file dirsteps uri2file compile throw idn_encode idn_decode debug catch );

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
	headers        => [],             ## Headers to be sent to the client
	'q'            => $q,
	env            => $env,
	's'            => undef,          ## Session object
	lang           => undef,          ## Chosen language
	params         => clone($Para::Frame::PARAMS), ## template data
	redirect       => undef,          ## ... to other server
	browser        => undef,          ## browser detection object
	result         => undef,
	orig_uri       => $orig_uri,
	orig_ctype     => $content_type,
	uri            => undef,
	template       => undef,          ## if diffrent from URI
	template_uri   => undef,          ## if diffrent from URI
	error_template => undef,          ## if diffrent from template
	referer        => $q->referer,    ## The referer of this page
	ctype          => undef,          ## The response content-type
	dirconfig      => $dirconfig,     ## Apache $r->dir_config
	in_body        => 0,              ## flag then headers sent
	page           => undef,          ## Ref to the generated page
	page_sender    => undef,          ## The mode of sending the page
	childs         => 0,              ## counter in parent
	in_yield       => 0,              ## inside a yield
	child_result   => undef,          ## the child res if in child
	reqnum         => $reqnum,        ## The request serial number
	wait           => 0,              ## Asked to wait?
    }, $class;

    # Cache uri2file translation
    uri2file( $orig_uri, $orig_filename, $req);

    $req->{'cookies'} = new Para::Frame::Cookies($req);
    $req->{'browser'} = new HTTP::BrowserDetect($env->{'HTTP_USER_AGENT'}||undef);
    $req->{'result'}  = new Para::Frame::Result($req);  # Before Session
    $req->{'s'}       = new Para::Frame::Session($req);

    # Log some info
    #
    warn "# http://".$req->http_host_name."$orig_uri\n";

    warn "Req for $req->{'env'}{'HTTP_HOST'}\n";


    return $req;
}

=head2 new_minimal

Used for background jobs, without a calling browser client

=cut

sub new_minimal
{
    my( $class, $reqnum, $bg_client ) = @_;

    if( $Para::Frame::REQ )
    {
	# Detatch previous %ENV
	$Para::Frame::REQ->{'env'} = {%ENV};
    }

    %ENV = ();
    my( $env ) = \%ENV;

    my $req =  bless
    {
	client         => $bg_client,     ## Just the unique name
	indent         => 1,              ## debug indentation
	jobs           => [],             ## queue of actions to perform
	env            => $env,
	's'            => undef,          ## Session object
	lang           => undef,          ## Chosen language
	result         => undef,
	childs         => 0,              ## counter in parent
	in_yield       => 0,              ## inside a yield
	child_result   => undef,          ## the child res if in child
	reqnum         => $reqnum,        ## The request serial number
	wait           => 0,              ## Asked to wait?
    }, $class;

    $req->{'result'}  = new Para::Frame::Result($req);  # Before Session
    $req->{'s'}       = Para::Frame::Session->new_minimal($req);

    return $req;
}

#######################################################################

sub q { shift->{'q'} }
sub s { shift->{'s'} }
sub env { shift->{'env'} }
sub client { shift->{'client'} }
sub cookies { shift->{'cookies'} }
sub result { shift->{'result'} }
sub uri { shift->{'uri'} }
sub dir { shift->{'dir'} }
sub filename { uri2file(shift->template) }
sub lang { undef }
sub error_page_selected { $_[0]->{'error_template'} ? 1 : 0 }
sub error_page_not_selected { $_[0]->{'error_template'} ? 0 : 1 }

# Is this request a client req or a bg server job?
sub is_from_client
{
    return $_[0]->{'q'} ? 1 : 0;
}

sub template
{
    return $_[0]->{'template'} || $_[0]->{'uri'};
}

sub template_uri
{
    return $_[0]->{'template_uri'} || $_[0]->{'uri'};
}

sub in_yield
{
    return $_[0]->{'in_yield'};
}

#######################################################################

sub set_uri
{
    my( $req, $uri ) = @_;

    die "not impelemnted" if $uri =~ /\?/;

    debug(3,"setting URI to $uri");
    $req->{uri} = $uri;
    $req->set_template( $uri );

    if( $uri eq '/test/die.tt' ) # Special testing URI
    {
	die if $Para::Frame::U->level == 42;
    }

    return $uri;
}

sub set_template
{
    my( $req, $template ) = @_;

    # For setting a template diffrent from the URI

    # To forward to a page not handled by the paraframe, use
    # redirect()

    # template param should NOT include the http://hostname part
    # TODO: tecken.se uses set_tempalte to redirect to another domain

    my $template_uri = $template;

    # Apache can possibly be rewriting the name of the file...

    # The template to file translation is used for getting the
    # directory of the templates. But we assume that the URI
    # represents an actual file, regardless of the uri2file
    # translation. If the translation goes to another file, that file
    # will be ignored and the file named like that in the URI will be
    # used.


    my $file = uri2file( $template );
    debug(3,"The template $template represents the file $file");
    if( -d $file )
    {
	debug(3,"  It's a dir!");
	unless( $template =~ /\/$/ )
	{
	    $template .= "/";
	    $template_uri .= "/";
	}
	$template .= "index.tt";
    }
    elsif( $template =~ /\/$/ )
    {
	# Template indicates a dir. Make it so
	$template .= "index.tt";
    }
    else
    {
#	# Don't change template...
#
#	my( $tname, $tpath, $text ) = fileparse( $template, qr{\..*} );
#	my( $fname, $fpath, $fext ) = fileparse( $file,     qr{\..*} );
#
#	# Change the name but not the path
#
#	if( $tname ne $fname )
#	{
#	    $template = $tpath . $fname . $fext;
#	}
    }
  
    debug(3,"setting template to $template");

    $req->ctype->set("text/html") if $template =~ /\.tt$/;

    $req->{template}     = $template;
    $req->{template_uri} = $template_uri;

    return $template;
}

sub set_error_template
{
    my( $req, $error_tt ) = @_;

    return $req->{'error_template'} = $req->set_template( $error_tt );
}

sub ctype
{
    my( $req, $content_type ) = @_;

    # Needs $REQ

    unless( $req->{'ctype'} )
    {
	$req->{'ctype'} = Para::Frame::Request::Ctype->new();
    }

    if( $content_type )
    {
	$req->{'ctype'}->set( $content_type );
    }

    return $req->{'ctype'};
}


##############################################
# Set up things from params
#
sub setup_jobs
{
    my( $req ) = @_;

    my $q = $req->q;

    # Section for request
    $req->{'section'}  ||= [$q->param('section')];

    # Custom renderer?
    $req->{'renderer'} ||= $q->param('renderer') || undef;

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

    $req->add_job('after_jobs');
}

sub add_job
{
    debug(2,"Added the job $_[1] for $_[0]->{reqnum}");
    push @{ shift->{'jobs'} }, [@_];
}

sub add_background_job
{
    debug(2,"Added the background job $_[1] for $_[0]->{reqnum}");
    push @Para::Frame::BGJOBS_PENDING, [@_];
}

sub add_header
{
    push @{ shift->{'headers'}}, [@_];
}

sub send_headers
{
    my( $req ) = @_;

    my $client = $req->client;

    $req->ctype->commit;

    my %multiple; # Replace first, but add later headers
    foreach my $header ( @{$req->{'headers'}} )
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
    $req->{'in_body'} = 1;
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

# This concept is flawed...
#
# sub run_code_as_user
# {
#     my( $req, $user ) = (shift, shift );
# 
#     # Save the original request, because it may be needed if the real
#     # request is a background job. But support just giving the
#     # username
# 
#     if( ref $user eq 'Para::Frame::Request' )
#     {
# 	my $original_request = $user;
# 
# 	$user = $req->s->u;
# 	$req->{'original_request'} = $original_request;
#     }
# 
#     # The code should not let other jobs for the same request run
#     # while this job is running, since it then would run with the
#     # wrong user and maby the wrong original_request, in case this is
#     # a background request.
# 
#     $user->become_temporary_user($user);
#     my $res = $req->run_code(@_);
#     $user->revert_from_temporary_user();
#     delete $req->{'original_request'};
#     return $res;
# }

sub run_action
{
    my( $req, $run, @args ) = @_;

    return 1 if $run eq 'nop'; #shortcut

    my $actionroots = [$Para::Frame::CFG->{'appbase'}."::Action"];
    foreach my $family ( @{$Para::Frame::CFG->{'appfmly'}} )
    {
	push @$actionroots, "${family}::Action";
    }
    push @$actionroots, "Para::Frame::Action";

    my( $c_run ) = $run =~ m/^([\w\-]+)$/
	or die "bad chars in run: $run";
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
	$req->result->exception;
	return 0;
    };

    debug(-1);
    return 1; # All OK
}

sub after_jobs
{
    my( $req ) = @_;

    # Take a planned action unless an error has been encountered
    if( my $action = shift @{ $req->{'actions'} } )
    {
	unless( $req->result->errcnt )
	{
	    $req->add_job('run_action', $action);
	    $req->add_job('after_jobs');
	}
    }

    if( $req->in_last_job )
    {
	# Check for each thing. If more jobs, stop and add a new after_jobs

	### Waiting for children?
	if( $req->{'childs'} )
	{
	    debug(2,"Waiting for childs");
	    return;
	}

	### Do pre backtrack stuff
	### Do backtrack stuff
	$req->error_backtrack or
	    $req->s->route->check_backtrack;
	### Do last job stuff
    }

    # Backtracking could have added more jobs
    #
    if( $req->in_last_job )
    {
	## TODO: forward if requested uri ends in /index.tt

	if( $req->error_page_not_selected and $req->{'redirect'} )
	{
	    $req->cookies->add_to_header;
 
	    $req->output_redirection( $req->{'redirect'} );

	    $req->s->after_request( $req );

	    return;
	}


	my $render_result = 0;

	if( $req->{'renderer'} )
	{
	    # Using custom renderer
	    $render_result = &{$req->{'renderer'}}( $req );

	    # TODO: Handle error...
	}
	else
	{
	    $render_result = $req->render_output;
	}

	if( $render_result )
	{
	    $req->cookies->add_to_header;
 
	    $req->send_output;

	    $req->s->after_request( $req );

	    return;
	}
	$req->add_job('after_jobs');
    }

    return 1;
}

sub in_last_job
{
    return not scalar @{$_[0]->{'jobs'}};
}

sub error_backtrack
{
    my( $req ) = @_;

    if( $req->result->errcnt and not $req->error_page_selected )
    {
	debug(2,"Backtracking to previuos page because of errors");
	my $previous = $req->referer;
	if( $previous )
	{
	    # It must be a template
	    unless( $previous =~ /\.tt/ )
	    {
		$previous = "/error.tt";
	    }

	    debug(3,"Previous is $previous");

	    # Do not regard this as an error template
	    $req->set_template( $previous );
	}
	return 1;
    }
    return 0;
}

sub add_params
{
    my( $req, $extra, $keep_old ) = @_;

    my $param = $req->{'params'};

    if( $keep_old )
    {
	while( my($key, $val) = each %$extra )
	{
	    next if $param->{$key};
	    $param->{$key} = $val;
	    debug(4,"Add TT param $key");
	}
    }
    else
    {
	while( my($key, $val) = each %$extra )
	{
	    $param->{$key} = $val;
	    debug(4,"Add TT param $key");
	}
     }
}

sub referer
{
    my( $req ) = @_;

    #
    # TODO: test recovery from runaway processes
    # test recursive $req->referer
    #


    # Returns the path part

    # Explicit caller_page could be given
    if( my $uri = $req->q->param('caller_page') )
    {
	return URI->new($uri)->path;
    }

    # The query could have been changed by route
    if( my $uri = $req->q->referer )
    {
	return URI->new($uri)->path;
    }

    # The actual referer is more acurate in this order
    if( my $uri = $req->{'referer'} )
    {
	return URI->new($uri)->path;
    }

    # This could be confusing if several browser windows uses the same
    # session
    #
    return $req->s->referer if $req->s->referer;

    return $Para::Frame::CFG->{'site'}{'last_step'} if
	$Para::Frame::CFG->{'site'}{'last_step'};

    # Last try. Should always be defined
    return $Para::Frame::CFG->{'site'}{'webhome'}.'/';
}

#############################################

sub get_static
{
    my( $req, $in, $pageref ) = @_;

    my $client = $req->client;
    $pageref or die;
    my $page = "";

    unless( ref $in )
    {
	$in = IO::File->new( $in );
    }


    if( ref $in eq 'IO::File' )
    {
	$page .= $_ while <$in>;
#	$client->send( $_ ) while <$in>;
    }
    else
    {
	warn "in: $in\n";
	die "What can I do";
    }

    return $pageref = \$page;
}

sub find_template
{
    my( $req, $template ) = @_;

    debug(3,"Finding template $template");
    my( $in );


    my( $base_name, $path_full, $ext_full ) = fileparse( $template, qr{\..*} );
    if( debug > 3 )
    {
	debug(0,"path: $path_full");
	debug(0,"name: $base_name");
	debug(0,"ext : $ext_full");
    }

    my( $ext ) = $ext_full =~ m/^\.(.+)/; # Skip initial dot

    # Not absolute path?
    if( $template !~ /^\// )
    {
	die "not implemented ($template)";
    }

    # Also used by &Para::Frame::incpath_generator
    $req->{'dirsteps'} = [ dirsteps( $path_full ) ];

    # uri2file returns file without '/' for dirs
    my( @step ) = map uri2file( $_."def" )."/", @{$req->{'dirsteps'}};


    # TODO: Check for global templates with this name
    my $global = $Para::Frame::CFG->{'paraframe'}. "/def/";

    # Reasonable default?
    my $language = $req->lang || ['sv'];

    debug(4,"Check $ext",1);
    foreach my $path ( uri2file($path_full)."/", @step, $global )
    {
	die unless $path; # could be undef

	# We look for both tt and html regardless of it the file was called as .html
	debug(4,"Check $path",1);
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
		my $params = $Para::Frame::CFG->{'th'}{'html'};
		my $compfile = $params->{ COMPILE_DIR }.$filename;
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
			my $parser = Template::Config->parser($params);
			
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
			$req->result->exception;
			if( $template eq '/error.tt' )
			{
			    die( "Fatal template error for error.tt: ".
				 $Para::Frame::th->{'html'}->error()."\n");
			}
			debug(2,"Using /error.tt");
			($in) = $req->find_template('/error.tt');
			debug(-2);
			return( $in, 'tt' );
		    }
		}

		debug(-2);
		return( $data, $ext );
	    }
	    debug(-1);
	}
	debug(-1);
    }

    # If we can't find the filname
    debug(1,"Not found: $template");
    return( undef );
}

sub load_compiled
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

sub send_code
{
    my $req = shift;

    # To get a response, use get_cmd_val()

    debug(3,"Sending code: ".join("-", @_));

    if( $Para::Frame::FORK )
    {
	debug(2,"redirecting to parent");
	my $code = shift;
	my $port = $Para::Frame::CFG->{'port'};
	my $client = $req->client;
	debug(3,"  to $client");
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

	debug "The $client will now considering starting an UA";
	

	# Use existing
	$req->{'wait_for_active_reqest'} ||= 0;
	unless( $req->{'wait_for_active_reqest'} ++ )
	{
	    debug "  Prepare for starting UA\n";

	    my $origreq = $req->{'original_request'};

	    # Find out which website to use
	    my( $webhost, $webport );
	    if( $origreq )
	    {
		$webhost = $origreq->{'env'}{'HTTP_HOST'};
	    }
	    else
	    {
		$webhost = $Para::Frame::CFG->{'site'}{'webhost'};
	    }

	    my $webpath = $Para::Frame::CFG->{'site'}{'loopback'};
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
	debug 3, "We got an active request for $client";
	my $client = $req->{'active_reqest'}->client;
	debug 3, "  Using $client";

	$client->send(join "\0", @_ );
	$client->send("\n");

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

    $req->{'wait_for_active_reqest'} --;

    if( $req->{'wait_for_active_reqest'} )
    {
	debug "More jobs for active request";
    }
    else
    {
        debug "Releasing active_request";

	$req->{'active_reqest'}{'wait'} --;
	delete $req->{'active_reqest'};
    }
}

sub get_cmd_val
{
    my $req = shift;

    $req->send_code( 'AR-GET', @_ );
    return Para::Frame::get_value( $req );
}

sub render_output
{
    my( $req ) = @_;

    ### Output page
    my $client = $req->client;
    my $template = $req->template;
    my $page = "";


    my( $in, $ext ) = $req->find_template( $template );

    # Setting tt params AFTER template was found
    $req->set_tt_params;

    if( not $in )
    {
	( $in, $ext ) = $req->find_template( '/page_not_found.tt' );
	$Para::Frame::REQ->result->error('notfound', "Hittar inte sidan $template\n");
    }

    if( not $in )
    {
	$page .= ( "<p>404: Not found\n" );
	$page .= ( "<p>Failed to find the file not found error page!\n" );
    }
    elsif( $ext ne 'tt' )
    {
	$req->get_static( $in, \$page );
	return 1;
    }
    else
    {
	$Para::Frame::th->{'html'}->process($in, $req->{'params'}, \$page)
	    or do
	{

	    debug(0,"FALLBACK!");
	    $req->result->message("During the processing of\n$template");
	    $req->result->exception();

	    my $error = $Para::Frame::th->{'html'}->error;

	    ### Use error page template
	    my $error_tt = $req->template; # Could have changed
	    if( $error_tt eq $template ) # No new template specified
	    {
		if( $error->type eq 'file' )
		{
		    ## TODO: Check if error is a 404 or TT error
		    $error_tt = '/page_part_not_found.tt';
		}
		elsif( $error->type eq 'denied' and $req->s->u->level == 0 )
		{
		    # Ask to log in
		    $error_tt = "/login.tt";
		    $req->s->route->bookmark;
		}
		else
		{
		    $error_tt = '/error.tt';
		}
	    }

	    debug(1,$Para::Frame::th->{'html'}->error());

	    $req->set_error_template( $error_tt );

	    return 0;

	};1
    }


    if( debug > 3 )
    {
	$page .= ( "<h2>Debug data</h2>\n" );
#	$page .= (sprintf "<p>Using template %s med ext $ext\n", $in, $ext) if $in;
        $page .= ("<table>\n");
	$page .= (sprintf "<tr><td>Referer <td>%s\n", $req->referer);
	$page .= (sprintf "<tr><td>Orig URI <td>%s\n", $req->{orig_uri});
	$page .= (sprintf "<tr><td>me <td>%s\n", $req->{me});
	$page .= (sprintf "<tr><td>template <td>%s\n", $req->{template});
	$page .= (sprintf "<tr><td>dir <td>%s\n", $req->{dir});
	$page .= (sprintf "<tr><td>filename <td>%s\n", $req->filename);
	$page .= (sprintf "<tr><td>Session ID <td>%s\n", $req->s->id);
        $page .= ("</table>\n");
    }

    $req->{'page'} = \$page;

    return 1;
}

sub send_output
{
    my( $req ) = @_;

    # Forward if URL differs from template_url

    if( debug > 2 )
    {
	debug(0,"Sending output to ".$req->uri);
	debug(0,"Sending the page ".$req->template_uri);
    }

    if( $req->error_page_not_selected and
	$req->uri ne $req->template_uri )
    {
	$req->forward();
    }
    else
    {
	# If not set, find out best way to send page
	if( $req->{'page_sender'} )
	{
	    unless( $req->{'page_sender'} =~ /^(utf8|bytes)$/ )
	    {
		debug "Page sender $req->{page_sender} not recogized";
	    }
	}
	else
	{
	    if( is_utf8  ${ $req->{'page'} } )
	    {
		$req->{'page_sender'} = 'utf8';
	    }
	    else
	    {
		$req->{'page_sender'} = 'bytes';
	    }
	}

	if( $req->{'page_sender'} eq 'utf8' )
	{
	    $req->ctype->set_charset("UTF-8");
	    $req->send_headers;
	    binmode( $req->client, ':utf8');
	    debug(4,"Transmitting in utf8 mode");
	    $req->send_in_chunks( $req->{'page'} );
	    binmode( $req->client, ':bytes');
	}
	else # Default
	{
	    $req->send_headers;
	    $req->send_in_chunks( $req->{'page'} );
	}
    }
}

sub send_in_chunks
{
    my( $req, $dataref ) = @_;

    my $client = $req->client;
    my $length = length($$dataref);
    debug(4,"Sending ".length($$dataref)." bytes of data to client");
    my $sent = 0;
    my $errcnt = 0;
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
		debug(1,"  Failed to send chunk $i\n  Tries to recover...",1);

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

    return $sent;
}

sub yield
{
    my( $req, $wait ) = @_;

    $req->{'in_yield'} ++;
    Para::Frame::main_loop( 1, $wait );
    $req->{'in_yield'} --;
    Para::Frame::switch_req( $req );
}

sub forward
{
    my( $req, $uri ) = @_;

    # Should only be called AFTER the page has been generated

    # To request a forward, just set the set_template($uri) before the
    # page is generated.

    # To forward to a page not handled by the paraframe, use
    # redirect()

    confess "forward() called without a generated page" unless $req->{'page'};

    $uri ||= $req->template_uri;
    $req->output_redirection($uri);
    $req->s->register_result_page($uri, $req->{'headers'}, $req->{'page'});
}

sub redirect
{
    my( $req, $uri ) = @_;

    # This is for redirecting to a page  not handled by the paraframe

    # The actual redirection will be done then all the jobs are
    # finished. Error in the jobs could result in a redirection to an
    # error page instead.

    $req->{'redirect'} = $uri;
}

sub output_redirection
{
    my( $req, $uri_in ) = @_;
    $uri_in or die "URI missing";

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
	my $uri = URI->new($uri_in, 'http');
	$uri->host( idn_encode $req->http_host_name ) unless $uri->host;
	$uri->port( $req->host_port ) unless $uri->port;
	$uri->scheme('http');

	$uri_out =  $uri->canonical->as_string;
    }

    debug(2,"--> Redirect to $uri_out");

    $req->send_code( 'AR-PUT', 'status', 302 ); # moved
    $req->send_code( 'AR-PUT', 'header_out', 'Pragma', 'no-cache' );
    $req->send_code( 'AR-PUT', 'header_out', 'Cache-Control', 'no-cache' );
    $req->send_code( 'AR-PUT', 'header_out', 'Location', $uri_out );
    $req->send_code( 'AR-PUT', 'send_http_header', 'text/plain' );
    $req->client->send( "\n" );
    $req->client->send( "Go to $uri_out\n" );
}

sub http_host_name
{

    # This is the host name the client requested. It tells with which
    # of the alternatives names the site was requested

#    warn "Host name: $ENV{SERVER_NAME}\n";
    return idn_decode( $ENV{HTTP_HOST} );
}

sub client_ip
{
    return $_[0]->env->{REMOTE_ADDR} || $_[0]->{'client'}->peerhost;
}

sub host_name
{
    # This is the host name as given in the apache config.

#    warn "Host name: $ENV{SERVER_NAME}\n";
    return idn_decode( $ENV{SERVER_NAME} );
}

sub host_port
{
#    warn "Host port: $ENV{SERVER_PORT}\n";
    return $ENV{SERVER_PORT};
}

sub host
{
    my $port = host_port();

    if( $port == 80 )
    {
	return host_name();
    }
    else
    {
	return sprintf "%s:%d", host_name(), $port;
    }
}

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
    my( $req, $child ) = @_;

    my $result;
    eval
    {
	$result = $child->get_results;
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

sub set_tt_params
{
    my( $req ) = @_;

    # Real filename
    my $real_filename = $req->filename;
    $real_filename or die "No filename given: ".Dumper($req);

    # Determine the directory
    my( $dir ) = $real_filename =~ /^(.*\/)/;
    $req->{'dir'} = $dir;
    debug(3,"Setting dir to $dir");

    # Keep alredy defined params  # Static within a request
    $req->add_params({
	'q'               => $req->{'q'},
	'ENV'             => $req->env,
	'me'              => $req->template_uri,
	'filename'        => $real_filename,
	'dir'             => $dir,
	'browser'         => $req->{'browser'},
	'u'               => $Para::Frame::U,
	'result'          => $req->{'result'},
	'reqnum'          => $req->{'reqnum'},
	'req'             => $req,

	# Is allowed to change between requests
	'site'            => $Para::Frame::CFG->{'site'},
	'home'            => $Para::Frame::CFG->{'site'}{'webhome'},
    }, 1);
}

1;
