#  $Id$  -*-cperl-*-
package Para::Frame::Request::Response;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Request Tesponse class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2007 Jonas Liljegren.  All Rights Reserved.
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

use strict;
use utf8;

use Carp qw( croak confess cluck );
use IO::File;
use Encode qw( is_utf8 decode );
use File::Basename; # exports fileparse, basename, dirname
use File::stat; # exports stat
use File::Slurp; # Exports read_file, write_file, append_file, overwrite_file, read_dir
use Scalar::Util qw(weaken);

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
use Para::Frame::File;
use Para::Frame::Renderer::TT;


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
    }, $class;

    if( my $req = $args->{req} )
    {
	$resp->{req} = $req;
	weaken( $resp->{'req'} );

	$args->{'site'} ||= $req->site;
	$args->{'language'} ||= $req->language;

	if( my $q = $req->q )
	{
	    $args->{'renderer'} ||= $q->param('renderer');
	}
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

sub page
{
    my( $resp ) = @_;

#    debug "RETURNING page ".datadump($resp->{'page'},1); ### DEBUG
    return $resp->{'page'};
}


#######################################################################

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

sub page_url_with_query_and_reqnum
{
    my( $resp ) = @_;

    my $path = $resp->page->url_path_slash;
    my $req = $Para::Frame::REQ;

#    debug "CALLER query string is ".$req->original_url_params;
#    debug datadump \%ENV;

    if( $path eq $req->original_url_string )
    {
	if( my $query = $req->original_url_params )
	{
	    return $path . "?".$query.'&reqnum='.$req->id;
	}
	else
	{
	    return $path . '?reqnum='.$req->id;
	}
    }
    else
    {
	return $path . '?reqnum='.$req->id;
    }
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

  $resp->ctype( $content_type )

Returns the content type to use in the http response, in the form
of a L<Para::Frame::Request::Ctype> object.

If C<$content_type> is defiend, sets the content type using
L<Para::Frame::Request::Ctype/set>.

=cut

sub ctype
{
    my( $resp, $content_type ) = @_;

    # Needs $REQ

    unless( $resp->{'ctype'} )
    {
	$resp->{'ctype'} = Para::Frame::Request::Ctype->new($resp->req);
    }

    if( $content_type )
    {
	$resp->{'ctype'}->set( $content_type );
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
#    my $url_norm = $req->normalized_url( $url );


#    debug "URL In  $url_in";
#    debug "URL Out $url_out";

#    debug "Original url: $url";

    if( $url_in ne $url_out )
    {
	debug "!!! $url_in ne $url_out";

	# Keep query string
	$url_out = $resp->page_url_with_query_and_reqnum;

	$req->session->register_result_page($resp, $url_out);
	$resp->forward($url_out);
    }
    else
    {
	if( $req->header_only )
	{
	    my $result;
	    if( $req->in_loadpage )
	    {
		$result = "LOADPAGE";
	    }
	    else
	    {
		$resp->send_headers;
		$result = $req->get_cmd_val( 'HEADER' );
	    }

	    if( $result eq 'LOADPAGE' )
	    {
		# Keep query string
		$url_out = $resp->page_url_with_query_and_reqnum;

		$req->session->register_result_page($resp, $url_out);
		$req->send_code('PAGE_READY', $url_out);
	    }
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
		binmode( $req->client, ':utf8');
		$resp->send_headers;
		$result = $req->get_cmd_val( 'BODY' );
	    }

	    if( $result eq 'LOADPAGE' )
	    {
		# Keep query string
		$url_out = $resp->page_url_with_query_and_reqnum;

		$req->session->register_result_page($resp, $url_out);
		$req->send_code('PAGE_READY', $url_out);
	    }
	    elsif( $result eq 'SEND' )
	    {
		$resp->send_in_chunks( $resp->{'content'} );
	    }
	    else
	    {
		binmode( $req->client, ':bytes');
		die "Strange response '$result'";
	    }

	    binmode( $req->client, ':bytes');
	}
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

    if( not( $resp->{'content'} or $req->header_only ) )
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

    $resp->output_redirection($url_norm );

    $req->session->register_result_page($resp);
}


#######################################################################

=head2 output_redirection

  $resp->output_redirection( $url )

Internally used by L</forward> for sending redirection headers to the
client.

=cut

sub output_redirection
{
    my( $resp, $url_in ) = @_;

    my $req = $resp->req;
    my $page = $resp->page;

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
	$req->send_code('PAGE_READY', $url_out );
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
	$req->client->send( $out );
    }
}


#######################################################################

=head2 send_headers

  $resp->send_headers()

Used internally by L</send_output> for sending the HTTP headers to the
client.

=cut

sub send_headers
{
    my( $resp ) = @_;

    my $req = $resp->req;

    my $client = $req->client;

    my $ctype = $resp->ctype;
    unless( $ctype->is_defined )
    {
	my $ctype_str = $resp->renderer->content_type_string
	  || $req->original_content_type_string || 'text/plain';
	$ctype->set($ctype_str);
    }

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

=head2 send_in_chunks

  $resp->send_in_chunks( $dataref )

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
    my( $resp, $dataref ) = @_;

    my $req = $resp->req;

    my $client = $req->client;
    my $length = length($$dataref);
    if( debug > 1 )
    {
	my $length2 = bytes::length($$dataref);
	debug(1,"Sending $length chars/$length2 bytes of data to client");
    }

    my $total = 0;
    my $errcnt = 0;

    unless( $length )
    {
	debug "We got nothing to send (for req $req)";
	return 1;
    }

    eval
    {
	my $chunk = 16384; # POSIX::BUFSIZ * 2
	my $sent = 0;
	for( my $i=0; $i<$length; $i+= $sent )
	{
	    debug(3,"  Transmitting chunk from $i\n");
	    $sent = $client->send( substr $$dataref, $i, $chunk );
	    if( $sent )
	    {
		debug(3, "  Sent $sent chars");
		$total += $sent;
		$errcnt = 0;
	    }
	    else
	    {
		if( $req->cancelled )
		{
		    debug("Request was cancelled. Giving up");
		    return $total;
		}

		debug(1,"  Resending chunk $i");

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

	debug(2, "Transmitted $total chars to client");
    };
    if( $@ )
    {
	my $err = catch($@);
	unless( $Para::Frame::REQUEST{$client} )
	{
	    return 0;
	}

	debug "Failed to transmit to client";
	debug $err->as_string;
	return 0;
    }

    return $total;
}



#######################################################################

=head2 send_stored_result

=cut

sub send_stored_result
{
    my( $resp ) = @_;

    my $req = $resp->req;

    debug 0, "Sending stored page result";

    if( my $content = $resp->{'content'} ) # May be header only
    {
	binmode( $req->client, ':utf8');

	if( utf8::is_utf8($$content) )
	{
	    if( utf8::valid($$content) )
	    {
#		debug "  as valid utf8";
	    }
	    else
	    {
		debug "  as INVALID utf8";
	    }
	}
	else
	{
	    debug "  NOT Marked as utf8";
	}


	$resp->send_headers;
	my $res = $req->get_cmd_val( 'BODY' );
	if( $res eq 'LOADPAGE' )
	{
	    die "Was to slow to send the pregenerated page";
	}
	else
	{
	    $resp->send_in_chunks( $content );
	}

	binmode( $req->client, ':bytes');
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
#    return $_[0]->{'content'} = $_[1];

    $_[0]->{'content'} = $_[1];

#    if( utf8::is_utf8(${$_[0]->{'content'}}) )
#    {
#	if( utf8::valid(${$_[0]->{'content'}}) )
#	{
##	    debug "3Render result Marked as valid utf8";
#	}
#	else
#	{
#	    debug "3Render result Marked as INVALID utf8";
#	}
#    }
#    else
#    {
#	debug "3Render result NOT Marked as utf8";
#    }

    return 1;
}

#######################################################################

=head2 renderer

  $tmpl->renderer

Returns: the renderer to be used, if not the standard renderer

=cut

sub renderer
{

# Args are sent to new()
    unless( $_[0]->{'renderer'} )
    {
	my( $resp ) = @_;
	my $args = $resp->{'renderer_args'} || {};
	$args->{'page'} = $resp->page;

	return $resp->{'renderer'}
	    = $resp->{'page'}->renderer($args->{'renderer'}, $args);
    }

    return $_[0]->{'renderer'};
}

#######################################################################

=head2 set_rendere

=cut

sub set_renderer
{
    return $_[0]->{'renderer'} = $_[1];
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

=cut

sub render_output
{
    my( $resp ) = @_;

    return eval
    {
#	debug "Rendering output";
	# May throw exceptions
	my $renderer = $resp->renderer;
#	debug "Using renderer $renderer";
	my $content = "";

	# May throw exceptions -- May return false
	if( $renderer->render_output(\$content) )
	{
#	    debug "Storing content";
	    $resp->set_content( \$content );
#	    debug "Returning true";
	    return 1;
	}
#	debug "Returning false";
	return 0;
    };
#    debug "Got an error";
    return 0;
}

#######################################################################

=head2 last_modified

  $resp->last_modified()

This method should return the last modification date of the page in
its rendered form.

This function currently only works for CSS pages.

For other pages, returns undef

=cut

sub last_modified
{
    my( $resp ) = @_;

    if( $resp->ctype->is('text/css') )
    {
	my $page = $resp->page;
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




1;

=head1 SEE ALSO

L<Para::Frame>

=cu
