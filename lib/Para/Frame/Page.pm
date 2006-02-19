#  $Id$  -*-perl-*-
package Para::Frame::Page;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Page class
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

Para::Frame::Page - Represents a particular page visited

=head1 DESCRIPTION

The $req->{'page'} holds the generated page. But this class just
gathers methods to get info about which page that's currently choosed.

But we may move other things here.

=cut

use strict;
use Carp qw( croak confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );

=head2 obj

The page object, getting all info from the req obj... (Transitional
layout...)

=cut

sub obj
{
    my( $this, $req ) = @_;
    my $class = ref($this) || $this;

    return bless {req=>$req}, $class;
}


#######################################################################

=head1 Accessors

Prefix url_ gives the path of the page in http on the host

Prefix sys_ gives the path of the page in the filesystem

No prefix gives the path of the page relative the site root in url_path

path_tmpl gives the path and filename

path_full gives the preffered URI for the file

path_base excludes the suffix of the filename

dir excludes the trailing slash (and the filename)


 # url_path_tmpl  template
 # url_path_full  template_uri
 # url_path_base
 # url_dir
 # filename
 # basename
 # path_tmpl     site_uri
 # path_full
 # path_base     site_file
 # dir           site_dir
 # sys_path_tmpl
 # sys_path_base
 # sys_dir


=cut

=head2 url_path_tmpl

The path and filename in http on the host.

=cut

sub url_path_tmpl
{
    return $_[0]->{'req'}->template;
}

=head2 url_path_full

The preffered URI for the file in http on the host.

=cut

sub url_path_full
{
    return $_[0]->{'req'}->template_uri;
}

=head2 filename

The template filename without the path.

=cut

sub filename
{
    $_[0]->{'req'}->template =~ /\/([^\/]+)$/
      or die "Couldn't get filename from ".$_[0]->{'req'}->template;
    return $1;
}

=head2 path_base

The path to the template, including the filename, relative the site
home, begining with a slash. But excluding the suffixes of the file
along with the dots.

=cut

sub path_base
{
    my( $page ) = @_;
    my $req = $page->{'req'};

    my $home = $req->site->home;
    my $template = $page->url_path_tmpl;
    $template =~ /^$home(.*?)(\.\w\w)?\.\w{2,3}$/
      or die "Couldn't get path_base from $template under $home";
    return $1;
}

=head2 path_full

The preffered URI for the file, relative the site home, begining with
a slash.

=cut

sub path_full
{
    my( $page ) = @_;
    my $req = $page->{'req'};

    my $home = $req->site->home;
    my $template_uri = $page->url_path_full;
    my( $site_uri ) = $template_uri =~ /^$home(.+?)$/
      or die "Couldn't get site_uri from $template_uri under $home";
    $site_uri =~ s/\.\w\w\.tt$/.tt/; # Remove language part
    return $site_uri;
}

=head2 path_tmpl

The path to the template, including the filename, relative the site
home, begining with a slash.

=cut

sub path_tmpl
{
    my( $page ) = @_;
    my $req = $page->{'req'};

    my $home = $req->site->home;
    my $template = $page->url_path_tmpl;
    my( $site_uri ) = $template =~ /^$home(.+?)$/
      or die "Couldn't get site_uri from $template under $home";
    $site_uri =~ s/\.\w\w\.tt$/.tt/; # Remove language part
    return $site_uri;
}

=head2 dir

The path to the template, excluding the filename, relative the site
home, begining but not ending with a slash.

=cut

sub dir
{
    my( $page ) = @_;
    my $req = $page->{'req'};

    my $home = $req->site->home;
    my $template = $page->url_path_tmpl;
    $template =~ /^$home(.*?)\/[^\/]*$/
      or confess "Couldn't get site_dir from $template under $home";
    return $1;
}

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
