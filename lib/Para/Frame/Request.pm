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
use CGI qw( :all );
use CGI::Cookie;
use FreezeThaw qw( thaw );
use Data::Dumper;
use HTTP::BrowserDetect;
use Time::Piece;
use Clone qw( clone );
use File::stat;
use File::Slurp;
use File::Basename;
use IO::File;
use URI;
use Carp qw(cluck);
#use Cwd qw( abs_path );
use Encode qw( is_utf8 );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Client;

use Para::Frame::Reload;
use Para::Frame::Cookies;
use Para::Frame::Session;
use Para::Frame::Result;
use Para::Frame::Child;
use Para::Frame::Child::Result;
use Para::Frame::Request::Ctype;
use Para::Frame::Utils qw( create_dir chmod_file dirsteps uri2file compile throw idn_encode idn_decode );

our $DEBUG = undef;

sub new
{
    my( $class, $client, $recordref, $reqnum ) = @_;

    $DEBUG = $Para::Frame::DEBUG;

    my( $value ) = thaw( $$recordref );
    my( $params, $env, $orig_uri, $orig_filename, $content_type ) = @$value;

    # Modify $env for non-mod_perl mode
    $env->{'REQUEST_METHOD'} = 'GET';
    delete $env->{'MOD_PERL'};

    %ENV = %$env;     # To make CGI happy
    my $q = new CGI($params);
    $q->cookie('password'); # Should cache all cookies

    my $req =  bless
    {
	debug          => 0,              ## Debug level
	client         => $client,
	jobs           => [],             ## queue of actions to perform
	headers        => [],             ## Headers to be sent to the client
	'q'            => $q,
	env            => $env,
	's'            => undef,          ## Session object
	lang           => undef,          ## Chosen language
	params         => clone($Para::Frame::PARAMS), ## template data
	redrict        => undef,          ## redirect to other server
	browser        => undef,          ## browser detection object
	result         => undef,
	orig_uri       => $orig_uri,
	uri            => undef,
	template       => undef,          ## if diffrent from URI
	error_template => undef,          ## if diffrent from template
	ctype          => undef,          ## The response content-type
	in_body        => 0,              ## flag then headers sent
	page           => undef,          ## The generated page to output
	childs         => 0,              ## counter in parent
	in_yield       => 0,              ## inside a yield
	child_result   => undef,          ## the child res if in child
	reqnum         => $reqnum,        ## The request serial number
    }, $class;

    # Register $req
    $Para::Frame::REQ = $req;

    # Cache uri2file translation
    uri2file( $orig_uri, $orig_filename);

    $req->{'cookies'} = new Para::Frame::Cookies($req);
    $req->{'browser'} = new HTTP::BrowserDetect($env->{'HTTP_USER_AGENT'}||undef);
    $req->{'result'}  = new Para::Frame::Result($req);  # Before Session
    $req->{'s'}       = new Para::Frame::Session($req);

    $req->ctype( $content_type );

    $req->{'uri'} = $req->set_uri( $orig_uri );

    # Initialize the route
    $req->{'s'}->route->init;

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
sub me { shift->{'me'} } # same as uri, minus index.tt
sub filename { uri2file(shift->template) }
sub lang { undef }
sub error_page_selected { $_[0]->{'error_template'} ? 1 : 0 }

sub template
{
    return $_[0]->{'template'} || $_[0]->{'uri'};
}

sub template_uri
{
    my $template = $_[0]->template;

    $template =~ s/\/index.tt$/\//;
    return $template;
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

    warn "  setting URI to $uri\n";
    $req->{uri} = $uri;
    $req->set_template( $uri );

    return $uri;
}

sub set_template
{
    my( $req, $template ) = @_;

    # For setting a template diffrent from the URI

    warn "  setting template to $template\n";

    if( -d uri2file( $template ) )
    {
	$template .= "/" unless $template =~ /\/$/;
	$template .= "index.tt";
    }
  
    $req->ctype->set("text/html") if $template =~ /\.tt$/;

    $req->{template} = $template;

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
    $req->{'renderer'} ||= $q->param('renderer');

    # Setup actions
    my $actions = [];
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

    $req->add_job('after_jobs');
}



sub add_job
{
    warn "  Added the job $_[1] for $_[0]->{reqnum}\n"
	if $DEBUG > 1;
#    cluck;
#    push @Para::Frame::JOBS, [@_];
    push @{ shift->{'jobs'} }, [@_];
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
	    warn "  Send header add @$header\n";
	    $req->send_code( 'AT-PUT', 'add', @$header);
	}
	else
	{
	    warn "  Send header_out @$header\n";
	    $req->send_code( 'AR-PUT', 'header_out', @$header);
	}
    }

    warn "  Send newline\n";
    $client->send( "\n" );
    $req->{'in_body'} = 1;
}

sub run_action
{
    my( $req, $run ) = @_;

    return 1 if $run eq 'nop'; #shortcut

    my $actionroots = [$Para::Frame::CFG->{'appbase'}."::Action"];
    foreach my $family ( @{$Para::Frame::CFG->{'appfmly'}} )
    {
	push @$actionroots, "${family}::Action";
    }
    push @$actionroots, "Para::Frame::Action";

    my( $c_run ) = $run =~ m/^([\w\-]+)$/
	or die "bad chars in run: $run";
    warn "  Will now require $c_run\n" if $DEBUG;

    # Only keep error if all tries failed

    my( $actionroot, %errors );
    foreach my $tryroot ( @$actionroots )
    {
	my $path = $tryroot;
	$path =~ s/::/\//g;
	my $file = "$path/${c_run}.pm";
	warn "    testing $file\n" if $DEBUG > 1;
	eval
	{
	    compile($file);
	};
	if( $@ )
	{
	    # What went wrong?
	    warn "    $@\n" if $DEBUG > 2;

	    if( $@ =~ /^Can\'t locate $file/ )
	    {
		push @{$errors{'notfound'}}, "$c_run hittades inte under $tryroot";
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
		    warn "Not matching BEGIN failed\n" if $DEBUG > 1;
		    $info = $@;
		}
		push @{$errors{'compilation'}}, $info;
	    }
	    else
	    {
		warn "    Generic error in require $file\n" if $DEBUG;
		push @{$errors{'compilation'}}, $@;
	    }
	    last; # HOLD IT
	}
	else
	{
	    $actionroot = $tryroot;
	    last; # Success!
	}
    }

    if( not $actionroot )
    {
	warn "    ACTION NOT LOADED!\n" if $DEBUG;

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
	warn "    using $actionroot\n" if $DEBUG > 1;
	no strict 'refs';
	$req->result->message( &{$actionroot.'::'.$c_run.'::handler'}($req) );
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
	    warn "  Fork child got EXCEPTION: $@\n";
	    $result->return;
	    exit;
	}

	warn "  ACTION FAILED!\n" if $DEBUG;
	warn $@ if $DEBUG > 2;
	$req->result->exception;
	return 0;
    };

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
	return if $req->{'childs'};

	### Do pre backtrack stuff
	### Do backtrack stuff
	$req->s->route->check_backtrack;
	### Do last job stuff

	### handle error
	$req->error_backtrack;

	## TODO: redirect if requested uri ends in /index.tt
	if( $req->render_output )
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
	warn "  Backtracking to previuos page because of errors\n";
	my $previous = $req->referer;
	if( $previous )
	{
	    warn "    Previous is $previous\n" if $DEBUG;
	    # TODO: forward to the URI instead
	    $req->set_error_template( $previous );
	}
    }
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
	}
    }
    else
    {
	while( my($key, $val) = each %$extra )
	{
	    $param->{$key} = $val;
	}
     }
}

sub referer
{
    my( $req ) = @_;

    # Returns the path part

    # The actual referer is more acurate in this order
    if( my $uri = $req->q->referer )
    {
	return URI->new($uri)->path;
    }

    return $req->s->referer;
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

    warn "  Finding template $template\n" if $DEBUG;
    my( $in );


    my( $base_name, $path_full, $ext_full ) = fileparse( $template, qr{\..*} );
    if( $DEBUG > 3 )
      {
	warn "  path: $path_full\n";
	warn "  name: $base_name\n";
	warn "  ext : $ext_full\n";
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
    my $global = $Para::Frame::ROOT . "/def/";

    # Reasonable default?
    my $language = $req->lang || ['sv'];

	warn "    Check $ext\n" if $DEBUG > 2;
	foreach my $path ( uri2file($path_full)."/", @step, $global )
	{
	    die unless $path; # could be undef

	    # We look for both tt and html regardless of it the file was called as .html
	    warn "      Check $path\n" if $DEBUG > 2;
	    die "dir_redirct failed" unless $base_name;

	    # Handle dirs
	    if( -d $path.$base_name.$ext_full )
	    {
		die "Found a directory: $path$base_name$ext_full\nShould redirect";
	    }


	    # Find language specific template
	    foreach my $lang ( map(".$_",@$language),'' )
	    {
		warn "        Check $lang\n" if $DEBUG > 2;
		my $filename = $path.$base_name.$lang.$ext_full;
		if( -r $filename )
		{
		    warn "  Using $filename\n" if $DEBUG;

		    # Static file
		    if( $ext ne 'tt' )
		    {
			warn "    As STATIC ($ext)\n";
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
			warn "    Found in MEMORY\n" if $DEBUG;
			( $data, $ltime) = @$rec;
			if( $ltime <= $mod_time )
			{
			    warn "       To old!\n" if $DEBUG;
			    warn "       ltime: $ltime\n";
			    warn "    mod_time: $mod_time\n";
			    undef $data;
			}
		    }

		    # 2. Look for compiled file
		    #
		    unless( $data )
		    {
			if( -f $compfile )
			{
			    warn "    Found in COMPILED file\n" if $DEBUG;

			    my $ltime = stat($compfile)->mtime;
			    if( $ltime <= $mod_time )
			    {
				warn "       To old!\n" if $DEBUG;
				warn "       ltime: $ltime\n";
				warn "    mod_time: $mod_time\n";
			    }
			    else
			    {
				$data = load_compiled( $compfile );

				warn "      Loading $compfile\n" if $DEBUG;

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
			    warn "    Reading file\n" if $DEBUG;
			    $mod_time = time; # The new time of reading file
			    my $filetext = read_file( $filename );
			    my $parser = Template::Config->parser($params);

			    warn "    Parsing\n" if $DEBUG;
			    my $parsedoc = $parser->parse( $filetext )
			      or throw('template', "parse error:\nFile: $filename\n".
				       $parser->error);

			    $parsedoc->{ METADATA }{'name'} = $filename;
			    $parsedoc->{ METADATA }{'modtime'} = $mod_time;

			    warn "    Writing compiled file\n" if $DEBUG;
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
			    warn "  Error while compiling template $filename: $@";
			    $req->result->exception;
			    if( $template eq '/error.tt' )
			    {
				die( "Fatal template error for error.tt: ".
				     $Para::Frame::th->{'html'}->error()."\n");
			    }
			    warn "   Using /error.tt\n" if $DEBUG;
			    ($in) = $req->find_template('/error.tt');
			    return( $in, 'tt' );
			}
		    }

		    return( $data, $ext );
		}
	    }
	}

    # If we can't find the filname
    warn "Not found: $template\n";
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

    warn "Sending code: ".join("-", @_)."\n" if $DEBUG > 1;

    if( $Para::Frame::FORK )
    {
	warn "  redirecting to parent\n";
	my $code = shift;
	my $client = $req->client;
	my $val = $client . "\x00" . shift;
	die "Too many args in send_code($code $val @_)" if @_;

	&Para::Frame::Client::connect;
	$Para::Frame::Client::SOCK or die "No socket";
	&Para::Frame::Client::send_to_server($code, \$val);

	# Keep open the SOCK to get response later
#	undef $Para::Frame::Client::SOCK;
	return;
    }

    my $client = $req->client;
#    warn "  to client $client\n";
    $client->send(join "\0", @_ );
    $client->send("\n");
}

sub get_cmd_val
{
    my $req = shift;

    $req->send_code( 'AR-GET', @_ );
    return Para::Frame::get_value( $req->client );
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

	    warn "FALLBACK!\n";
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

	    warn $Para::Frame::th->{'html'}->error()."\n";

	    $req->set_error_template( $error_tt );

	    return 0;

#	    if( not $in )
#	    {
#		warn "Error page not found\n";
#		$client->send( "<p>404: Error page not found: <code>$error_tt</code>\n" );
#	    }
#	    else
#	    {
#		$Para::Frame::th->{'html'}->process($in, $req->{'params'}, \$page )
#		    or die( "Fatal template error for $in: ".
#			    $Para::Frame::th->{'html'}->error()."\n");
#	    }
	};1
    }


    if( $DEBUG > 1 )
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

#	$page .= ("<pre>\n");
#	foreach my $key ( $req->{q}->param() )
#	{
#	    my $value = $req->{q}->param($key);
#	    $value =~ s/\x00/?/g;
#	    $page .= ("   $key:\t$value\n");
#	}
#	foreach my $key ( keys %{$req->{env}} )
#	{
#	    $page .= ("   $key:\t$req->{env}{$key}\n");
#	}
#	$page .= ("</pre>\n");
#
#	$page .= ("<h2>Cookies</h2>");
#	$page .= ($req->cookies->as_html);
    }

    $req->{'page'} = \$page;

    return 1;
}

sub send_output
{
    my( $req ) = @_;

    # Redirect if URL differs from template_url

    warn "  ||Sending output to ".$req->uri."\n";
    warn "  ||Sending the page ".$req->template_uri."\n";

    if( $req->uri ne $req->template_uri )
    {
	$req->forward();
    }
    else
    {
	if( is_utf8( ${ $req->{'page'} } ) )
	{
	    $req->ctype->set_charset("UTF-8");
	    $req->send_headers;
	    binmode( $req->client, ':utf8');
	    $req->client->send( ${ $req->{'page'} } );
	    binmode( $req->client, ':bytes');
	}
	else
	{
	    $req->send_headers;
	    $req->client->send( ${ $req->{'page'} } );
	}
    }
}

sub forward
{
    my( $req, $uri ) = @_;

    $uri ||= $req->template_uri;
    $req->output_redirection($uri);
    $req->s->register_result_page($uri, $req->{'headers'}, $req->{'page'});
}

sub output_redirection
{
    my( $req, $uri_in ) = @_;
    $uri_in or die "URI missing";

    my $uri_out;

    # URI module doesn't support punycode. Bypass module if we
    # redirect to specified domain
    #
    if( $uri_in =~ /^http:\/\/(.*?)(:|\/|$)/ )
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

    warn "  --> Redirect to $uri_out\n";

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

sub set_tt_params
{
    my( $req ) = @_;

    # Real filename
    my $real_filename = $req->filename;
    $real_filename or die "No filename given: ".Dumper($req);

    # Determine the directory
    my( $dir ) = $real_filename =~ /^(.*\/)/;
    $req->{'dir'} = $dir;
    warn "  Setting dir to $dir\n";

    # Special handling of index.tt
    my $me = $req->{'uri'};
    $me =~ s/\bindex.tt$//;
    $req->{'me'} = $me; #store

    # Keep alredy defined params
    $req->add_params({
	'q'               => $req->{'q'},
	'ENV'             => $req->env,
	'me'              => $me,
	'filename'        => $real_filename,
	'dir'             => $dir,
	'browser'         => $req->{'browser'},
	'u'               => $Para::Frame::U,
	'result'          => $req->{'result'},
	'reqnum'          => $req->{'reqnum'},
	'req'             => $req,
    }, 1);
}

sub create_fork
{
    my( $req ) = @_;

    my $sleep_count = 0;
    my $pid;
    my $fh = new IO::File;

    do
    {
	$pid = open($fh, "-|");
	unless( defined $pid )
	{
	    warn "  cannot fork: $!";
	    die "bailing out" if $sleep_count++ > 6;
	    sleep 1;
	}
    } until defined $pid;

    if( $pid )
    {
	# parent
	return $req->register_child( $pid, $fh );
    }
    else
    {
	# child
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
	$req->result->message( $message );
    }

    return 1;
}

sub run_hook
{
    Para::Frame->run_hook(@_);
}


#### TEST job

sub count
{
    my( $s ) = @_;

    $s->{cnt} ++;
    $s->{client}->send( sprintf( "<p>%8d: %4d</p>\n", $s->{env}{REMOTE_PORT}, $s->{cnt}));
    warn "Count $s->{cnt}\n";

    $s->add_job("count") unless $s->{cnt} >= 5;
}


1;
