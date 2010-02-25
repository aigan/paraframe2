package Para::Frame::Renderer::Email;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009-2010 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Renderer::Email - Renders an email for sending

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( confess cluck );

use Para::Frame::Reload;
use Para::Frame::Email;
use Para::Frame::Utils qw( debug datadump throw validate_utf8 deunicode );

##############################################################################

=head2 new

  Para::Frame::Renderer::Email->new( \%args )

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    $args ||= {};

    my $rend = bless
    {
     'incpath'        => undef,
     'params'         => undef,
     'burner'         => undef,          ## burner used for page
    }, $class;

#    $rend->{'params'} = {%$Para::Frame::PARAMS};

    $rend->{'template'} = $args->{'template'};

    $rend->{'params'} = $args->{'params'} or
      throw 'validation', "No email params given";

    if( $rend->{'email'} = $args->{'email'} )
    {
	unless( $rend->{'email'}->isa('Para::Frame::Email') )
	{
	    throw 'validation', "Given email of wrong type";
	}
    }

    return $rend;
}


##############################################################################

=head2 render_message

  $e->render_message( $to_addr )

If C<dataref> is defined, returns it as the finished message.

Otherwise, concatenates the C<header> with the C<body_encoded>

The body encoding is dependant on the headers and the headers are
dependant on the body.

Unless both C<header> and C<body_encoded> are defined, we will call
L</render_header> with C<$to_addr> that in turn will set the C<header>
and C<body_encoded> properties.

=cut

sub render_message
{
    my( $rend, $to_addr ) = @_;

    my $use_existing_header = 0;
    my $use_existing_body   = 0;
    my $p = $rend->params;


    unless( $to_addr )
    {
	my @to = ref $p->{'to'} eq 'ARRAY' ? @{$p->{'to'}} : $p->{'to'};
	if( scalar(@to) > 1 )
	{
	    confess "More than one to not supported";
	}
	elsif(  scalar(@to) == 0 )
	{
	    confess "No to addr given";
	}
	else
	{
	    $to_addr = Para::Frame::Email::Address->parse( $to[0] );
	}
    }

    if( $rend->{'header_rendered_to'} )
    {
	debug "  Has a previous header for $rend->{header_rendered_to}";
	if( $to_addr eq $rend->{'header_rendered_to'} )
	{
	    $use_existing_header = 1;
	}
    }

    if( $rend->{'static_body'} )
    {
	$use_existing_body = 1;
    }

    if( $use_existing_header and $use_existing_body and $rend->{'dataref'} )
    {
	return $rend->{'dataref'};
    }

    $rend->set_tt_params( $to_addr );

    unless( $use_existing_body and $rend->email )
    {
	if( $p->{'template'} )
	{
	    $rend->render_body_from_template;
	}
	elsif( $p->{'body'} )
	{
	    $rend->render_body_from_plain;
	}
	else
	{
	    throw 'validation', "No content given for email";
	}

 	debug "Rendering body - done";
    }

    unless( $use_existing_header and $rend->email )
    {
	$rend->render_header( $to_addr );
	debug "Rendering header - done";
    }

    $rend->{'dataref'} =  $rend->email->raw;

    ### Validating result
    #
    if( ${$rend->{'dataref'}} =~ /\[%/ )
    {
	debug "EAMIL:\n".${$rend->{'dataref'}};
	die "Failed to parse TT from email";
    }

    return $rend->{'dataref'};
}


##############################################################################

=head2 render_header

The header depends on the body. The body depends on the header.

=cut

sub render_header
{
    my( $rend, $to_addr ) = @_;

    my $p = $rend->params;
    my $e = $rend->email_new([],$rend->{'body'});
    $rend->{'header_rendered_to'} = $to_addr;

    $e->apply_headers_from_params( $p, $to_addr );
    return 1;
}


##############################################################################

=head2 render_body_from_template

=cut

sub render_body_from_template
{
    my( $rend ) = @_;

#    cluck "PF render_body_from_template";

    my $p = $rend->params;

    my $tmpl_in = $p->{'template'}
      or throw 'validation', "No template selected";

    debug "Rendering body from template";

    # Clone params for protection from change
    my %params = %$p;
    my $data_out = "";


#	    debug "Using template \n".$$tmpl_in;
#	    my $rend = Para::Frame::Renderer::TT_noplace->
#	      new({template=>$tmpl_in});
#	    my $burner = $rend->set_burner_by_type('plain');
#	    my $parser = $burner->parser;
#	    my $parsedoc = $parser->parse( $$tmpl_in, {} ) or
#	      throw('template', "parse error: ".$parser->error);
#	    my $doc = Template::Document->new($parsedoc) or
#	      throw('template', $Template::Document::ERROR);
#	    debug "Burning";
#	    $burner->burn( $rend, $doc, \%params, \$data_out );
#	    debug "Burning - done";


    my $data = "";

    my $site = $Para::Frame::REQ->site;
    my $home = $site->home_url_path;

    my $url;
    if( $tmpl_in =~ /^\// )
    {
	$url = $tmpl_in;
    }
    else
    {
	$url = "$home/email/$tmpl_in";
    }

    debug "Rendering body from template $url";

    my $page = Para::Frame::File->new({
				       url => $url,
				       site => $site,
				       file_may_not_exist => 1,
				      });

    my( $tmpl ) = $page->template;
    if( not $tmpl )
    {
	throw('notfound', "Hittar inte e-postmallen $tmpl_in");
    }

    my $trend = $tmpl->renderer;

    my $burner = $trend->set_burner_by_type('plain');

    $params{'page'} = $page;


    $burner->burn( $trend, $tmpl->document, \%params, \$data )
      or throw($burner->error);

#    debug "email before downgrade: ".validate_utf8(\$data);

    $data_out = deunicode($data); # Convert to ISO-8859-1
#    debug "email after downgrade: ".validate_utf8(\$data_out);

    if( $p->{'pgpsign'} )
    {
	pgpsign(\$data_out, $p->{'pgpsign'} );
    }


    if( utf8::is_utf8( $data_out ) )
    {
#	debug "Body before downgrade: ". validate_utf8( $data_out );
	$data_out = deunicode( $data_out ); # Convert to ISO-8859-1
#	debug "Body after downgrade: ". validate_utf8( $data_out );
    }


    $rend->{'body'} = \ $data_out;

#    debug datadump $data_out;
#    die "CHECKME";

    return 1;
}


##############################################################################

=head2 render_body_from_plain

=cut

sub render_body_from_plain
{
    my( $rend ) = @_;

#    cluck "PF render_body_from_template";

    my $p = $rend->params;

    my $data = $p->{'body'}
      or throw 'validation', "No body selected";
    my $data_out = "";

    debug "Rendering body";
#    debug "email before downgrade: ".validate_utf8(\$data);

    $data_out = deunicode($data); # Convert to ISO-8859-1
#    debug "email after downgrade: ".validate_utf8(\$data_out);

    if( $p->{'pgpsign'} )
    {
	pgpsign(\$data_out, $p->{'pgpsign'} );
    }


    if( utf8::is_utf8( $data_out ) )
    {
#	debug "Body before downgrade: ". validate_utf8( $data_out );
	$data_out = deunicode( $data_out ); # Convert to ISO-8859-1
#	debug "Body after downgrade: ". validate_utf8( $data_out );
    }


    $rend->{'body'} = \ $data_out;

#    debug datadump $data_out;
#    die "CHECKME";

    return 1;
}


##############################################################################

=head2 email

=cut

sub email
{
    return $_[0]->{'email'};
}


##############################################################################

=head2 email_new

=cut

sub email_new
{
    my( $rend, $head, $body ) = @_;
    return $rend->{'email'} = Para::Frame::Email->new($head, $body);
}


##############################################################################

=head2 email_clone

=cut

sub email_clone
{
    my( $rend, $eml ) = @_;

    return $rend->{'email'} = $eml->clone
}


##############################################################################

=head2 params

=cut

sub params
{
    return $_[0]->{'params'};
}


##############################################################################

=head2 set_dataref

=cut

sub set_dataref
{
    return $_[0]->{'dataref'} = $_[1];
}


##############################################################################

=head2 set_tt_params

The standard functions availible in templates. This is called before
the page is rendered. You should not call it by yourself.

=over

=item lang

The L<Para::Frame::Request/preffered_language> value.

=item req

The C<req> object.

=item u

$req->{'user'} : The L<Para::Frame::User> object.

=back

Special params are:

=over

=item on_set_tt_params

Will be called as a code reference with C<$param> as the first parameter.

=back

=cut

sub set_tt_params
{
    my( $rend, $to_addr ) = @_;

    my $p = $rend->params;

    my $from_addr = $p->{'from_addr'} or die "No from selected";
    my $subject = $p->{'subject'}  or die "No subject selected";
    my $envelope_from_addr = $p->{'envelope_from_addr'} || $from_addr;

    unless( $to_addr )
    {
	die "no to selected";
    }

    $p->{'to_addr'} = $to_addr;

    debug "Setting to_addr to ".$to_addr;



    my $req = $Para::Frame::REQ;

    # Keep alredy defined params  # Static within a request
    $rend->add_params({
	'u'               => $Para::Frame::U,
	'lang'            => $req->language->preferred, # calculate once
	'req'             => $req,
    });

    if( $p->{'on_set_tt_params'} )
    {
	&{$p->{'on_set_tt_params'}}( $rend );
    }
}


##############################################################################

=head2 add_params

  $resp->add_params( \%params )

  $resp->add_params( \%params, $keep_old_flag )

Adds template params. This can be variabls, objects, functions.

If C<$keep_old_flag> is true, we will not replace existing params with
the same name.

=cut

sub add_params
{
    my( $resp, $extra, $keep_old ) = @_;

    my $param = $resp->{'params'} ||= {};

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
	    debug(3, "Add TT param $key: $val");
	}
     }
}


##############################################################################


1;

=head1 SEE ALSO

L<Para::Frame>

=cut
