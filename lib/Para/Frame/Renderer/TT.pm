package Para::Frame::Renderer::TT;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2014 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Renderer::TT - Renders a TT page

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( croak confess cluck );
use Template::Exception;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch );
use Para::Frame::L10N qw( loc );
use Scalar::Util qw(weaken);


# Used in set_ctype. Defaults to given ctype and charset UTF-8
our %TYPEMAP =
  (
   'htaccess' =>
   {
    charset => 'Latin1',
   },
   'tt' =>
   {
    type => 'text/html',
   },
   'xtt' =>
   {
    type => 'application/xhtml+xml',
   },
  );


##############################################################################

=head1 Constructors

=cut

##############################################################################

=head2 new

  Para::Frame::Renderer::TT->new( \%args )

args:

  umask
  page
  template
  template_root

C<template_root> is the root of the template used, if not the site
root.  Include files will be search for between the root and the
template dir.

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    $args ||= {};

    my $rend = bless
    {
     'page'           => undef,
     'template'       => undef,
     'incpath'        => undef,
     'params'         => undef,
     'burner'         => undef, ## burner used for page
     'template_root'  => undef,
    };


    my $page = $rend->{'page'} = $args->{'page'}
      or confess "page param missing";

#    debug "=======> Created renderer for page ".$page->url_path;

    $rend->{'params'} = {%$Para::Frame::PARAMS};

    $rend->{'template_root'} = $args->{'template_root'};


    # Cache template -- May throw an exception -- may return undef
    my $tmpl = $rend->{'template'} = $args->{'template'} || $page->template;
    if ( $tmpl and debug)
    {
        debug 2, "Template initialy set to ".$tmpl->sysdesig;
    }

    unless( ref $tmpl )
    {
        if ( $tmpl )
        {
            confess "Template $tmpl not an object";
        }

        ### FIXME
        my $url_path = $page->url_path;
        confess "No req" unless $Para::Frame::REQ;
        my $tried_to_find = $Para::Frame::REQ->{'tried_to_find'} ||= {};
#	    debug datadump($tried_to_find);
        unless ( $tried_to_find->{ $url_path } ++ )
        {
            my $orig_url_path = $Para::Frame::REQ->original_url_string;
#		debug "Comparing $url_path with $orig_url_path";
            if ( $url_path eq $Para::Frame::REQ->original_url_string )
            {
                # Try to find the page
                $Para::Frame::REQ->prepend_action('find_page');
                return $rend;
            }
        }

        ### Must return renderer even if template not found
        # Error will be handled during the actual rendering
#        throw('notfound', "No template found for $url_path");
    }

    return $rend;
}


##############################################################################

=head2 render_output

  $p->render_output()

Burns the page and stores the result.

If the rendering failes, may change the template and URL. The new URL
can be used for another call to this method.

This method is called by L<Para::Frame::Request/after_jobs>.

Returns:

  True on success (the content as a scalar-ref or sender object)

  False on failure

=cut

sub render_output
{
    my( $rend ) = @_;

#    # Maby we have a page generated already
#    return 1 if $resp->{'content'};

#    # Don't burn if this is a HEAD request
#    return 1 if $req->header_only;

    my $out = "";
    my $outref = \$out;

    ### Output page
    my $page = $rend->page;
    unless( $page )
    {
        confess "No page ".datadump($rend,2);
    }

    my $site = $page->site;
    my $home = $site->home_url_path;

    $Para::Frame::REQ->note(loc("Rendering page"));

    my $tmpl = $rend->template;
    unless( $tmpl )
    {
        cluck "template not found";
        throw('notfound', "Couldn't find a template for ".$rend->page->url_path);
    }


    if ( ref $tmpl eq 'Para::Frame::Template' )
    {
        my $in = $tmpl->document;
        my $burner = $rend->burner;
        if ( $burner )
        {
            $rend->set_tt_params;
            $rend->burn($in, $outref) or return 0;
        }
        else
        {
            debug "Getting '$in' as a static page";
            $rend->get_static( $in, $outref ) or return 0;
        }
    }
    elsif ( UNIVERSAL::isa $tmpl, 'Para::Frame::File' )
    {
        $outref = $tmpl->contentref_as_text;

#	my $in = $tmpl->sys_path;
#	debug "Getting '$in' as a static page";
#	$rend->get_static( $in, $outref ) or return 0;
#	utf8::upgrade( $$outref );
    }
    else
    {
        debug datadump($rend,2);
        confess "$tmpl is not a template";
    }


    if ( utf8::is_utf8($$outref) )
    {
        if ( utf8::valid($$outref) )
        {
#	    debug "Render result Marked as valid utf8";

#	    if( $$outref =~ /(V.+?lkommen)/ )
#	    {
#		my $str = $1;
#		my $len1 = length($str);
#		my $len2 = bytes::length($str);
#		debug "  >>$str ($len2/$len1)";
#	    }
        }
        else
        {
            debug "Render result Marked as INVALID utf8";
        }
    }
    else
    {
        debug "Render result NOT Marked as utf8";
    }


#    debug "BURNING DONE";
    return $outref;
}



##############################################################################

=head2 burner

  $p->burner

Returns: the L<Para::Frame::Burner> selected for this page

=cut

sub burner
{
    unless ( $_[0]->{'burner'} )
    {
        my( $rend ) = @_;
        my $ext = $rend->template->suffix;
        $rend->set_burner_by_ext( $ext );
    }

    return $_[0]->{'burner'};
}

##############################################################################

=head2 set_burner_by_type

  $p->set_burner_by_type( $type )

Calls L<Para::Frame::Burner/get_by_type> and store it in the page
object.

Returns: the burner

=cut

sub set_burner_by_type
{
    return $_[0]->{'burner'} =
      Para::Frame::Burner->get_by_type($_[1])
          or die "Burner type $_[1] not found";
}

##############################################################################

=head2 set_burner_by_ext

  $p->set_burner_by_ext( $ext )

Calls L<Para::Frame::Burner/get_by_ext> and store it in the page
object.

Returns: the burner

=cut

sub set_burner_by_ext
{
    return $_[0]->{'burner'} =
      Para::Frame::Burner->get_by_ext($_[1])
          or die "Burner ext $_[1] not found";
}

##############################################################################

=head2 burn

  $p->burn( $in, $out );

Calls L<Para::Frame::Burner/burn> with C<($in, $params, $out)> there
C<$params> are set by L</set_tt_params>.

Returns: the burner

=cut

sub burn
{
    my( $rend, $in, $out ) = @_;
    return $rend->{'burner'}->burn($rend, $in, $rend->{'params'}, $out );
}

##############################################################################

=head2 set_tt_params

The standard functions availible in templates. This is called before
the page is rendered. You should not call it by yourself.

=over

=item browser

The L<HTTP::BrowserDetect> object.  Not in StandAlone mode.

=item ENV

$req->env: The Environment hash (L<http://hoohoo.ncsa.uiuc.edu/cgi/env.html>).  Only in client mode.

=item home

$req->site->home : L<Para::Frame::Site/home>

=item lang

The L<Para::Frame::Request/preffered_language> value.

=item me

Holds the L<Para::Frame::File/url_path_slash> for the page, except if
an L<Para::Frame::Request/error_page_selected> in which case we set it
to L<Para::Frame::Request/original_response> C<page>
C<url_path_slash>.  (For making it easier to link back to the intended
page)

=item page

Holds the L<Para::Frame::Request/page>

=item q

The L<CGI> object.  You will probably mostly use
[% q.param() %] method. Only in client mode.

=item req

The C<req> object.

=item site

The <Para;;Frame::Site> object.

=item u

$req->{'user'} : The L<Para::Frame::User> object.

=back

=cut

sub set_tt_params
{
    my( $rend ) = @_;

    my $req = $Para::Frame::REQ;
    my $page = $rend->page;
    my $site = $page->site or confess "no site: ".$page->sysdesig;
    my $me = $page->url_path_slash;

    if ( $req->is_from_client )
    {
        if ( $req->error_page_selected )
        {
            $me = $req->original_response->page->url_path;
        }

        $rend->add_params({
                           'q'               => $req->{'q'},
                           'ENV'             => $req->env,
                          });
    }

    # Keep alredy defined params  # Static within a request
    $rend->add_params({
                       'page'            => $page,

                       'me'              => $me,

                       'u'               => $Para::Frame::U,
                       'lang'            => $req->language->preferred, # calculate once
                       'req'             => $req,

                       # Is allowed to change between requests
                       'site'            => $site,
                       'home'            => $site->home_url_path,
                      });

    # Add local site params
    if ( $site->params )
    {
        $rend->add_params($site->params);
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

    if ( $keep_old )
    {
        while ( my($key, $val) = each %$extra )
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
        while ( my($key, $val) = each %$extra )
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

=head2 get_static

  $rend->get_static( $in, $pageref )

C<$pageref> must be a scalar ref.

C<$in> must be a L<IO::File> or a filename to be sent to
L<IO::File/new>.

Places the content of the file in C<$pageref>.

Returns: C<$pageref>

=cut

sub get_static
{
    my( $page, $in, $pageref ) = @_;

    $pageref or die "No pageref given";
    my $out = "";

    unless( ref $in )
    {
        $in = IO::File->new( $in );
    }


    if ( ref $in eq 'IO::File' )
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


##############################################################################

=head2 page

=cut

sub page
{
    return $_[0]->{'page'};
}

##############################################################################

=head2 template

May not be defined

=cut

sub template
{

#    debug "Returning template ".$_[0]->{'template'}->sysdesig;
    return $_[0]->{'template'};
}


##############################################################################

=head2 set_template

=cut

sub set_template
{
    debug 2, "Template set to ".$_[1]->sysdesig;
    return $_[0]->{'template'} = $_[1];
}


##############################################################################


=head2 paths

  $p->paths( $burner )

Automaticly called by L<Template::Provider>
to get the include paths for building pages from templates.

Returns: L</incpath>

=cut

sub paths
{
    my( $rend ) = @_;

    unless ( $rend->{'incpath'} )
    {
        my $burner = $rend->burner
          or confess "Page burner not set";
        my $type = $burner->{'type'};

        my $page = $rend->page;
        my $site = $page->site;


        my $path_full = $page->dirsteps->[0];
        my $destroot = $site->home->sys_path;
        my $dir = $path_full;
        unless( $dir =~ s/^$destroot// )
        {
            warn "destroot $destroot not part of $dir";
            warn datadump($page->dirsteps);
            warn datadump($page,2);
            die;
        }
        my $paraframedir = $Para::Frame::CFG->{'paraframe'};

        my @htmlsrc = $site->htmlsrc( $page->is_compiled );

        my $template_root = $rend->{'template_root'};
        if ( ref $template_root )
        {
            $template_root = $template_root->sys_path;
        }

#	my $subdir = 'inc' . $burner->subdir_suffix;

        my @places;
#	if( $site->is_compiled )
#	{
#	    @places =
#	      (
#	       {
#		subdir => $subdir,
#		backdir => '/dev',
#	       },
#	       {
#		subdir => 'inc',
#		backdir => '/html',
#	       },
#	      );
#	}
#	else
#	{
#	    @places =
#	      (
#	       {
#		subdir => $subdir,
#		backdir => '/html',
#	       },
#	      );
#	}

        my $subdir;
        if ( $rend->template->is_compiled($site) )
#	if( $page->is_compiled($site) )
        {
            push @places,
            {
             subdir => $burner->pre_dir,
             backdir => '/dev',
            };

            $subdir = $burner->pre_dir;
        }
        else
        {
            $subdir = $burner->inc_dir;
        }

        push @places,
        {
         subdir => $burner->inc_dir,
         backdir => '/html',
        };


        debug 3, "Creating incpath for $dir under $destroot ($type)";

        my @searchpath;

        if ( $template_root )
        {
            my $tmpl_path = $rend->template->dir->sys_path_slash;
            my $path = $tmpl_path;
            unless( $path =~ s/^$template_root// )
            {
                warn "template root $template_root not part of $path";
                die;
            }

            foreach my $step ( Para::Frame::Utils::dirsteps($path), '/' )
            {
                push @searchpath, $template_root.$step.$subdir.'/';
            }
        }

        my @appbacks = ( $site->approot, @{$site->appback} );

        foreach my $step ( Para::Frame::Utils::dirsteps($dir), '/' )
        {
            push @searchpath, map $_.$step.$subdir.'/', @htmlsrc;

            foreach my $appback ( @appbacks )
            {
                foreach my $place (@places)
                {
                    push @searchpath, ( $appback.$place->{'backdir'}.
                                        $step.$place->{'subdir'}.'/'
                                      );
                }
            }

            foreach my $place (@places)
            {
                push @searchpath, ($paraframedir.$place->{'backdir'}.
                                   $step.$place->{'subdir'}.'/'
                                  );
            }
        }


        $rend->{'incpath'} = [ @searchpath ];


        if ( debug > 2 )
#	if( debug )
        {
            my $incpathstring = join "", map "- $_\n", @searchpath;
            debug "Include path:";
            debug $incpathstring;
        }

    }

    return $rend->{'incpath'};
}


##############################################################################

=head2 set_ctype

=cut

sub set_ctype
{
    my( $rend, $ctype ) = @_;

    my $tmpl = $rend->template;
#    debug "Setting ctype for ".$tmpl->sysdesig;
    if ( my $ext = $tmpl->suffix )
    {
        $ext =~ s/_tt$//;       # Use the destination ext

#	debug "  ext $ext";
        my( $type, $charset );
        if ( my $def = $TYPEMAP{ $ext } )
        {
            $type = $def->{'type'};
            $charset = $def->{'charset'};
#	    debug "  type $type";
#	    debug "  charset $charset";
        }

        $charset ||= $ctype->charset || 'UTF-8';

        # Will keep previous value if non given here
        if ( $type )
        {
            $ctype->set_type($type);
        }

        $ctype->set_charset($charset);
    }

    return $ctype;
}

##############################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    my( $rend ) = @_;

    return datadump($rend,2);
}

##############################################################################


1;

=head1 SEE ALSO

L<Para::Frame>

=cut
