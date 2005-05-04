#  $Id$  -*-perl-*-
package Para::Frame::Route;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Route handling
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

Para::Frame::Route - Backtracking and planning steps in a session

=cut

use strict;
use Data::Dumper;
use URI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame;
use Para::Frame::Reload;
use Para::Frame::Request;
use Para::Frame::Utils qw( throw uri referer );

=head1 DESCRIPTION

For conditional planning inside a page, use param plan, like:

  [% jump('Do that', there, plan_next=uri(me, id=id)) %]

This will first "do that there" and then done, continue with $me.

The plan will only be added to the route if the link is selected.
In a form, the plan can be modified by javascript

For unconditional planning of later steps, call function plan_next

Select the action L<Para::Frame::Action::mark> for bookmarking the
current page, calling it with all the properties, except the call for
C<mark>.


=head3 TODO

There is a lot left to document.  There is many ways to use routes.

Use the html form fields C<step_add_params> or C<step_replace_params>
for selecting what values from the submitted form should be passed to
the previous step.


=head2 Exported objects

=over

=item L</plan_backtrack>

=item plan : L</plan_next>

=item L</plan_next>

=item L</plan_after>

=back

=head1 METHODS

=cut


sub on_startup
{
    # Called during compilation
    warn "  Importing Route global TT params\n";

    Para::Frame->add_global_tt_params({
	'plan_backtrack'  => sub{ $Para::Frame::REQ->s->route->plan_backtrack(@_) },
	'plan'            => sub{ $Para::Frame::REQ->s->route->plan_next(@_) },
	'plan_next'       => sub{ $Para::Frame::REQ->s->route->plan_next(@_) },
	'plan_after'      => sub{ $Para::Frame::REQ->s->route->plan_after(@_) },
	'route'           => sub{ $Para::Frame::REQ->s->route->{'route'} },
    });
}

#######################################################################

=head2 plan_backtrack

  $route->plan_backtrack

Pops the URL from the top of the route stack and returns it.  All
parameters are set to the state of the step.

plan_backtrack() is called in the template header to set next_handler
if non is specified.

=cut

sub plan_backtrack
{
    my( $route ) = @_;

    if( my $step = $route->{'route'}[-1] )
    {
	warn "  Next step is $step\n";
	$step = URI->new($step) unless UNIVERSAL::isa($step, 'URI');
#	my $uri = URI->new($step);
	warn "  Plan backtrack to ".$step->path."\n";
	return $step->path . '?backtrack';
    }

    return $route->{'default'} || undef;
}


#######################################################################

=head2 plan_next

  $route->plan_next( @urls )

Insert a new step in the route.  The url should include all the params
that will be set then we backtrack to this step.

=cut

sub plan_next
{
    my( $route, $urls ) = @_;

    $urls = [$urls] unless UNIVERSAL::isa($urls, 'ARRAY');
    foreach my $url ( @$urls )
    {
	$url = URI->new($url) unless UNIVERSAL::isa($url, 'URI');
	warn "  !! New step in route: $url\n";
#	warn "  !! New step in route\n";
	push @{$route->{'route'}}, $url->as_string;
    }
}


#######################################################################

=head2 plan_after

  $route->plan_afterplan_next( @urls )

Insert a new step as the last step in the route.  The url should
include all the params that will be set then we backtrack to this
step.

=cut

sub plan_after
{
    my( $route, $urls ) = @_;

    $urls = [$urls] unless UNIVERSAL::isa($urls, 'ARRAY');
    foreach my $url ( @$urls )
    {
	$url = URI->new($url) unless UNIVERSAL::isa($url, 'URI');
	warn "  !! New last step in route: $url\n";
	unshift @{$route->{'route'}}, $url->as_string;
    }
}


#########################################################################
################################  Constructors  #########################

=head2 new

Construct the route object.  This is used internally from the Session
object.  Calling the $session->route will return the route object or
create it if not yet existing.

The $route->init() method is not called by new() and should be called
once for each request.

=cut

sub new
{
    my( $class ) = @_;

    my $route = bless
    {
	route => [],
	default => undef,
    }, $class;

    return $route;
}

sub clear
{
    my( $route ) = @_;

    $route->{'route'} = [];
    $route->{'default'} = undef;
    return 1;
}


#######################################################################

=head2 init

  $route->init

Sets up the route for the present request.  Should be called once from
the application handler.

Adds the tempalte methods and calls $route->check_add().

=cut

sub init
{
    my( $route ) = @_;

    $route->check_add;
}


#######################################################################

=head2 check_add

  $route->check_add

Takes any query params C<plan_next> and C<plan_after> and add those as
steps by calling the correspongding methods, removing the query
params.

=cut

sub check_add
{
    my( $route ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $uri = $req->uri;

    if( my @plan_url = $q->param('plan_next') )
    {
	$q->delete('plan_next');
	$route->plan_next(\@plan_url);
    }

    if( my @plan_url = $q->param('plan_after') )
    {
	$q->delete('plan_after');
	$route->plan_after(\@plan_url);
    }

    warn "  Route has ".$route->steps." steps\n" if $route->steps;
}


#######################################################################

=head2 check_backtrack

  $route->check_backtrack

Called after each action in the request, if sessions are used.

This will check if a backtrack was requested, by an earlier use of
C<$route->plan_backtrack>.  If a backtrack was requested, takes a step
back by calling C<$route->next_step>.

=cut

sub check_backtrack
{
    my( $route ) = @_;

    warn "-- check for backtrack\n";
    my $req = $Para::Frame::REQ;


    # No backtracking if an error page is selected
    return if $req->error_page_selected;

    # The CGI module doesn't handle query data in URL after a form POST

    if( ($req->q->url_param('keywords')||'') eq 'backtrack' )
    {
	warn "  !! Backtracking!\n";
	$route->get_next;
    }
    else
    {
	warn "-- no backtracking!\n";

	# Remove last step if it's equal to curent place, including params
	my $last_step = $route->{'route'}[-1];
	$last_step = URI->new($last_step) unless UNIVERSAL::isa($last_step, 'URI');

#	my $lsp = $last_step->path;
#	my $qsp = $req->uri;
#	warn "-- comparing $lsp to $qsp\n";

	if( $last_step->path eq $req->template_uri )
	{
#	    my $lsq = $last_step->query;
#	    my $qsq = $req->q->query_string;
#	    warn "-- comparing $lsq to $qsq\n";

	    if( $last_step->query eq $req->q->query_string )
	    {
		warn "-- Removing a step, since it's equal to this one\n";
		pop @{$route->{'route'}};
	    }
	}

    }
}


#######################################################################

=head2 bookmark

  $route->bookmark( $uri_str )

Put a bookmark on the page C<$uri_str>, defaulting to the current
page.

This will add a step to the route with the page and all the query
params we have at the moment, except file uploads.  If a C<run> query
param exist, it will cause the action to run again with the same
parameters then we backtrack to that step.

Use C<$route->skip_step> to go back without taking the action.

=cut

sub bookmark
{
    my( $route, $uri_str ) = @_;

    my $req = $Para::Frame::REQ;

    # Should be called with normalized uri; (No 'index.tt' part)

    # This should default to the PREVIUS page in most cases
    my $uri = URI->new($uri_str || $req->uri );
    my $q = $req->q;

    if( $q->param )
    {
	warn "  !! Puts a bookmark with query params\n";
	my @pairs;
	foreach my $key ( $q->param )
	{
	    foreach my $val ( $q->param($key) )
	    {
		# Skip complex values, like file upload
		next if ref $val;

		push @pairs, $key => $val;
	    }
	}
	$uri->query_form( @pairs );
    }
    $route->plan_next($uri);
}


#######################################################################

=head2 get_next

  $route->get_next

Take the next step in the route. That is; one step back.

Set upp all the params for that step.  The query param
C<step_replace_params> can be repeated, each param naming the name of
antoher param given, that sould replace the corresponding param in the
stpep.  The query param C<step_add_params> adds the corresponding
parameter values rather than replacing them.

The template is set to that of the step.

=cut

sub get_next
{
    my( $route ) = @_;

    if( my $step = pop @{$route->{'route'}} )
    {
#	warn "  Next step is $step\n";
	$step = URI->new($step) unless UNIVERSAL::isa($step, 'URI');
	my $query = $step->query || '';
#	warn "    step query is $query\n";

	my $req = $Para::Frame::REQ;
	my $q = $req->q;

	# Modify step withe these params
	my %args_replace;
	foreach my $key ( $q->param('step_replace_params') )
	{
	    $args_replace{$key} = [ $q->param($key) ];
	}

	# Modify step withe these params
	my %args_add;
	foreach my $key ( $q->param('step_add_params') )
	{
	    $args_add{$key} = [ $q->param($key) ];
	}

#	debug_query("BEFORE");

	$q->delete_all;
	###  DANGER  DANGER  DANGER
	# init() is not a public method
#	debug_query("DELETED");
	warn "Initiating query with string $query\n";
	$q->init($query);

	foreach my $key ( keys %args_replace )
	{
	    $q->param( $key, @{ $args_replace{$key} } );
	}

	foreach my $key ( keys %args_add )
	{
	    my @vals = $q->param( $key );
	    $q->param( $key, @{ $args_add{$key} }, @vals );
	}

#	debug_query("AFTER");

	$req->set_uri( $step->path );

	warn "  !!  Initiated new query\n";
    }
    else
    {
	warn "  !!  No more steps in route\n";
    }
}


#######################################################################

=head2 skip_step

  $route->skip_step

Going back, but skipping one step in the route.  Just jumping one step
or taking the step for initial param values but uses it for finding
the previous template.

=cut

sub skip_step
{
    my( $route ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $dest;

    warn "  !!  called skip_step\n";

    if( my $step = pop @{$route->{'route'}} )
    {
	warn "  !!    back step one\n";

	# Use the second step if existing
	#
	if( @{$route->{'route'}} )
	{
	    warn "  !!    back step two\n";
	    return $route->get_next;
	}

	$step = URI->new($step) unless UNIVERSAL::isa($step, 'URI');
	my $query = $step->query;

	$q->delete_all;
	###  DANGER  DANGER  DANGER
	# init() is not a public method
	$q->init($query);
	warn "  !!    Initiated new query\n";

	$dest = $q->param('previous') || '';
	warn "  !!    Destination set to $dest\n";

	$route->clear_special_params;
    }
    else
    {
	$route->clear_special_params;

	warn "  !!  No more steps in route\n";
    }

    $dest ||= $route->default || $req->app->home;

    $req->forward($dest);
}

sub clear_special_params
{
    my $q = $Para::Frame::REQ->q;

    # We want to get the qyery params as default values for the
    # form. Stripping out all special params.
    #
    $q->delete('run');
    $q->delete('section');
    $q->delete('renderer');
    $q->delete('destination');
}

sub steps
{
    my( $route ) = @_;

    return scalar( @{$route->{'route'}} );
}

sub debug_query
{
    ### DEBUG
    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    warn("@_\n");
    foreach my $key ( $q->param )
    {
	warn "\t$key\n";
	foreach my $val ( $q->param($key) )
	{
	    warn "\t\t$val\n";
	}
    }
 }

1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::Manual::Templates>

=cut
