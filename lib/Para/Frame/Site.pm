#  $Id$  -*-perl-*-
package Para::Frame::Site;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Web Site class
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

Para::Frame::Site - Represents a particular website

=head1 DESCRIPTION

A Paraframe server can serv many websites. (And a apache server can
use any number of paraframe servers.)

One website can have several diffrent host names, like www.name1.org,
www.name2.org.

The mapping of URL to file is done by Apache. Apache also give a
canonical name of the webserver.

Background jobs may not be coupled to a specific site.

A default site is used then the needed.

Information about each specific site is looked up by the canonical
name that is considered to consist of the apache servern name,
followed by ":$port" if $port != 80. This is what $req->host
returns. (It does NOT include 'http://')

$req->http_host gives the name used in the request, in the same
format.

=cut

use strict;
use Carp qw( croak );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug fqdn uri2file );

our %DATA; # hostname -> siteobj

sub _new
{
    my( $this, $params ) = @_;
    my $class = ref($this) || $this;

    my $site = bless $params, $class;

    if( $site->webhost =~ /^http/ )
    {
	croak "Do not include http in webhost";
    }

    if( $site->webhome =~ /\/$/ )
    {
	croak "Do not end webhome wit a '/'";
    }

    return $site;
}

sub add
{
    my( $this, $params ) = @_;

    my $site = $this->_new( $params );

    my $webhost = $site->webhost;
    debug "Registring site $webhost";

    $DATA{ $webhost } = $site;
    $DATA{'default'} ||= $site;

    foreach my $alias (@{$params->{'aliases'}})
    {
	$DATA{ $alias } = $site;
    }

    return $site;
}

sub get
{
    my( $this, $name ) = @_;

    return $name if UNIVERSAL::isa($name, 'Para::Frame::Site');

    no warnings 'uninitialized';

    debug 3, "Looking up site $name";
    return $DATA{$name} || $DATA{'default'} or
	croak "Either site $name or default is registred";
}

sub webhome     { $_[0]->{'webhome'} || '' }
sub home        { $_[0]->webhome }


sub last_step   { $_[0]->{'last_step'} } # default to undef
sub login_page
{
    return
	$_[0]->{'login_page'} ||
	$_[0]->{'last_step'}  ||
	$_[0]->webhome.'/';
}

sub logout_page
{
    return $_[0]->{'logout_page'} ||
	$_[0]->webhome.'/';
}


sub webhost
{
    return $_[0]->{'webhost'} || fqdn();
}

sub loopback    { $_[0]->{'loopback'} }

sub host        { $_[0]->webhost }

sub backup_host { $_[0]->{'backup_host'} }

sub host_without_port
{
    my $webhost = $_[0]->{'webhost'};

    $webhost =~ s/:\d+$//;
    return $webhost;
}

sub host_with_port
{
    my $host = $_[0]->{'webhost'};

    if( $host =~ /:\d+$/ )
    {
	return $host;
    }
    else
    {
	return $host.":80";
    }
}

sub port
{
    my $webhost = $_[0]->{'webhost'};
    $webhost =~ m/:(\d+)$/;
    return $1 || 80;
}

sub appbase
{
    my( $site ) = @_;

    return $site->{'appbase'} || $Para::Frame::CFG->{'appbase'};
}

sub appfmly
{
    my( $site ) = @_;
    my $family = $site->{'appfmly'} || $Para::Frame::CFG->{'appfmly'};
    unless( ref $family )
    {
	my @list = ();
	if( $family )
	{
	    push @list, $family;
	}
	return $site->{'appfmly'} = \@list;
    }

    return $family;
}

sub approot
{
    my( $site ) = @_;

    return $site->{'approot'} || $Para::Frame::CFG->{'approot'};
}

sub appback
{
    my( $site ) = @_;

    return $site->{'appback'} || $Para::Frame::CFG->{'appback'};
}

sub params
{
    return $_[0]->{'params'};
}

sub languages
{
    return $_[0]->{'languages'} || $Para::Frame::CFG->{'languages'} || [];
}

sub pagepath
{
    my( $site ) = @_;
    my $req = $Para::Frame::REQ;

    my $home = $site->home;
    my$tmpl = $req->template;
    my( $page ) = $tmpl =~  /^$home(.*?)(\.\w\w)?\.\w{2,3}$/;
    if( $page )
    {
	return $page;
    }
    else
    {
	die "Couldn't get pagepath from $tmpl\n";
    }
}

sub htmlsrc # src dir for precompile or for getting inc files
{
    my( $site ) = @_;
    return $site->{'htmlsrc'} ||
      $site->{'is_compiled'} ?
	($site->approot . "/dev") :
	  uri2file($site->home.'/');
}

sub is_compiled
{
    return $_[0]->{'is_compiled'} || 0;
}

sub set_is_compiled
{
    return $_[0]->{'is_compiled'} = $_[1];
}

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
