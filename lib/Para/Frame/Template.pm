#  $Id$  -*-cperl-*-
package Para::Frame::Template;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Template class
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

Para::Frame::Template - Represents a Template file

=cut

use strict;
use Carp qw( croak confess cluck );
use List::Uniq qw( uniq ); # keeps first of each value

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch );
use Para::Frame::Dir;
use Para::Frame::File;
use Para::Frame::Burner;
use Para::Frame::Template::Compiled;
use Para::Frame::Time qw( now );


use base qw( Para::Frame::File );

#######################################################################

=head1 Constructors

=cut

#######################################################################

=head2 new

See L<Para::Frame::File>

This constructor is usually called by L</response_page>.

=cut

#######################################################################

=head2 initialize

=cut

sub initialize
{
    my( $tmpl, $args ) = @_;

#    confess("CHECKME: ".datadump($args,2));
#    if( my $burner = $args->{'burner'} )
#    {
#	$tmpl->{'burner'} = $burner;
#    }

    return 1;
}


#######################################################################

sub is_template
{
    return 1;
}

#######################################################################

=head2 title

  $p->title()

Returns the L</template> C<otitle> or L<title> or undef.

=cut

sub title
{
    my( $tmpl ) = @_;

    my $doc = $tmpl->document;

    return $doc->otitle || $doc->title || undef;
}

#######################################################################

sub document
{
    my( $tmpl ) = @_;

    #Cache within a req

    unless( $Para::Frame::REQ->{'document'}{$tmpl} )
    {
#	debug "Getting doc for ".$tmpl->sysdesig;

	my $req = $Para::Frame::REQ;

	my $mod_time = $tmpl->mtime_as_epoch;

	my $burner = Para::Frame::Burner->get_by_ext( $tmpl->suffix );
	my $compdir = $burner->compile_dir;
	my $tmplname = $tmpl->sys_path;

	my $compfile = Para::Frame::Template::Compiled->new_possible_sysfile($compdir.$tmplname);



#	debug "Compdir: $compdir";

	my( $doc, $ltime);

	# 1. Look in memory cache
	#
	if( my $rec = $Para::Frame::Cache::td{$tmplname} )
	{
	    debug("Found in MEMORY");
	    ( $doc, $ltime) = @$rec;
	    if( $ltime <= $mod_time )
	    {
		if( debug > 3 )
		{
		    debug(0,"     To old!");
		    debug(0,"     ltime: $ltime");
		    debug(0,"  mod_time: $mod_time");
		}
		undef $doc;
	    }
	}

	# 2. Look for compiled file
	#
	unless( $doc )
	{
	    if( $compfile->is_plain_file )
	    {
		debug("Found in COMPILED file");

		my $ltime = $compfile->mtime_as_epoch;
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
		    $doc = $compfile->load_compiled();

		    debug("Loading ".$compfile->sys_path);

		    # Save to memory cache (loadtime)
		    $Para::Frame::Cache::td{$tmplname} =
			[$doc, $ltime];
		}
	    }
	}

	# 3. Compile the template
	#
	unless( $doc )
	{
#	    debug("Reading file");
	    $mod_time = time; # The new time of reading file
	    my $tmpltext = $tmpl->content;
	    my $parser = $burner->parser;

#	    debug("Parsing");
	    $req->note("Compiling ".$tmpl->sys_path);
	    my $metadata =
	    {
	     name => $tmplname,
	     time => $mod_time,
	    };
	    my $parsedoc = $parser->parse( $$tmpltext, $metadata )
		or throw('template', "parse error:\nFile: $tmplname\n".
			 $parser->error);

#	    debug("Writing compiled file");
	    $compfile->dir->create;

	    Template::Document->write_perl_file($compfile->sys_path, $parsedoc);
	    $compfile->chmod;
	    $compfile->utime($mod_time);

	    $doc = Template::Document->new($parsedoc)
		or throw('template', $Template::Document::ERROR);

	    # Save to memory cache
	    $Para::Frame::Cache::td{$tmplname} =
		[$doc, $mod_time];
	}

	return $Para::Frame::REQ->{'document'}{$tmpl} = $doc;
    }

    return $Para::Frame::REQ->{'document'}{$tmpl};
}

#######################################################################

=head2 desig

=cut

sub desig
{
    my( $tmpl ) = @_;

    if( $tmpl->exist )
    {
	return $tmpl->title || $tmpl->SUPER::desig();
    }
    else
    {
	return $tmpl->SUPER::desig();
    }
}


#######################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    my( $tmpl ) = @_;

    return $tmpl->SUPER::sysdesig();
}


#######################################################################

=head2 find

  $resp->find($page)

Returns:

A L<Para::Frame::Template> object

=cut

sub find
{
    my( $this, $page ) = @_;
    my $class = ref($this) || $this;

#   debug "Finding template for page ".$page->sysdesig;

    my $req = $Para::Frame::REQ;

    # Handle index.tt
    if( $page->is_dir )
    {
	$page = $page->get_virtual('index.tt');
    }

    my $site = $page->site
      or confess sprintf "Page %s not part of a site", $page->sysdesig;

    # Reasonable default?
    my $lang = $req->language;
    my( @languages ) = $lang->alternatives;
    if( my $langcode = $page->langcode )
    {
	if( $site->supports_language( $langcode ) )
	{
	    @languages = uniq( $langcode, @languages );
	}
    }

    my $dir_sps = $page->dir->sys_path_slash;
    my @searchpath = $dir_sps;

    if( $site->is_compiled )
    {
	push @searchpath, map $_."def/", @{$page->dirsteps};
    }
    else
    {
	my $destroot = $site->home->sys_path;

	my $dir = $dir_sps;
	$dir =~ s/^$destroot// or
	  die "destroot $destroot not part of $dir";

	my $paraframedir = $Para::Frame::CFG->{'paraframe'};

	foreach my $appback (@{$site->appback})
	{
	    push @searchpath, $appback . '/html' . $dir;
	}

	push @searchpath, $paraframedir . '/html' . $dir;

	foreach my $path ( Para::Frame::Utils::dirsteps($dir), '/' )
	{
	    push @searchpath, $destroot . $path . "def/";
	    foreach my $appback (@{$site->appback})
	    {
		push @searchpath, $appback . '/html' . $path . "def/";
	    }
	    push @searchpath,  $paraframedir . '/html' . $path . "def/";
	}
    }

    my $base_name = $page->base_name;
    my $ext_full = '.' . $page->suffix;

    foreach my $path ( @searchpath )
    {
	unless( $path )
	{
	    cluck "path undef (@searchpath)";
	    next;
	}

	# We look for both tt and html regardless of it the file was called as .html
#	debug(0,"Check $path",1);
	die "dir_redirect failed" unless $base_name;

	# Handle dirs
	if( -d $path.$base_name.$ext_full )
	{
	    confess "Found a directory: $path$base_name$ext_full\nShould redirect";
	}


	# Find language specific template
	foreach my $langcode ( map(".$_",@languages),'' )
	{
#	    debug("Check $langcode");
	    my $tmplname = $path.$base_name.$langcode.$ext_full;
#	    debug "Looking at $tmplname";
	    my $tmpl = $class->new_possible_sysfile($tmplname);

	    if( $tmpl->exist )
	    {
		debug("Using $tmplname");
		debug(-2);
		return $tmpl;
	    }
	}
	debug(-1);
    }
    debug(-1);

    # Check if site should be compiled but hasn't been yet
    #
    if( $site->is_compiled )
    {
	my $langcode = $languages[0];
	my $path = "/def/page_not_found.$langcode.tt";
	my $sample_tmpl = $site->get_possible_page($path);
	unless( $sample_tmpl->exist )
	{
	    $site->set_is_compiled(0);
	    debug "*** The site is not yet compiled";
	    die datadump($sample_tmpl); ####### DEBUG
	    return $class->find($page);
	}
    }

    # If we can't find the filname
    debug("Not found: ".$page->sys_path);
    return( undef );
}

#######################################################################


=head2 precompile

TODO: REWRITE

  $page->precompile( \%args )

Send same args as for L</new> for creating the new page from thre
source C<$page>. Also takes:

  arg type defaults to html_pre
  arg language defaults to undef
  arg umask defaults to 02
  arg create_missing_dirs
  arg params
  arg page

Returns: The new compiled page

=cut

sub precompile
{
    my( $dest, $args ) = @_;

    my $req = $dest->req;

    $args ||= {};
    $args->{'umask'} ||= 02;

    my $tmpl = $args->{'template'};
    unless($tmpl)
    {
	$tmpl = $dest->template;
    }

    my $destfile = $dest->sys_path;

    #Normalize page URL
    my $page = $dest->normalize;

    my $dir = $dest->dir->create($args); # With umask

    my $srcfile = $tmpl->sys_path;
    my $fh = new IO::File;
    $fh->open( "$srcfile" ) or die "Failed to open '$srcfile': $!\n";

    my $rend = $page->renderer(undef, {template => $tmpl} );

    $rend->set_burner_by_type($args->{'type'} || 'html_pre');

    $rend->add_params({
		       pf_source_file => $srcfile,
		       pf_compiled_date => now->iso8601,
		       pf_source_version => $tmpl->vcs_version(),
		      });

    if( my $params = $args->{'params'} )
    {
	$rend->add_params($params);
    }

    $rend->set_tt_params;
#    debug "BURNING TO $destfile";
    my $res = $rend->burn( $fh, $destfile );
    $fh->close;

    my $error = $rend->burner->error unless $res;

    $dest->chmod($args);
    $dest->reset();

    if( $error )
    {
	debug "ERROR WHILE PRECOMPILING PAGE";
	debug 0, $error;
	my $part = $req->result->exception($error);
	if( ref $error and $error->info =~ /not found/ )
	{
	    debug "Subtemplate for precompile not found";
	    my $incpathstring = join "", map "- $_\n",
		@{$rend->paths};
	    $part->add_message("Include path is\n$incpathstring");
	}

	die $part;
    }

    return $dest;
}

#######################################################################


1;

=head1 SEE ALSO

L<Para::Frame>

=cut
