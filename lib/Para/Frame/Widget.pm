#  $Id$  -*-perl-*-
package Para::Frame::Widget;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Common template widgets
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

Para::Frame::Widget - Common template widgets

=cut

use strict;
use Carp;
use Template 2;
use locale;
use POSIX qw(locale_h strftime);
use Data::Dumper;
use IO::File;
use Time::Piece;
use Date::Manip;
use Clone qw( clone );
use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( trim throw );

=head1 DESCRIPTION

C<Para::Frame::Widget> is an optional module.  It will not be used unless
the application calls it or uses the default application init method.

Widgets can be implemented either as exported objects (functions /
methods / variables) or as templates for inclusion or defined template
macros.

These are the standard widgets defined as Perl code.  See also the
standard L<Para::Frame::TT::components>.

=head1 Exported objects

=over

=item L</selectorder>

=item L</slider>

=item L</jump>

=item L</uri>

=item L</submit>

=item L</go>

=item L</go_js>

=item L</forward>

=item L</forward_url>

=item L</alfanum_bar>

=item L</rowlist>

=item L</list2block>

=item L</preserve_data>

=item L</param_includes>

=item L</hidden>

=item L</input>

=item L</textarea>

=item L</filefield>

=back

=cut

#######################################################################

=head2 slider

  slider( %attrs )

Draws a series of radiobuttons representing a range of numerical
values.

field   = form field name

min     = value of the leftmost radiobutton (default is 0)

max     = value of the rightmost radiobutton (default is 100)

number  = number of buttons (default is 6)

current = The current value.  The nearest button will be selected.

The $current value will be taken from query param $field or $current
or 0, in turn.

=cut

sub slider
{
    my( $attr ) = @_;

    my $field   = $attr->{'field'}      or die "param field missing";
    my $min     = $attr->{'min'}  || 0;
    my $max     = $attr->{'max'}    || 100;
    my $number  = $attr->{'number'}    || 6;
    my $default = $attr->{'default'}; # Could be undef
    my $current = $Para::Frame::REQ->q->param($field) || $attr->{'current'} || $default;

    my @val = ();
    my( @checked ) = ('')x$number;
    my $delta = ($max - $min ) / ($number-1);
    my $widget = "";
    for( my $i=0; $i<$number; $i++ )
    {
	$val[$i] = int($min + $i*$delta);
	if( defined $current and ($current >=  ($min + $i*$delta - $delta/2)) and
	      ($current <  ($min + $i*$delta + $delta/2)))
	{
	    $checked[$i] = "checked";
	}

	$widget .= "<input type=\"radio\" name=\"$field\" value=\"$val[$i]\" $checked[$i]>\n";
    }
    return $widget;
}


#######################################################################

=head2 jump

  jump( $label, $template, %attrs )

Draw a link to $template with text $label and query params %attrs.

A 'target' attribute will set the target frame for the link.

A 'onClick' attribute will set the corresponding tag attribute.

A 'class' attribute will set the class for the link.

If no class is set, the class will be 'selected' if the link goes to
the current page.  To be used with CSS for marking the current page in
menues.

Default $label = '???'

Default $template = '', witch would be the current template

=cut

sub jump
{
    my( $label, $template, $attr ) = @_;

    $label = '???' unless length $label;
    $attr ||= {};

    my $extra = "";
    if( my $val = delete $attr->{'target'} )
    {
	$extra .= " target=\"$val\"";
    }
    if( my $val = delete $attr->{'id'} )
    {
	$extra .= " id=\"$val\"";
    }
    if( my $val = delete $attr->{'onClick'} )
    {
	$extra .= " onClick=\"$val\"";
    }

    my $class_val = delete $attr->{'class'};
    if( $class_val )
    {
	$extra .= " class=\"$class_val\"";
    }
    elsif( not defined $class_val )
    {
	if( $Para::Frame::REQ->is_from_client )
	{
	    # Mark as selected if link goes to current page
	    if( $Para::Frame::REQ->template_uri eq $template and not $attr->{'run'} )
	    {
		$extra .= " class=\"same_place\"";
	    }
	}
    }

    {
	my $q = $Para::Frame::REQ->q;
	my @keep_params = @{ $attr->{'keep_params'}||[] };
	delete $attr->{'keep_params'};
	if( $q )
	{
	    @keep_params = $q->param('keep_params')
		unless @keep_params;
	}
#	warn "keep_params are @keep_params\n"; ### DEBUG
	foreach my $key ( @keep_params )
	{
	    $attr->{$key} = $q->param($key)
		unless defined $attr->{$key} and length $attr->{$key};
	    delete $attr->{$key} unless $attr->{$key}; # Only if TRUE
	}
    }



#    warn sprintf("Escaping '%s' and getting '%s'\n", $label,CGI->escapeHTML( $label ) );
    my $uri = Para::Frame::Utils::uri( $template, $attr );

    if( $template )
    {
	return sprintf("<a href=\"%s\"%s>%s</a>",
		       Para::Frame::Utils::uri( $template, $attr ),
		       $extra,
		       CGI->escapeHTML( $label ),
		       );
    }
    else
    {
	return CGI->escapeHTML( $label );
    }
}


#######################################################################

=head2 submit

  submit( $label, $setval )

Draw a form submit button with text $label and value $setval.

Default label = 'Fortsätt'

Default setval is to not have a value

=cut

sub submit
{
    my( $label, $setval, $attr ) = @_;

    die "Too many args for submit()" if $attr and not ref $attr;

    $label ||= 'Fortsätt';
    $attr ||= {};
    my $class = $attr->{'class'} || 'msg';

    my $name = '';
    $name = "name=\"$setval\"" if $setval;

    return "<input type=\"submit\" class=\"$class\" $name value=\"$label\">";
}

#######################################################################

=head2 go

  go( $label, $template, $run, %attrs )

Draw a form submit button with text $label.  Sets template to $template
and runs action $run.  %attrs specifies form fields to be set to
specified values.

Default $label = '???'

Default $template is previously set next_template

Default $run = 'nop'

All fields set by %attrs must exist in the form. (Maby as hidden
elements)

A 'target' attribute will set the target frame for the form
submit. (not implemented)

=cut

sub go
{
    my( $label, $template, $run, $attr ) = @_;

    die "Too many args for go()" if $attr and not ref $attr;

    $label = '???' unless length $label;
    $template ||= '';
    $run ||= 'nop';
    $attr ||= {};
    $attr->{'class'} ||= 'msg';

    my $extra = "";
    if( my $val = delete $attr->{'target'} )
    {
	$extra .= "target=\"$val\" ";
    }
    if( my $val = delete $attr->{'class'} )
    {
	$extra .= "class=\"$val\" ";
    }

    my $query = join '', map sprintf("document.f.$_.value='%s';", $attr->{$_}), keys %$attr;
    return "<input type=\"button\" value=\"$label\" onClick=\"${query}go('$template', '$run')\" $extra>";
}

sub go_js
{
    my( $template, $run, $attr ) = @_;

    die "Too many args for go()" if $attr and not ref $attr;

    $template ||= '';
    $run ||= 'nop';

    my $query = join '', map sprintf("document.f.$_.value='%s';", $attr->{$_}), keys %$attr;
    return "${query}go('$template', '$run')";
}

#######################################################################

=head2 forward

  forward( $label, $template, %attrs )

Draw a link to $template with text $label and query params %attrs as
well as all the query params.  Params set in %attrs overide the
previous value.  Also sets param 'previous' to current template.

Default $label = '???'

Default $template = '' which would be the current template

=cut

sub forward
{
    my( $label, $template, $attr ) = @_;

    my $url = forward_url( $template, $attr );

    $label = '???' unless length $label;

    return "<a href=\"$url\">$label</a>";
}

sub forward_url
{
    my( $template, $attr ) = @_;

    die "Too many args for jump()" if $attr and not ref $attr;

    $template ||= '';

    my $q = $Para::Frame::REQ->q;

    my $except = ['run']; # FIXME

  KEY:
    foreach my $key ( $q->param() )
    {
	foreach my $exception ( @$except )
	{
	    next KEY if $key eq $exception;
	}

	next if defined $attr->{$key};
	next unless $q->param($key);
	$attr->{$key} = [$q->param($key)];
    }
    my @parts = ();
    foreach my $key ( keys %$attr )
    {
	my $value = $attr->{$key};
	if( UNIVERSAL::isa($value, 'ARRAY') )
	{
	    foreach my $val (@$value)
	    {
		push @parts, sprintf("%s=%s", $key, $q->escape($val));
	    }
	}
	else
	{
	    push @parts, sprintf("%s=%s", $key, $q->escape($value));
	}
    }
    my $query = join '&', @parts;
    $query and $query = '?'.$query;
    return $template.$query;
}


#######################################################################

=head2 preserve_data

  preserve_data( @fields )

Preserves most query params EXCEPT those mentioned in @fields.  This
is done by creating extra hidden fields.  This method will thus only
work with a form submit.

The special query params 'previous', 'run' and 'route' are also
excepted.

=cut

sub preserve_data
{
    my( @except ) = @_;
    my $text = "";
    my $q = $Para::Frame::REQ->q;

    push @except, 'previous', 'run', 'route', 'selector', 'destination';
  KEY:
    foreach my $key ( $q->param())
    {
	foreach( @except )
	{
#	    warn "Testing $key =~ /^$_\$/\n";
	    next KEY if $key =~ /^$_$/;
#	    warn "  PASSED\n";
	}
	my @vals = $q->param($key);
	foreach my $val ( @vals )
	{
	    $val = $q->escapeHTML($val);
	    $text .= "<input type=\"hidden\" name=\"$key\" value=\"$val\">\n";
	}
    }
    return $text;
}


#######################################################################

=head2 alfanum_bar

  alfanum_bar( $template, $field )

Draws a alfanumerical bar, each letter being a link to $template with
the letter as value for field $field.

=cut

sub alfanum_bar
{
    my( $template, $name, $part, $attr ) = @_;

    die "Too many args for alfanum_bar()" if $attr and not ref $attr;
    die "template attrib missing" unless $template;
    die "name attrib missing" unless $name;

    my $q = $Para::Frame::REQ->q;

    $attr ||= {};
    $part ||= '';
    my $extra = '';
#    if( $part )
#    {
#	$extra = '&no_robots=1';
#    }

    my @keep_params = @{ $attr->{'keep_params'}||[] };
    delete $attr->{'keep_params'};
    @keep_params = $q->param('keep_params')
	unless @keep_params;
#	warn "keep_params are @keep_params\n"; ### DEBUG
    foreach my $key ( @keep_params )
    {
	next if $key eq 'offset';
	next if $key eq 'part';
	
	$attr->{$key} = $q->param($key)
	    unless defined $attr->{$key} and length $attr->{$key};
	delete $attr->{$key} unless $attr->{$key}; # Only if TRUE
    }

    use locale;
    use POSIX qw(locale_h);
    setlocale(LC_ALL, "sv_SE");

    my $text = join(' | ', map "<a href=\"$template?$name=$part$_$extra\">\U$_</a>", 'a'..'z','å','ä','ö');
    $text = "| <a href=\"$template?$name=\">0-9</a> | ".$text." |";
    $text =~ s/å/&aring;/g;
    $text =~ s/ä/&auml;/g;
    $text =~ s/ö/&ouml;/g;
    $text =~ s/Å/&Aring;/g;
    $text =~ s/Ä/&Auml;/g;
    $text =~ s/Ö/&Ouml;/g;

#    return "\Uåke ärlansson\n";
    return $text;
}


#######################################################################

=head2 rowlist

  rowlist( $text )

Returns a list of values.  One entry for each nonempty row in the
text.

=cut

sub rowlist
{
    my( $name ) = @_;

    my $q = $Para::Frame::REQ->q;

    my @list;
    foreach my $row ( split /\r?\n/, $q->param($name) )
    {
	trim(\$row);
	next unless length $row;
	push @list, $row;
    }
    return \@list;
}

#######################################################################

=head2 list2block

  list2block( @values )

This is the inverse of rowlist.  Returns a textblock created from a
list of values.

list2block and rowlist can be used for transfering list of values
between page requests.

=cut

sub list2block
{

    my $q = $Para::Frame::REQ->q;

    my $block;
    foreach my $name ( @_ )
    {
	foreach my $row ( $q->param($name) )
	{
	    $block .= $row."\n";
	}
    }
    return $block;
}

sub selectorder
{
    my( $id, $size ) = @_;

    my $result = "<select name=\"placeobj_$id\">\n";
    $result .= "<option selected>--\n";
    for(my $i=1;$i<=$size;$i++)
    {
	$result .= sprintf("<option value=\"$i\">%.2d\n", $i);
    }
    $result .= "</select>\n";
    return $result;
}

sub param_includes
{
    my( $key, $value ) = @_;

    my $q = $Para::Frame::REQ->q;

    foreach my $val ($q->param($key))
    {
	return 1 if $val eq $value;
    }
    return 0;
}


#######################################################################


=head2 hidden

  hidden( $field, $value, %attrs )

Inserts a hidden form field with name $field and value $value.

Default $value is query param $field or $value, in turn.

=cut

sub hidden
{
    my( $key, $value ) = @_;

#### I don't think we should use previous values for hidden fields
#
#    my( @previous ) = $q->param($key);
#    if( $#previous == 0 ) # Just one value
#    {
#	$value = $previous[0];
#    }

    $value ||= '';

    return sprintf('<input type="hidden" name="%s" value="%s">',
		   CGI->escapeHTML( $key ),
		   CGI->escapeHTML( $value ),
		   );
}

#######################################################################

=head2 input

  input( $field, $value, %attrs )

Draws a input field widget.

Sets form field name to $field and value to $value.

size      = width of input field  (default is 30)

maxlength = max number of chars (default is size times 3)

$value will be taken from query param $field or $value, in turn.

=cut

sub input
{
    my( $key, $value, $params ) = @_;


    my $size = delete $params->{'size'} || 30;
    my $maxlength = delete $params->{'maxlength'} || $size*3;

    my @previous;
    if( my $q = $Para::Frame::REQ->q )
    {
        @previous = $q->param($key);
    }

    if( $#previous == 0 ) # Just one value
    {
        $value = $previous[0];
    }
    $key   ||= 'query';
    $value ||= '';

    my $extra = "";
    foreach my $key ( keys %$params )
    {
	$extra .= sprintf " $key=\"%s\"",
	  CGI->escapeHTML( $params->{$key} );
    }

    return sprintf('<input name="%s" value="%s" size="%s" maxlength="%s"%s>',
                   CGI->escapeHTML( $key ),
                   CGI->escapeHTML( $value ),
                   CGI->escapeHTML( $size ),
                   CGI->escapeHTML( $maxlength ),
		   $extra,
                   );
}


#######################################################################

=head2 textarea

  textarea( $field, $value, %attrs )

Draws a textarea with fied name $field and value $value.

cols    = width (default is 60)

rows    = hight (default is 20)

$value is query param $field or $value, in turn.

=cut

sub textarea
{
    my( $key, $value, $params ) = @_;

    my $rows = $params->{'rows'} || 20;
    my $cols = $params->{'cols'} || 60;
    my @previous;

    if( my $q = $Para::Frame::REQ->q )
    {
	@previous = $q->param($key);
    }

    if( $#previous == 0 ) # Just one value
    {
	$value = $previous[0];
    }
    $value ||= '';

    return sprintf('<textarea name="%s" cols="%s" rows="%s" wrap="virtual">%s</textarea>',
		   CGI->escapeHTML( $key ),
		   CGI->escapeHTML( $cols ),
		   CGI->escapeHTML( $rows ),
		   CGI->escapeHTML( $value ),
		   );
}


#######################################################################

=head2 filefield

  filefield( $key, %attrs )

Draws a file-field

cols  = Width of input-field
value = default file upload value

=cut

sub filefield
{
    my( $key, $params ) = @_;

    my $cols = $params->{'cols'} || 60;
    my $value = $params->{'value'} || $Para::Frame::REQ->q->param($key) || "";

    return sprintf('<input type="file" name="%s" value="%s" size="%s">',
		   CGI->escapeHTML( $key ),
		   CGI->escapeHTML( $value ),
		   CGI->escapeHTML( $cols ),
		   );
}



#######################################################################

=head2 css_header

  css_header( \%attrs )

Draws a css header

Example:
    $attrs =
     {
      persistent => [ "/css/default.css" ],
      alternate =>
      {
       light => [ "/css/light.css" ],
       blue => [ "/css/blue.css" ],
      },
      default => 'blue',
     };

=cut

sub css_header
{
    my( $p ) = @_;

    return "" unless $p;

    unless( ref $p )
    {
	$p =
	{
	    'persistent' => [ $p ],
	};
    }

    my $default = $Para::Frame::U->style || $p->{'default'};
    my $persistent = $p->{'persistent'} || [];
    my $alternate = $p->{'alternate'} || {};
    $persistent = [$persistent] unless ref $persistent;

    if( not $default )
    {
	# Just take any of them as a default
	foreach my $key ( keys %$alternate )
	{
	    $default = $key;
	    last;
	}
    }

    my $out = "";

    foreach my $style ( @$persistent )
    {
	$out .= "<link rel=\"Stylesheet\" href=\"$style\" type=\"text/css\">\n";
    }

    if( $default )
    {
	foreach my $style ( @{$alternate->{$default}} )
	{
	    $out .= "<link rel=\"Stylesheet\" title=\"$default\" href=\"$style\" type=\"text/css\">\n";
	}
    }

    foreach my $title ( keys %$alternate )
    {
	next if $title eq $default;
	foreach my $style ( @{$alternate->{$title}} )
	{
	    $out .= "<link rel=\"alternate stylesheet\" title=\"$title\" href=\"$style\" type=\"text/css\">\n";
	}
    }    

    return $out;
}



#######################################################################

=head2 confirm_simple

  confirm_simple()

  confirm_simple( $headline )

  confirm_simple( $headline, $text )

  confirm_simple( $headline, $text, $button_name )

Returns true if the question in the C<$headline> has been confirmed.
Use a unique headline if there is any chanse that multiple
confirmations will be required in a route of actions.

If no confirmation has been given, creates a confirmation dialog box
and displays it by using an C<incomplete> exception and the
C<confirm.tt> template.

=head3 Default

  $headline    = 'Är du säker?'
  $text        = ''
  $button_name = 'Ja'

=head3 Example

In an action:

  confirm_simple("Remove $obj_name?");
  $obj->remove;

=cut

sub confirm_simple
{
    my( $widg, $headline, $text, $button_name ) = @_;

    $headline ||= 'Är du säker?';
    $text ||= '';
    $button_name ||= 'Ja';

    my $req = Para::Frame::Request->obj;
    my $q = $req->q;

    foreach my $confirmed ( $q->param('confirmed') )
    {
	warn "Comparing '$confirmed' with '$headline'\n";
	return 1 if $confirmed eq $headline;
    }

    ## Set up route, confirmation data and throw exception

    $req->s->route->bookmark;
    $req->set_template('confirm.tt');
    my $result = $req->result;
    my $home = $req->app->home;

#    my @actions = @{ $req->{'actions'} };
#    unshift @actions, $req->{'this_action'} if $req->{'this_action'};
#    pop @actions; # Last action always a nop!
#    my $run = join('&', @actions );

    $result->{'info'}{'confirm'} =
    {
     title => $headline,
     text  => $text,
     button =>
     [
      [ $button_name, undef, 'backtrack',
#      {
#       confirmed => $headline,
#       step_add_params => 'confirmed',
#      }
      ],
      ['Backa', undef, 'skip_step'],
     ],
    };

    $q->append(-name=>'confirmed',-values=>[$headline]);
    $q->append(-name=>'step_add_params',-values=>['confirmed']);
    throw('incomplete', 'Confirm');
}

#### Methods

sub on_configure
{
    my( $class ) = @_;

    my $params =
    {
	'selectorder'     => \&selectorder,
	'slider'          => \&slider,
	'jump'            => \&jump,
	'submit'          => \&submit,
	'go'              => \&go,
	'go_js'           => \&go_js,
	'forward'         => \&forward,
	'forward_url'     => \&forward_url,
	'alfanum_bar'     => \&alfanum_bar,
	'rowlist'         => \&rowlist,
	'list2block'      => \&list2block,
	'preserve_data'   => \&preserve_data,
	'param_includes'  => \&param_includes,
	'hidden'          => \&hidden,
	'input'           => \&input,
	'textarea'        => \&textarea,
	'filefield'       => \&filefield,
	'css_header'      => \&css_header,
    };

    Para::Frame->add_global_tt_params( $params );
}

sub on_reload
{
    # This will bind the newly compiled code in the params hash,
    # replacing the old code

    $_[0]->on_configure;
}


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::Manual::Templates>

=cut
