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
use URI::QueryParam;
use Carp;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame;
use Para::Frame::Reload;
use Para::Frame::Request;
use Para::Frame::Utils qw( throw uri debug );

=head1 DESCRIPTION

For conditional planning inside a page, use param plan_next, like:

  [% jump('Do that', there, plan_next=uri(me, id=id)) %]

This will first "do that there" and then done, continue with $me. If
the 'there' page has a defined next_template META, that will be done
first. But if no such template is given, or there just are an
default_template META, the next submit will follow the route.

Backtracking can also be done by running the action 'backtrack' or
'next_step'.

The plan will only be added to the route if the link is selected.  In
a form, the plan_next field can be modified by javascript. Use a
hidden field for that, like

  [% hidden('plan_next', uri(me, id=id) ) %]

Several steps can be added by just adding up several plan_next hidden
fields.

The steps can be set up during the generation of the page, from TT, by
calling the function plan_next(). 

Select the action L<Para::Frame::Action::mark> for bookmarking the
current page, calling it with all the properties, except the call for
C<mark>.

Use the html form fields C<step_add_params> or C<step_replace_params>
for selecting what values from the submitted form should be passed to
the previous step.

You can also modify the route from actions and other places. Mostly
you will be adding steps.

The [% regret(label) %] macro will create a button that will submit
the form and run the action skip_step().

The [% backstep(label) %] macro will create a button that will submit
the form and run the action next_step().

The backtrack action can be called to request a backtrack, rather than
any of the other methods given above.

'plan_after' can be used in place of plan_next to put a step in the
bottom of the route stack, rather than on top.

=head2 Exported objects

=over

=item L</plan_backtrack>

=item plan : L</plan_next>

=item L</plan_next>

=item L</plan_after>

=back

=head1 METHODS

=cut
    ;

sub on_configure
{
    # Called during compilation
    debug(1,"Importing Route global TT params");

    Para::Frame->add_global_tt_params({
	'plan_backtrack'  => sub{ $Para::Frame::REQ->s->route->plan_backtrack(@_) },
	'plan'            => sub{ $Para::Frame::REQ->s->route->plan_next(@_) },
	'plan_next'       => sub{ $Para::Frame::REQ->s->route->plan_next(@_) },
	'plan_after'      => sub{ $Para::Frame::REQ->s->route->plan_after(@_) },
	'default_step'    => sub{ $Para::Frame::REQ->s->route->default },
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
	$step = URI->new($step) unless UNIVERSAL::isa($step, 'URI');
#	my $uri = URI->new($step);
	debug(1,"!!Plan backtrack to ".$step->path);
	return $step->path . '?backtrack';
    }

    return undef;
}


#######################################################################

=head2 plan_next

  $route->plan_next( @urls )

Insert a new step in the route.  The url should include all the params
that will be set then we backtrack to this step. The step will be
placed on the top of the stack.

=cut

sub plan_next
{
    my( $route, $urls ) = @_;

    $urls = [$urls] unless UNIVERSAL::isa($urls, 'ARRAY');
    my $referer = $Para::Frame::REQ->referer;
    foreach my $url ( @$urls )
    {
	$url = URI->new($url) unless UNIVERSAL::isa($url, 'URI');

	# Used in skip_step...
	$url->query_param_append('caller_page' => $referer )
	    unless $url->query_param('caller_page');

	debug(1,"!!New step in route: $url");

	next if $route->{'route'}[-1] and $url->eq($route->{'route'}[-1]);
	push @{$route->{'route'}}, $url;
    }
}


#######################################################################

=head2 plan_after

  $route->plan_after( @urls )

Insert a new step as the last step in the route.  The url should
include all the params that will be set then we backtrack to this
step. The step will be placed in the bottom of the stack.

=cut

sub plan_after
{
    my( $route, $urls ) = @_;

    $urls = [$urls] unless UNIVERSAL::isa($urls, 'ARRAY');
    my $referer = $Para::Frame::REQ->referer;
    foreach my $url ( @$urls )
    {
	$url = URI->new($url) unless UNIVERSAL::isa($url, 'URI');

	# Used in skip_step...
	$url->query_param_append('caller_page' => $referer )
	    unless $url->query_param('caller_page');

	debug(1,"!!New last step in route: $url");

	next if $route->{'route'}[0] and $url->eq($route->{'route'}[0]);
	unshift @{$route->{'route'}}, $url;
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

    my $route = bless {}, $class;
    $route->clear;
    return $route;
}

sub clear
{
    my( $route ) = @_;

    $route->{'route'} = [];
    $route->{'default'} = $Para::Frame::CFG->{'site'}{'last_step'};
    return 1;
}


#######################################################################

=head2 init

  $route->init

Sets up the route for the present request.  Should be called once from
the application handler.

Calls $route->check_add().

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

    debug(1,"Route has ".$route->steps." steps") if $route->steps;
}


#######################################################################

=head2 check_backtrack

  $route->check_backtrack

Called after each action in the request, if sessions are used.

This will check if a backtrack was requested, by an earlier use of
C<$route->plan_backtrack>.  If a backtrack was requested, takes a step
back by calling C<$route->get_next>.

=cut

sub check_backtrack
{
    my( $route ) = @_;

#    warn "-- check for backtrack\n" if $DEBUG;
    my $req = $Para::Frame::REQ;


    # No backtracking if an error page is selected
    return if $req->error_page_selected;

    # The CGI module doesn't handle query data in URL after a form POST

    if( ($req->q->url_param('keywords')||'') eq 'backtrack' )
    {
	debug(1,"!!Backtracking (because of uri keyword)");
	$route->get_next;
    }
    else
    {
#	warn "-- no backtracking!\n" if $DEBUG;

      CHECK:
	{
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
		    debug(1,"--Removing a step, since it's equal to this one");
		    pop @{$route->{'route'}};
		    redo CHECK; # More steps to remove?
		}
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
	debug(1,"!!Puts a bookmark with query params");
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

This is the method used by the next_step action.

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
	    warn "    replacing param $key with ".$q->param($key)."\n";
	    $args_replace{$key} = [ $q->param($key) ];
	}

	# Modify step withe these params
	my %args_add;
	foreach my $key ( $q->param('step_add_params') )
	{
	    $args_add{$key} = [ $q->param($key) ];
	}

	$route->replace_query( $q, $query );

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

	$req->set_template( $step->path );
	$req->setup_jobs; # Takes care of any run keys in query string

	debug(1,"!!  Initiated new query");
    }
    else
    {
	debug(1,"!!  No more steps in route");
    }
}


#######################################################################

=head2 skip_step

  $route->skip_step

Going back to the referer page of the request setting up the next step in
the route. Giving that page the params that the next step would get,
except the special params like run(), et al. Removes that step from
the route.

The step could have an explicit caller_page that would be used in
place of the referer page.

Using run='mark' will make make the referer the same page as the step.

=cut

sub skip_step
{
    my( $route ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $dest;

    debug(1,"!!  called skip_step");

    if( my $step = pop @{$route->{'route'}} )
    {
	debug(1,"!!    back step one");

	$step = URI->new($step) unless UNIVERSAL::isa($step, 'URI');

	my $caller_page = URI->new($step->query_param('caller_page'))
	    or die "caller_page missing from $step";

#	warn " -- Got caller $caller_page from $step\n";

	# Check if previous steps has the same caller. Remove them as
	# well in that case.

      CHECK:
	while( my $next_step = @{$route->{'route'}}[-1] )
	{
	    $next_step = URI->new($next_step)
		unless UNIVERSAL::isa($next_step, 'URI');

	    my $previous_caller =
		URI->new($next_step->query_param('caller_page'))
		or die "caller_page missing from $step";
	    if( $previous_caller->eq( $caller_page ) )
	    {
		pop @{$route->{'route'}};
		next CHECK;
	    }
	    last CHECK;
	}

	# Now setup the params for the caller

	$route->replace_query( $q, $step->query );

	$dest = $q->param('caller_page')
	    or die "no caller_page for this step";
	debug(1,"!!  Destination set to $dest");

	$route->clear_special_params;
    }
    else
    {
	$route->clear_special_params;

	debug(1,"!!  No more steps in route");
    }

    $dest ||= $route->default || $Para::Frame::CFG->{'site'}{'webhome'};

    $req->set_template($dest);
}


#######################################################################

=head2 remove_step

  $route->remove_step

Remove next step in the route. Do not change uri or query params

=cut

sub remove_step
{
    my( $route ) = @_;

    if( my $step = pop @{$route->{'route'}} )
    {
	debug(1,"!!removed next step");
    }
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


#######################################################################

=head2 steps

  $route->steps

Return the number of steps in route

=cut

sub steps
{
    my( $route ) = @_;

    return scalar( @{$route->{'route'}} );
}


#######################################################################

=head2 default

  $route->default

Returns the default template to use after the last step

=cut

sub default
{
    return $_[0]->{'default'};
}

sub replace_query
{
    my( $this, $q, $query_string ) = @_;

    ###  DANGER  DANGER  DANGER
    # init() is not a public method
    debug(1,"Initiating query with string $query_string");

    $ENV{QUERY_STRING} = $query_string;
    $q->delete_all;
    delete $q->{'.url_param'};
#    warn Dumper \%ENV;
    $q->init($query_string);

#    warn Dumper $q;
    return $q;
}

sub debug_query
{
    ### DEBUG
    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    debug(1,@_);
    debug(1,"url_param is ".$q->url_param('keywords'));
    foreach my $key ( $q->param )
    {
	debug(1,"  $key");
	foreach my $val ( $q->param($key) )
	{
	    debug(1,"    $val");
	}
    }
 }

1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::Manual::Templates>

=cut
