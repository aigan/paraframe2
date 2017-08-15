package Para::Frame::Route;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Route - Backtracking and planning steps in a session

=cut

use 5.012;
use warnings;

use URI::QueryParam;
use Carp qw( cluck confess );

use Para::Frame;
use Para::Frame::Reload;
#use Para::Frame::Request;
use Para::Frame::URI;
use Para::Frame::Utils qw( throw uri debug store_params datadump );
use Para::Frame::List;

=head1 DESCRIPTION

For conditional planning inside a page, use param plan_next, like:

  [% jump('Do that', there, plan_next=uri(me, id=id)) %]

This will first "do that there" and then done, continue with $me. If
the 'there' page has a defined next_template META, that will be done
first. But if no such template is given, or there just are an
default_template META, the next submit will follow the route.

Backtracking can also be done by running the action 'next_step'.

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

The skip_step action can be called to request a backtrack, rather than
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



##############################################################################

=head2 plan_backtrack

  $route->plan_backtrack

Pops the URL from the top of the route stack and returns it.  All
parameters are set to the state of the step.

plan_backtrack() is called in the template header to set next_handler
if non is specified.

TODO: Should make sure that the step only gets called one time.

=cut

sub plan_backtrack
{
    my( $route ) = @_;

    if ( my $step = $route->{'route'}[-1] )
    {
        $step = Para::Frame::URI->new($step) unless UNIVERSAL::isa($step, 'URI');
#	my $url = URI->new($step);
        debug(1,"!!Plan backtrack to ".$step->path);
        return $step->path . '?backtrack=1';
    }

    return undef;
}


##############################################################################

=head2 plan_next

  $route->plan_next( @urls )

Insert a new step in the route.  The url should include all the params
that will be set then we backtrack to this step. The step will be
placed on the top of the stack.

If a C<run> query param exist, it will cause the action to run again
with the same parameters then we backtrack to that step.

Use C<$route->skip_step> to go back without taking the action.

=cut

sub plan_next
{
    my( $route, $urls ) = @_;

    $urls = [$urls] unless UNIVERSAL::isa($urls, 'ARRAY');

    my $caller_url = $route->caller_url;

    foreach my $url_in ( @$urls )
    {
        my $url_norm = $Para::Frame::REQ->normalized_url( $url_in );
        my $url = Para::Frame::URI->new($url_norm);
        $url->query_param_delete('reqnum');
        $url->query_param_delete('pfport');


        # Used in skip_step...
        my $url_clean = $url->clone;
        if ( $url->query_param('caller_page') )
        {
            $url_clean->query_param_delete('caller_page');
        }
        else
        {
            $url->query_param_append('caller_page' => $caller_url );
        }

        debug(1,"!!New step in route: $url");
        debug(1,"!!  with caller_url ".$caller_url);

        if ( my $prev_url_clean = $route->{'route_clean'}[-1] )
        {
            if ( $prev_url_clean->eq( $url_clean ) )
            {
                next;
            }
        }
        push @{$route->{'route'}}, $url;
        push @{$route->{'route_clean'}}, $url_clean;
    }
}


##############################################################################

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

    my $caller_url = $route->caller_url;

    foreach my $url_in ( @$urls )
    {
        my $url_norm = $Para::Frame::REQ->normalized_url( $url_in );
        my $url = Para::Frame::URI->new($url_norm);
        $url->query_param_delete('reqnum');
        $url->query_param_delete('pfport');


        # Used in skip_step...
        my $url_clean = $url->clone;
        if ( $url->query_param('caller_page') )
        {
            $url_clean->query_param_delete('caller_page');
        }
        else
        {
            $url->query_param_append('caller_page' => $caller_url );
        }

        debug(1,"!!New step last in route: $url");

        if ( my $prev_url_clean = $route->{'route_clean'}[-1] )
        {
            if ( $prev_url_clean->eq( $url_clean ) )
            {
                next;
            }
        }
        unshift @{$route->{'route'}}, $url;
        unshift @{$route->{'route_clean'}}, $url_clean;
    }
}




##############################################################################

=head2 caller_url

  $route->caller_url

This will use the post data if this was a post action.

Returns the caller_url, excluding actions, as an L<URI> obj.

=cut

sub caller_url
{
    my( $route ) = @_;

    my $referer = $Para::Frame::REQ->referer_with_query;
    my $caller_url = Para::Frame::URI->new( $referer );

    unless( $caller_url->query )
    {
        # Get the query fron CGI
        $caller_url->query_form_hash(store_params);
    }

    ### See also clear_special_params()
    $caller_url->clear_special_params();
    return $caller_url;
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


##############################################################################

sub clear
{
    my( $route ) = @_;

    $route->{'route'} = [];
    $route->{'route_clean'} = [];
    return 1;
}


##############################################################################

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


##############################################################################

=head2 check_add

  $route->check_add

Takes any query params C<plan_next> and C<plan_after> and add those as
steps by calling the correspongding methods, removing the query
params.

=cut

sub check_add
{
    my( $route ) = @_;

    my $req = $Para::Frame::REQ or confess "No active request";
    my $q = $req->q;

    if ( my @plan_url = $q->param('plan_next') )
    {
        $q->delete('plan_next');
        $route->plan_next(\@plan_url);
    }

    if ( my @plan_url = $q->param('plan_after') )
    {
        $q->delete('plan_after');
        $route->plan_after(\@plan_url);
    }

    debug(1,"Route has ".$route->steps." steps") if $route->steps;
}


##############################################################################

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

    my $req = $Para::Frame::REQ;
    my $page = $req->page;

    # No backtracking if an error page is selected
    return if $req->error_page_selected;

    # The CGI module doesn't handle query data in URL after a form POST
#    debug "-- check for backtrack";
    if ( $req->q->url_param('backtrack') )
    {
        debug(1,"!!Backtracking (because of url param backtrack)");
        $route->get_next;
    }
    else
    {
#	debug "-- no backtracking!";

        ### TODO: Not needed anymore?!?

      CHECK:
        {
            # Remove last step if it's equal to curent place, including params
            my $last_step = $route->{'route'}[-1] or return;
            $last_step = Para::Frame::URI->new($last_step) unless UNIVERSAL::isa($last_step, 'URI');

            if ( $last_step->path eq $page->url_path_slash )
            {
                if ( $last_step->query eq $req->q->query_string )
                {
                    debug(1,"--Removing a step, since it's equal to this one");
                    pop @{$route->{'route'}};
                    redo CHECK; # More steps to remove?
                }
            }
        }

    }
}


##############################################################################

=head2 bookmark

  $route->bookmark( $url_str )

  $route->bookmark()

Same as L</plan_next> but defaults to the current page and the current
query params.

This will add a step to the route with the page and all the query
params we have at the moment, except file uploads.

This will also run the hook after_bookmark which will commit the
DB. The changes up to date is needed for the bookmarking to be
effective.

=cut

sub bookmark
{
    my( $route, $url_str ) = @_;

    my $req = $Para::Frame::REQ;

    $url_str ||= uri($req->page->url_path_slash, store_params);
#    my $norm_url = $req->normalized_url( $url_str || $req->referer_with_query );

    # This should default to the PREVIUS page in most cases
    my $url = Para::Frame::URI->new($url_str );

    debug(1,"!!Adds a bookmark ($url)");

#    if( $url->query_param )
#    {
#	debug(1,"!!  with query params");
#	my @pairs;
#	foreach my $key ( $url->query_param )
#	{
#	    foreach my $val ( $url->query_param($key) )
#	    {
#		push @pairs, $key => $val;
#	    }
#	}
#	$url->query_form( @pairs );
#    }
    $route->plan_next($url);

    Para::Frame->run_hook($req, 'after_bookmark', $url );
}


##############################################################################

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
    my( $route, $break_path ) = @_;

#    Para::Frame::Logging->this_level(4);

    my $req = $Para::Frame::REQ;
    my $page = $req->page;
    my $q = $req->q;

    my $default = $route->default || $page->site->home->url_path_slash;

    if ( my $step = pop @{$route->{'route'}} )
    {
        pop @{$route->{'route_clean'}};

        debug 2, "  Next step is $step";
        $step = Para::Frame::URI->new($step) unless UNIVERSAL::isa($step, 'URI');
        my $query = $step->query || '';
        debug 3, "    step query is $query";

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

        $route->replace_query( $q, $query );

        foreach my $key ( keys %args_replace )
        {
            if ( @{ $args_replace{$key} } )
            {
                debug 1, "replacing param $key with @{$args_replace{$key}}";
                $q->param( $key, @{ $args_replace{$key} } );
            }
            else
            {
                $q->delete($key);
            }
        }

        foreach my $key ( keys %args_add )
        {
            if ( @{ $args_add{$key} } )
            {
                my( @vals ) = $q->param( $key );
                debug 1, "adding to param $key with @vals";
                $q->param( $key, @{ $args_add{$key} }, @vals );
            }
        }

#	debug_query("AFTER");

        $req->set_response( $step->path );
        $req->setup_jobs; # Takes care of any run keys in query string
        $req->add_job('after_jobs');

        debug(1,"!!  Initiated new query");
    }
    elsif ( $break_path )
    {
        debug(1,"!!  No more steps in route");
        debug 1, "!!    Using default step, breaking path";
        $q->delete_all;
        $req->set_response($default);
    }
    else
    {
        debug_query("NO MORE STEPS");
        $q->delete_all;
        debug(1,"!!  No more steps in route");
        if ( $page->url_path_slash ne $req->referer_path )
        {
            debug 1, "!!    Using selected template";
            debug 2, "!!    referer: ".$req->referer_path;
            debug 2, "!!       this: ".$page->url_path_slash;
        }
        else
        {
            debug 1, "!!    Using default step";
            $req->set_response($default);
        }

    }
}


##############################################################################

=head2 skip_step

  $route->skip_step

Going back to the referer page of the request that set up the next
step in the route. Giving that page the params it recieved then it was
called before, except the special params like run(), et al. Removes
that step from the route.

The step could have an explicit caller_page that would be used in
place of the referer page.

Using run='mark' will make make the referer the same page as the step.

=cut

sub skip_step
{
    my( $route ) = @_;

    my $req = $Para::Frame::REQ;
    my $page = $req->page;
    my $q = $req->q;
    my $dest;

    debug(1,"!!  called skip_step");
    debug 1, "  for route ".join("'",@{$route->{'route'}});

    if ( my $step = pop @{$route->{'route'}} )
    {
        pop @{$route->{'route_clean'}};

        debug(1,"!!    back step one");

        $step = Para::Frame::URI->new($step) unless UNIVERSAL::isa($step, 'URI');

        my $caller_page = Para::Frame::URI->new($step->query_param('caller_page'))
          or die "caller_page missing from $step";


        # Now setup the params for the caller

        debug "Got $caller_page";

        $route->replace_query( $q, $caller_page->query );

        $dest = $caller_page->path;
        debug(1,"!!  Destination set to $dest");

        $route->clear_special_params;
    }
    else
    {
        $route->clear_special_params;

        debug(1,"!!  No more steps in route");
    }

    $dest ||= $route->default || $page->site->home->url_path_slash;

    $req->set_response($dest);
}


##############################################################################

=head2 remove_step

  $route->remove_step

Remove next step in the route. Do not change url or query params

=cut

sub remove_step
{
    my( $route ) = @_;

    if ( my $step = pop @{$route->{'route'}} )
    {
        pop @{$route->{'route_clean'}};
        debug(1,"!!removed next step");
    }
}


##############################################################################

=head2 caller_is_next_step

  $route->caller_is_next_step

True if the next steps caller page also is the next step

=cut

sub caller_is_next_step
{
    my( $route ) = @_;

    if ( my $step = $route->{'route'}[-1] )
    {
        $step = Para::Frame::URI->new($step) unless UNIVERSAL::isa($step, 'URI');
        my $caller_page = Para::Frame::URI->new($step->query_param('caller_page'))
          or die "caller_page missing from $step";
        my $next = $step->path;
        my $caller = $caller_page->path;
        debug "Comparing $caller with $next";
        if ( $next eq $caller )
        {
            return 1;
        }
    }
    return 0;
}


##############################################################################

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
    $q->delete('reqnum');
    $q->delete('pfport');
    $q->delete('backtrack');
}


##############################################################################

=head2 steps

  $route->steps

Return the number of steps in route

=cut

sub steps
{
    return scalar @{$_[0]->{'route'}};
}


##############################################################################

# Use steps instead?

sub size
{
    return scalar @{$_[0]->{'route'}};
}


##############################################################################

=head2 default

  $route->default

Returns the default template to use after the last step

Can be undef!

=cut

sub default
{
    return $Para::Frame::REQ->page->site->last_step;
}



##############################################################################

=head2 replace_query

=cut

sub replace_query
{
    my( $this, $q, $query_string ) = @_;

    ###  DANGER  DANGER  DANGER
    # init() is not a public method
    debug(1,"Initiating query with string $query_string");
#    cluck "Empty query_string";

    $ENV{QUERY_STRING} = $query_string;
    $q->delete_all;
    delete $q->{'.url_param'};
    $q->init($query_string) if $query_string;

    return $q;
}



##############################################################################

=head2 debug_query

=cut

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


##############################################################################

=head2 list

=cut

sub list
{
    return Para::Frame::List->new($_[0]->{'route'});
}

##############################################################################

=head2 on_configure

=cut

sub on_configure
{
    # Called during compilation

    Para::Frame->add_global_tt_params
        ({
          'plan_backtrack'  => sub{ $Para::Frame::REQ->s->route->plan_backtrack(@_) },
          'plan'            => sub{ $Para::Frame::REQ->s->route->plan_next(@_) },
          'plan_next'       => sub{ $Para::Frame::REQ->s->route->plan_next(@_) },
          'plan_after'      => sub{ $Para::Frame::REQ->s->route->plan_after(@_) },
          'default_step'    => sub{ $Para::Frame::REQ->s->route->default },
          'route'           => sub{ $Para::Frame::REQ->s->route },
         });
}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::Manual::Templates>

=cut
