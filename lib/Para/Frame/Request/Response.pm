package Para::Frame::Request::Response;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Request::Response - Represents the response page for a req

=head1 DESCRIPTION

TODO: Rewrite

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

use 5.010;
use strict;
use warnings;
use utf8;

use Encode;
use Carp qw( croak confess cluck );
use IO::File;
use File::Basename; # exports fileparse, basename, dirname
use File::stat; # exports stat
use File::Slurp; # Exports read_file, write_file, append_file, overwrite_file, read_dir
use Scalar::Util qw(weaken);

use Para::Frame::Reload;
use Para::Frame::Request::Ctype;
use Para::Frame::URI;
use Para::Frame::L10N qw( loc );
use Para::Frame::Dir;
use Para::Frame::File;
use Para::Frame::Renderer::TT;

use Para::Frame::Utils qw( throw debug create_dir chmod_file
                           idn_encode idn_decode datadump catch
                           client_send package_to_module compile
                           validate_utf8 );


#######################################################################

=head1 Constructors

=cut

#######################################################################

=head2 new

This constructor is usually called by L<Para::Frame::Request/set_response>.

params:

  template => used in renderer->new

  req
  site
  language
  is_error_response
  umask
  url
  page
  renderer
  file_may_not_exist
  always_move

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    $args ||= {};

    my $resp = bless
    {
     'req'            => undef,
     'site'           => undef,          ## The site for the request
     'page'           => undef,
     'headers'        => [],             ## Headers to be sent to the client
     'redirect'       => undef,          ## ... to other server
     'ctype'          => undef,          ## The response content-type
     'content'        => undef,          ## Ref to the generated page
     'dir'            => undef,          ## Cached Para::Frame::Dir obj
     'renderer'       => undef,
     'is_error_response' => 0,
     'moved_temporarily' => undef,
     'time'           => time,
    }, $class;

    if( my $req = $args->{req} )
    {
	$resp->{req} = $req;
	weaken( $resp->{'req'} );

	$args->{'site'} ||= $req->site;
	$args->{'language'} ||= $req->language;
    }

    $args->{'resp'} = $resp;

    if( $args->{'is_error_response'} )
    {
	$resp->{'is_error_response'} = 1;
    }

    # NOTE: We set the normalized page

    $args->{'file_may_not_exist'} = 1;
    my $page = $resp->{'page'} = Para::Frame::File->new($args)->normalize;

    unless( $args->{'always_move'} || 0 )
    {
	$page->{'moved_temporarily'} = 1;
    }

    # Renderer sets page to current (normalized) page
    $resp->{'renderer_args'} = $args;

    return $resp;
}


#######################################################################

=head2 desig

=cut

sub desig
{
    my( $resp ) = @_;

    return sprintf "Response to req %d using %s",
      $resp->req->id, $resp->page->desig;
}


#######################################################################

=head2 page

=cut

sub page
{
    my( $resp ) = @_;

#    debug "RETURNING page ".datadump($resp->{'page'},1); ### DEBUG
    return $resp->{'page'};
}


#######################################################################

=head2 page_url_with_query

=cut

sub page_url_with_query
{
    my( $resp ) = @_;

    my $path = $resp->page->url_path_slash;

    my $req = $Para::Frame::REQ;
    if( $path eq $req->original_url_string )
    {
	if( my $query = $req->original_url_params )
	{
	    $path .= "?".$query;
	}
    }

    return $path;
}


#######################################################################

=head2 page_url_with_query_and_reqnum

=cut

sub page_url_with_query_and_reqnum
{
    my( $resp ) = @_;

    my $path = $resp->page->url_path_slash . '?';
    my $req = $Para::Frame::REQ;

#    debug "CALLER query string is ".$req->original_url_params;
#    debug datadump \%ENV;

    if( $path eq $req->original_url_string.'?' )
    {
	if( my $query = $req->original_url_params )
	{
	    $query =~ s/reqnum=[^&]+&?//g;
	    $query =~ s/pfport=[^&]+&?//g;

	    if( length $query )
	    {
		$path .= $query . '&';
	    }
	}
    }

    return $path . 'reqnum='.$req->id.'&pfport='.$Para::Frame::CFG->{'port'};
}


#######################################################################

=head2 page_url_with_reqnum

=cut

sub page_url_with_reqnum
{
    my( $resp ) = @_;

    my $path = $resp->page->url_path_slash;
    my $req = $Para::Frame::REQ;
    return $path . '?reqnum='.$req->id.'&pfport='.$Para::Frame::CFG->{'port'};
}


#######################################################################

=head2 req

=cut

sub req
{
    return $_[0]->{'req'} || $Para::Frame::REQ;
}

#######################################################################

=head2 is_error_response

  $resp->is_error_response

True if this is an error response

=cut

sub is_error_response
{
    return $_[0]->{'is_error_response'} ? 1 : 0;
}

#######################################################################

=head2 is_error

  $resp->is_error

True if this is an error response

=cut

sub is_error
{
    return $_[0]->{'is_error_response'} ? 1 : 0;
}

#######################################################################

=head2 is_no_error

  $resp->is_no_error

True if this is not an error response

=cut

sub is_no_error
{
    return $_[0]->{'is_error_response'} ? 0 : 1;
}

#######################################################################

=head2 set_is_error

  $resp->set_is_error()

  $resp->set_is_error(0)

=cut

sub set_is_error
{
    my $flag = defined( $_[0] ) ? $_[0] : 1;
    $_[0]->{'is_error_response'} = $flag;
}

#######################################################################


=head2 headers

  $resp->headers

Returns: the http headers to be sent to the client as a list of
listrefs of key/val pairs.

=cut

sub headers
{
#    debug "Getting headers ".datadump($_[0]->{'headers'});
    return @{$_[0]->{'headers'}};
}


#######################################################################

=head2 redirection

  $resp->redirection

Returns the page we will redirect to, or undef.

=cut

sub redirection
{
    return $_[0]->{'redirect'};
}


#######################################################################

=head2 set_headers

  $resp->set_headers( [[$key,$val], [$key2,$val2], ... ] )

Same as L</add_header>, but replaces any existing headers.

=cut

sub set_headers
{
    my( $page, $headers ) = @_;

    unless( ref $headers eq 'ARRAY' )
    {
	confess "Faulty headers: ".datadump($headers);
    }

#    debug "Headers set to ".datadump($headers);

    $page->{'headers'} = $headers;
}

#######################################################################

=head2 set_header

  $resp->set_header( $key => $val )

Replaces any existing header with the same key.

Returns:

The number of changes

=cut

sub set_header
{
    my( $resp, $key, $val ) = @_;

    my $changes = 0;
    foreach my $part ( @{$resp->{'headers'}} )
    {
	if( $key eq $part->[0] )
	{
	    $part->[1] = $val;
	    $changes ++;
	}
    }

    unless( $changes )
    {
	push @{$resp->{'headers'}}, [$key,$val];
	$changes ++;
    }

#    debug "Headers set to ".datadump($resp->{'headers'});

    return $changes;
}

#######################################################################


=head2 add_header

  $resp->add_header( [[$key,$val], [$key2,$val2], ... ] )

Adds one or more http response headers.

This sets headers to be used if this page is sent to the client. They
can be changed until they are actually sent.

=cut

sub add_header
{
#    debug "Adding a header";
    push @{ shift->{'headers'}}, [@_];
}

#######################################################################

=head2 ctype

  $resp->ctype

Returns the PRELIMINARY content type to use in the http response, in
the form of a L<Para::Frame::Request::Ctype> object.

It will be initialized from the client request and may be changed
before the response is sent back.

Especieally, it may be changed by the renderer before sending the http
headers.

=cut

sub ctype
{
    my( $resp ) = @_;

    # Needs $REQ

    unless( $resp->{'ctype'} )
    {
	$resp->{'ctype'} = Para::Frame::Request::Ctype->new($resp->req);
    }

    return $resp->{'ctype'};
}


#######################################################################

=head2 redirect

  $resp->redirect( $url )

  $resp->redirect( $url, $permanently_flag )

This is for redirecting to a page not handled by the paraframe.

The actual redirection will be done then all the jobs are
finished. Error in the jobs could result in a redirection to an
error page instead.

The C<$url> should be a full url string starting with C<http:> or
C<https:> or just the path under the curent host.

If C<$permanently_flag> is true, sets the http header for indicating
that the requested page permanently hase moved to this page.

For redirection to a TT page handled by the same paraframe daemon, use
L<Para::Frame::Request/set_response_page>.

=cut

sub redirect
{
    my( $resp, $url, $permanently ) = @_;

   $resp->{'moved_temporarily'} ||= 1 unless $permanently;

    $resp->{'redirect'} = $url;
}


#######################################################################

=head2 set_http_status

  $resp->set_http_status( $status )

Used internally by L</render_output> for sending the http_status of
the response page to the client.

=cut

sub set_http_status
{
    my( $resp, $status ) = @_;
    return 0 if $status < 100;
    return $resp->req->send_code( 'AR-PUT', 'status', $status );
}


#######################################################################

=head2 send_output

  $resp->send_output

SENDER!

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
    my( $resp ) = @_;

    my $req = $resp->req;
    my $page = $resp->page;
    my $client = $req->client;



    my $content = $resp->{'content'};
    my $content_length = length( $content||'' );
#    debug "Resp content has length $content_length";


    # Forward if URL differs from url_path

    if( debug > 2 )
    {
	debug(0,"Sending the page ".$page->url_path);
	unless( $req->error_page_not_selected )
	{
	    debug(0,"An error page was selected");
	}
    }


    # forward if requested url ends in '/index.tt' or if it is a dir
    # without an ending '/'

    my $url_in  = $req->original_url_string;
    my $url_out = $page->url_path_slash;

#    my $url_norm = $page->normalize->url_path_slash;
#    my $url_orig = $req->original_url_string;
#    debug "URL In  $url_in";
#    debug "URL Out $url_out";
#    debug "URL norm $url_norm";
#    debug "URL orig $url_orig";

    if( $url_in ne $url_out )
    {
	debug "!!! $url_in ne $url_out";

#	# Keep query string
#	$url_out = $resp->page_url_with_query_and_reqnum;
	$url_out = $resp->page_url_with_reqnum;
	$resp->forward($url_out);
	return;
    }

    if( $req->header_only )
    {
	my $result;
	if( $req->in_loadpage )
	{
	    $result = "LOADPAGE";
	}
	else
	{
	    $req->cookies->add_to_header;
	    $resp->send_headers;
	    $result = $req->get_cmd_val( 'HEADER' );
	}

	if( $result eq 'LOADPAGE' )
	{
#	    # Keep query string
#	    $url_out = $resp->page_url_with_query_and_reqnum;
	    $url_out = $resp->page_url_with_reqnum;

	    # We should not have come here for a head request!
	    # TODO: fixme

	    $req->session->register_result_page($resp, $url_out);
	    $req->send_code('PAGE_READY', $url_out, loc('page_ready'));
	}
	return;
    }
    else
    {
	my $result;
	if( $req->in_loadpage )
	{
	    $result = "LOADPAGE";
	}
	else
	{
	    $req->cookies->add_to_header;
	    $resp->send_headers;
	    $result = $req->get_cmd_val( 'BODY' );
	}

	if( $result eq 'LOADPAGE' )
	{
	    # Keep query string
	    $url_out = $resp->page_url_with_reqnum;

#	    # Keep query string
#	    $url_out = $resp->page_url_with_query_and_reqnum;

	    $req->cookies->add_to_header;

	    $req->session->register_result_page($resp, $url_out);
	    $req->send_code('PAGE_READY', $url_out, loc('page_ready'));
	}
	elsif( $result eq 'SEND' )
	{
	    my $encoding = $resp->{'encoding'};
	    unless( $encoding )
	    {
		my $ctype = $resp->ctype;
		if( $ctype->type =~ /^text\// )
		{
		    $encoding = $ctype->charset;
		}
	    }

	    my $res = client_send($client, $content,
				  {
				   req => $req,
				   encoding => $encoding,
				  });
	}
	else
	{
	    debug "Strange response '$result'";
	    debug $req->logging->debug_data;
	    confess "Not good";
	}

	return;
    }

#    debug "send_output: done";
}

#######################################################################

=head2 forward

  $resp->forward( $url )

Should only be called AFTER the page has been generated. It's used by
L</send_output> and should not be used by others.

C<$url> must be a normalized url path

To request a forward, just use
L<Para::Frame::Request/set_response_page> before the page is
generated.

To forward to a page not handled by the paraframe, use L</redirect>.

=cut

sub forward
{
    my( $resp, $url_norm ) = @_;

    my $req = $resp->req;

    my $page = $resp->page;
    my $site = $page->site;

    $url_norm ||= $page->url_path_slash;


    debug "Forwarding to $url_norm";

    if( not( $resp->{'content'} or $resp->{'sender'} or $req->header_only ) )
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
	my $referer = $req->referer_path;
	debug "  Referer is $referer";
	debug "  Cancelling forwarding";
	$resp = $req->set_response($req->original_url_string);
#	$page->{url_norm} = $page->orig_url_path;
#	$page->{sys_name} = undef;
	$resp->send_output;
	return;
    }

    # Storing result page BEFORE sending redirection, in case the
    # sending stalls and results in the client requests the result
    # page before send function returns.

    $req->session->register_result_page($resp, $url_norm);

    $resp->sender->send_redirection($url_norm );

}


#######################################################################

=head2 send_redirection

  $resp->send_redirection( $url )

SENDER!

Internally used by L</forward> for sending redirection headers to the
client.

=cut

sub send_redirection
{
    my( $resp, $url_in ) = @_;

    my $req = $resp->req;
    my $page = $resp->page;

    $url_in or die "URL missing";


    $req->cookies->add_to_header;



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
	my $scheme = 'http';
	unless( ref $url_in )
	{
	    $scheme = $req->site->scheme;
	}

	my $url = Para::Frame::URI->new($url_in, $scheme);
	$url->host( idn_encode $req->http_host ) unless $url->host;
	$url->port( $req->http_port ) unless $url->port;
	$url->scheme($scheme);

	$url_out =  $url->canonical->as_string;
    }

    debug(2,"--> Redirect to $url_out");

    my $moved_permanently = $resp->{'moved_temporarily'} ? 0 : 1;


    my $res = $req->get_cmd_val( 'WAIT' );
    if( $res eq 'LOADPAGE' )
    {
	$req->send_code('PAGE_READY', $url_out, loc('page_ready') );
	return;
    }

    if( $moved_permanently )
    {
	debug "MOVED PERMANENTLY";
	$req->send_code( 'AR-PUT', 'status', 301 );
	$req->send_code( 'AT-PUT', 'set', 'Cache-Control', 'public' );
    }
    else # moved temporarily
    {
	$req->send_code( 'AR-PUT', 'status', 302 );
	$req->send_code( 'AT-PUT', 'set', 'Pragma', 'no-cache' );
	$req->send_code( 'AT-PUT', 'set', 'Cache-Control', 'no-cache' );
    }
    $req->send_code( 'AT-PUT', 'set', 'Location', $url_out );

    my $out = "Go to $url_out\n";
    my $length = length( $out );

    $req->send_code( 'AR-PUT', 'content_type', 'text/plain' );

    if( $req->header_only )
    {
	$req->send_code( 'HEADER' );
    }
    else
    {
	$req->send_code( 'AT-PUT', 'set', 'Content-Length', $length );
	$req->send_code( 'BODY' );
	client_send($req->client, $out);
    }
}


#######################################################################

=head2 send_headers

  $resp->send_headers()

Used internally by L</send_output> for sending the HTTP headers to the
client.

The headers themself are not sent in utf8...

=cut

sub send_headers
{
    my( $resp ) = @_;

    my $req = $resp->req;

    my $client = $req->client;
    my $ctype = $resp->ctype;

    $resp->renderer->set_ctype($ctype);

    $req->lang->set_headers;               # lang

    if( my $last_modified = $resp->last_modified )
    {
	$resp->set_header('Last-Modified' => $last_modified->internet_date);
    }

    $ctype->commit;

    my %multiple; # Replace first, but add later headers
    foreach my $header ( $resp->headers )
    {
	if( $multiple{$header->[0]} ++ )
	{
	    debug(3,"Send header add @$header");
	    $req->send_code( 'AT-PUT', 'add', @$header);
	}
	else
	{
	    debug(3,"Send header_out @$header");
	    $req->send_code( 'AT-PUT', 'set', @$header);
	}
    }
}


#######################################################################

=head2 send_stored_result

=cut

sub send_stored_result
{
    my( $resp ) = @_;

    my $req = $resp->req;

    debug 2, "Sending stored page result";

    if( my $content = $resp->{'content'} ) # May be header only
    {
#	debug "  ".validate_utf8($content);

	$resp->send_headers;
	my $res = $req->get_cmd_val( 'BODY' );
	if( $res eq 'LOADPAGE' )
	{
	    die "Was too slow to send the pregenerated page";
	}
	else
	{
	    my $client = $req->client;
	    my $encoding = $resp->{'encoding'};
	    unless( $encoding )
	    {
		my $ctype = $resp->ctype;
		if( $ctype->type =~ /^text\// )
		{
		    $encoding = $ctype->charset;
		}
	    }

#	    my $content_length = length( $$content||'' );
#	    debug "Resp content has length $content_length";

	    client_send($client, $content,
			{
			 req => $req,
			 encoding => $encoding,
			});
	}
    }
    else
    {
	debug 4, "  as HEADER";
	$resp->send_headers;
	my $res = $req->get_cmd_val( 'HEADER' );
	if( $res eq 'LOADPAGE' )
	{
	    die "Was to slow to send the pregenerated page";
	};
    }

    #debug "Sending stored page result: done";
}


#######################################################################

=head2 send_not_modified

  $resp->send_not_modified()


Just as send_output, but sends a header saying that the requested page
has not been modified.

=cut

sub send_not_modified
{
    my( $resp ) = @_;

    debug "Not modified";
    $resp->set_http_status(304);
    $resp->req->set_header_only(1);
    $resp->send_output;

    return 1;
}


#######################################################################

=head2 equals

=cut

sub equals
{
    confess "realy use this?";
    return( $_[0] eq $_[1] );
}

#######################################################################

=head2 set_content

=cut

sub set_content
{

    $_[0]->{'content'} = $_[1];
    return 1;
}

#######################################################################

=head2 set_sender

=cut

sub set_sender
{
    delete $_[0]->{'content'};
    return $_[0]->{'sender'} = $_[1];
}

#######################################################################

=head2 sender

=cut

sub sender
{
    if( $_[0]->{'sender'} )
    {
	return $_[0]->{'sender'};
    }
    else
    {
	return $_[0]; # Send with this response obj
    }
}

#######################################################################

=head2 renderer

  $resp->renderer

Sets the renderer if not yet defined, by calling L</set_renderer>.

Returns: the renderer to be used

=cut

sub renderer
{
    unless( $_[0]->{'renderer'} )
    {
	$_[0]->{'renderer'} = $_[0]->set_renderer();
    }

#    debug "Returning renderer ".ref($_[0]->{'renderer'});

    return $_[0]->{'renderer'};
}

#######################################################################

=head2 set_renderer

  $resp->set_renderer( $renderer, \%args )

Sets the renderer to be uses. Renderer will be chosen from the first
defined among

  1. the given $renderer
  2. $args->{'renderer'}
  3. $q->param('renderer')
  4. $req->dirconfig->{'renderer'}
  5. $resp->page->renderer()

The renderer should be either
 a) a renderer object, which will be returned as is
 b) the module class name of the renderer
    It will be looked for using the each of the appbases. Example; The
    renderer 'TT' will be looked for as Para::Frame::Renderer::TT

Loads and compiles the renderer if necessary

Sets renderer by calling C<new()>

=cut

sub set_renderer
{
    my( $resp, $renderer_in, $args_in ) = @_;

    my $req = $resp->req;
    my $args = $args_in || $resp->{'renderer_args'} || {};
    my $renderer =
      ( $renderer_in
	|| $args->{'renderer'}
	|| $req->q->param('renderer')
	|| $req->dirconfig->{'renderer'}
      );


#    debug "renderer set to $renderer";


    if( not $renderer and $resp->{'page'} )
    {
	$renderer = $resp->{'page'}->renderer( $args );
    }
    elsif( $resp->is_error_response and not $renderer_in )
    {
	# If this is an error response, we should not use a renderer
	# from dirconfig. But always use the renderer given in
	# $renderer_in, since that may be the HTML_Fallback renderer
	# used as a last resort

	$renderer = $resp->{'page'}->renderer( $args );
    }

    if( ref $renderer )
    {
	return $resp->{'renderer'} = $renderer;
    }

    if( $renderer !~ /::/ )
    {
	my $site = $req->site;
	my @errors;
	foreach my $base ( $site->appbases )
	{
	    my $pkg = $base.'::Renderer::'.$renderer;
	    my $mod = package_to_module($pkg);
	    if( eval{compile($mod)} )
	    {
		return $resp->{'renderer'} = $pkg->new($args);
	    }

	    if( $@ )
	    {
		push @errors, $@;
	    }
	}

	foreach my $err ( @errors )
	{
	    $req->result->exception($err);
	}
    }

    unless( $renderer =~ /::Renderer::/i )
    {
	confess "Renderer $renderer is invalid";
    }

    my $mod = package_to_module($renderer);
    compile($mod);
    return $resp->{'renderer'} = $renderer->new($args);
}

#######################################################################

=head2 renerer_if_existing

=cut

sub renderer_if_existing
{
    return $_[0]->{'renderer'};
}

#######################################################################

=head2 render_output

  $resp->render_output()

Returns:

   true if a response was sucessfully generated

   false if response not successfulle generated

=cut

sub render_output
{
    my( $resp ) = @_;

    return eval
    {
	debug 3, "Rendering output";
	# May throw exceptions
	my $renderer = $resp->renderer;
	debug 3, "Using renderer $renderer";

	# May throw exceptions -- May return false
	if( my $result = $renderer->render_output() )
	{
	    return 0 unless ref $result;

	    if( ref $result eq 'SCALAR' )
	    {
		$resp->set_content( $result );
	    }
	    else
	    {
		$resp->set_sender( $result );
	    }
	    debug 3, "Returning true";
	    return 1;
	}
	debug 3, "Returning false";
	return 0;
    };
    debug 3, "Got an error";
    return 0;
}

#######################################################################

=head2 last_modified

  $resp->last_modified()

This method should return the last modification date of the page in
its rendered form.

This function currently only works for css and js pages.

TODO: Work with more than css and js pages.


For other pages, returns undef

=cut

sub last_modified
{
    my( $resp ) = @_;

    my $type = $resp->ctype->type || '';

    if( ($type eq 'text/css') or ($type eq 'application/x-javascript') )
    {
	my $page = $resp->page;
#	my $updated = $page->site->css->updated;
#	debug "CSS updated $updated";
#	my $page_updated = $page->mtime;
#	debug "CSS template updated $page_updated";
#	if( $page_updated > $updated )
	if( $page->is_updated ) # May be a sub-page that was updated
	{
	    return Para::Frame::Time->now();
	}
	return $page->mtime;
    }

    return undef;
}


#######################################################################




1;

=head1 SEE ALSO

L<Para::Frame>

=cut

