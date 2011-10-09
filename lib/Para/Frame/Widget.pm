package Para::Frame::Widget;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2010 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Widget - Common template widgets

=cut

use 5.010;
use strict;
use warnings;
use utf8; # Using Latin1 (åäö) in alfanum_bar()
use locale;

use Carp qw( cluck confess croak );
use IO::File;
#use CGI;
use Para::Frame::URI;
use POSIX qw(locale_h);
use Scalar::Util qw( blessed );
use JSON; # to_json


use base qw( Exporter );
our @EXPORT_OK

      = qw( slider jump submit go go_js forward forward_url preserve_data alfanum_bar rowlist list2block selectorder param_includes hidden input password textarea htmlarea filefield css_header confirm_simple inflect radio calendar input_image selector label_from_params checkbox );

use Para::Frame::Reload;
use Para::Frame::Utils qw( trim throw debug uri store_params datadump );
use Para::Frame::L10N qw( loc );

our $IDCOUNTER = 0;

=head1 DESCRIPTION

C<Para::Frame::Widget> is an optional module.  It will not be used unless
the application calls it or uses the default application init method.

Widgets can be implemented either as exported objects (functions /
methods / variables) or as templates for inclusion or defined template
macros.

These are the standard widgets defined as Perl code.  See also the
standard L<Para::Frame::Template::Components>.

=head1 Exported objects

=over

=item L</selectorder>

=item L</slider>

=item L</jump>

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

=item L</css_header>

=item L</inflect>

=back

=cut

##############################################################################

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
	    $checked[$i] = 'checked="checked"';
	}

	$widget .= "<input type=\"radio\" name=\"$field\" value=\"$val[$i]\" $checked[$i]/>\n";
    }
    return $widget;
}


##############################################################################

=head2 jump

  jump( $label, $template, \%attrs )

  jump( $label, $template_with_query, \%attrs )

  jump( $label, $uri, \%attrs )

Draw a link to C<$template> with text C<$label> and query params
C<%attrs>.

Special attrs include

=over

=item tag_attr

See L</tag_extra_from_params>

Used instead of deprecated attrs C<href_target>, C<href_onclick>,
C<href_class>, C<href_id> and C<href_style>.

=item tag_image

Used instead of deprecated attrs C<href_image>.

=item keep_params

=back

If no class is set, the class will be C<same_place> if the link goes to
the current page.  To be used with CSS for marking the current page in
menues.

Default $label = '???'

Default $template = '', witch would be the current template

=cut

sub jump
{
    my( $label, $template, $attr ) = @_;

    $label = '???' unless length $label;

    my $label_out;
    if( blessed $label and $label->can('as_html') )
    {
	$label_out = $label->as_html;
    }
    else
    {
	$label_out = CGI->escapeHTML( $label );
    }
    my $content = $label_out;

    # DEPRECATED
    if( my $src =  delete ${$attr}{'href_image'} )
    {
	$content = "<img alt=\"$label_out\" src=\"$src\" />";
    }
    if( my $src =  delete ${$attr}{'tag_image'} )
    {
	$content = "<img alt=\"$label_out\" src=\"$src\" />";
    }

    my $extra = jump_extra( $template, $attr );

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

    unless( $template )
    {
	if( $Para::Frame::REQ->response_if_existing )
	{
	    $template = $Para::Frame::REQ->page->url_path_slash;
	}
    }

#    warn sprintf("Escaping '%s' and getting '%s'\n", $label,CGI->escapeHTML( $label ) );

    if( $template )
    {
	my $uri = Para::Frame::Utils::uri( $template, $attr );
	return sprintf("<a href=\"%s\"%s>%s</a>",
		       CGI->escapeHTML( $uri ),
		       $extra,
		       $content,
		       );
    }
    else
    {
	return $content;
    }
}


##############################################################################

=head2 jump_extra

  jump_extra( $template, \%attr, \%args )

=cut

sub jump_extra
{
    my( $template, $attr, $args ) = @_;

    if( UNIVERSAL::isa $template, 'URI' )
    {
	if( $template->host eq $Para::Frame::REQ->site->host )
	{
	    $template = $template->path_query;
	}
    }

    $attr ||= {};

    $args ||= {};
    $args->{'highlight_same_place'} //= 1;

    my $extra = "";

    ###### DEPRECATED
    if( my $val = delete ${$attr}{'href_target'} )
    {
	$extra .= " target=\"$val\"";
    }
    if( my $val = delete ${$attr}{'href_id'} )
    {
	$extra .= " id=\"$val\"";
    }
    if( my $val = delete ${$attr}{'href_onclick'} )
    {
	$extra .= " onClick=\"$val\"";
    }
    if( my $val = delete ${$attr}{'href_style'} )
    {
	$extra .= " style=\"$val\"";
    }

    my $class_val = delete ${$attr}{'href_class'};
    if( $class_val )
    {
	$extra .= " class=\"$class_val\"";
    }

    if( my $tag_attr = delete ${$attr}{'tag_attr'} )
    {
	$class_val = $tag_attr->{'class'};
	$extra .= tag_extra_from_params( $tag_attr );
    }

    if( not defined $class_val and $args->{'highlight_same_place'} )
    {
	if( $Para::Frame::REQ->is_from_client and $template )
	{
	    my $template_path = $template;
	    $template_path =~ s/\?.*//;

	    # Mark as same_place if link goes to current page
	    if( $Para::Frame::REQ->page->url_path_slash eq $template_path
		and not $attr->{'run'} )
	    {
		# Special handling of attribute id
		my $oid = $Para::Frame::REQ->q->param('id') || 0;
		my $nid = $attr->{'id'} || 0;
		unless( $nid )
		{
		    if( $template =~ /(\?|&)id=(.+?)(&|$)/ )
		    {
			$nid = CGI->unescape($2) || 0;
		    }
		}
		if( $nid eq $oid )
		{
		    $extra .= " class=\"same_place\"";
		}
	    }
	}
    }

    return $extra;
}


##############################################################################

=head2 submit

  submit( $label, $setval, \%attrs )

Draw a form submit button with text $label and value $setval.

Default label = 'Continue'

Default setval is to not have a value

Special attrs include

=over

=item tag_attr

See L</tag_extra_from_params>

Used instead of deprecated attrs C<href_target>, C<href_onclick>,
C<href_class>, C<href_id> and C<href_style>.

=back

TODO: Do html escape of value

=cut

sub submit
{
    my( $label, $setval, $attr ) = @_;

    die "Too many args for submit()" if $attr and not ref $attr;

    $label ||= 'Continue';
    $attr ||= {};

    my $extra = jump_extra( undef, $attr, {highlight_same_place=>0} );

    my $label_out = loc($label);

    # DEPRECATED
    if( my $class = delete ${$attr}{'href_class'} )
    {
	$extra .= " class=\"$class\"";
    }
    if( my $val = delete ${$attr}{'href_target'} )
    {
	$extra .= " target=\"$val\"";
    }
    if( my $val = delete ${$attr}{'href_id'} )
    {
	$extra .= " id=\"$val\"";
    }
    if( my $val = delete ${$attr}{'href_onclick'} )
    {
	$extra .= " onClick=\"$val\"";
    }
    if( my $val = delete ${$attr}{'href_style'} )
    {
	$extra .= " style=\"$val\"";
    }

    my $name = '';
    $name = "name=\"$setval\"" if $setval;

    return "<input type=\"submit\" $name value=\"$label_out\"$extra/>";
}

##############################################################################

=head2 go

  go( $label, $template, $run, \%attrs )

Draw a form submit button with text $label.  Sets template to $template
and runs action $run.  %attrs specifies form fields to be set to
specified values.

Default $label = '???'

Default $template is previously set next_template

Default $run = 'nop'

All fields set by %attrs must exist in the form. (Maybe as hidden
elements)

Special attrs include

=over

=item tag_attr

See L</tag_extra_from_params>

Used instead of deprecated attrs C<href_target>, C<href_onclick>,
C<href_class>, C<href_id> and C<href_style>.

=back

TODO: Do html escape of value

=cut

sub go
{
    my( $label, $template, $run, $attr ) = @_;

    die "Too many args for go()" if $attr and not ref $attr;

    $label = '???' unless length $label;
    $template ||= '';
    $run ||= 'nop';
    $attr ||= {};

    if( utf8::is_utf8($label) )
    {
	if( utf8::valid($label) )
	{
#	    debug "Label '$label' is valid UTF8";
	}
	else
	{
	    confess "Label '$label' is INVALID UTF8";
	}
    }
    else
    {
	utf8::decode($label);
#	debug "Label '$label' decoded to UTF8";
#	if( utf8::is_utf8($label) )
#	{
#	    if( utf8::valid($label) )
#	    {
#		debug "Label '$label' is valid UTF8";
#	    }
#	    else
#	    {
#		debug "Label '$label' is INVALID UTF8";
#	    }
#	}
    }

    my $extra = jump_extra( $template, $attr, {highlight_same_place=>0} );
    my $onclick_extra = "";

    # DEPRECATED
    if( my $val = delete $attr->{'href_target'} )
    {
	$extra .= "target=\"$val\" ";
    }
    if( my $val = delete $attr->{'href_id'} )
    {
	$extra .= "id=\"$val\" ";
    }
    if( my $val = delete $attr->{'href_onclick'} )
    {
	$extra .= "onClick=\"$val\" ";
    }
    if( my $val = delete $attr->{'href_style'} )
    {
	$extra .= "style=\"$val\" ";
    }
    if( my $val = delete $attr->{'href_class'} )
    {
	$extra .= "class=\"$val\" ";
    }

    ### NEW FORMAT
    if( my $tag_attr = delete ${$attr}{'tag_attr'} )
    {
	$extra .= tag_extra_from_params( $tag_attr );
    }


    my $query = join '', map sprintf("document.forms['f'].$_.value='%s';", $attr->{$_}), keys %$attr;
    return "<input type=\"button\" value=\"$label\" onclick=\"${onclick_extra}${query}go('$template', '$run')\" $extra />";
}

sub go_js
{
    my( $template, $run, $attr ) = @_;

    die "Too many args for go()" if $attr and not ref $attr;

    $template ||= '';
    $run ||= 'nop';

    my $query = join '', map sprintf("document.forms['f'].$_.value='%s';", $attr->{$_}), keys %$attr;
    return "${query}go('$template', '$run')";
}

##############################################################################

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

    my $extra = jump_extra( $template, $attr, {highlight_same_place=>0} );

    my $url = forward_url( $template, $attr );

    $label = '???' unless length $label;

    return "<a href=\"$url\"$extra>$label</a>";
}

sub forward_url
{
    my( $template, $attr ) = @_;

    die "Too many args for jump()" if $attr and not ref $attr;


#    debug "In forward_url for $template with attr\n".datadump($attr);

    $template ||= $Para::Frame::REQ->env->{'REQUEST_URI'};
    my $except = ['run','destination','reqnum','pfport','caller_page']; # FIXME

    if( $template =~ /(.*?)\?/ )
    {
#	debug "Processing query part of template";
	my $uri = Para::Frame::URI->new($template);
	$template = $1;
	my( %urlq ) = $uri->query_form;

      KEY1:
	foreach my $key ( keys %urlq )
	{
	    # Not supporting multiple values
	    next if defined $attr->{$key};

	    foreach my $exception ( @$except )
	    {
		if( $key eq $exception )
		{
		    next KEY1;
		}
	    }

#	    debug "  Adding $key";
	    $attr->{$key} = [$urlq{$key}];
	}
    }

    my $q = $Para::Frame::REQ->q;

#    debug "Processing query params";
  KEY2:
    foreach my $key ( $q->param() )
    {
	next if defined $attr->{$key};
	next unless $q->param($key);

	foreach my $exception ( @$except )
	{
	    if( $key eq $exception )
	    {
		next KEY2;
	    }
	}

#	debug "  Adding $key";
	$attr->{$key} = [$q->param($key)];
    }

    my @parts = ();
#    debug "Processign given attrs";
    foreach my $key ( keys %$attr )
    {
#	debug "  Encoding $key";
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

    my $query = join '&amp;', @parts;
    if( $query )
    {
	if( $template =~ /\?/ )
	{
	    $query = '&'.$query;
	}
	else
	{
	    $query = '?'.$query;
	}
    }
    return $template.$query;
}


##############################################################################

=head2 preserve_data

  preserve_data( @fields )

Preserves most query params EXCEPT those mentioned in @fields.  This
is done by creating extra hidden fields.  This method will thus only
work with a form submit.

The special query params 'previous', 'run', 'route' and 'reqnum' are also
excepted. And some more...

=cut

sub preserve_data
{
    my( @except ) = @_;
    my $text = "";
    my $q = $Para::Frame::REQ->q;

    push @except, 'previous', 'run', 'route', 'selector',
      'destination', 'session_vars_update', 'admin_mode', 'reqnum', 'pfport';

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
	    $text .= "<input type=\"hidden\" name=\"$key\" value=\"$val\" />\n";
	}
    }
    return $text;
}


##############################################################################

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
    if( $part )
    {
	$extra = ' rel="nofollow"';
    }

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

    # locale should have been set previously!
    my $text = join(' | ', map "<a href=\"$template?$name=$part$_\"$extra>\U$_</a>", 'a'..'z','å','ä','ö');
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


##############################################################################

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
    foreach my $row ( split /\r?\n/, ($q->param($name)||'') )
    {
	trim(\$row);
	next unless length $row;
	push @list, $row;
    }
    return \@list;
}

##############################################################################

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


##############################################################################

=head2 sekectorder

=cut

sub selectorder
{
    my( $id, $size ) = @_;

    my $result = "<select name=\"placeobj_$id\">\n";
    $result .= "<option selected=\"selected\">--\n";
    for(my $i=1;$i<=$size;$i++)
    {
	$result .= sprintf("<option value=\"$i\">%.2d\n", $i);
    }
    $result .= "</select>\n";
    return $result;
}


##############################################################################

=head2 param_includes

=cut

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


##############################################################################

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

    return sprintf('<input type="hidden" id="%s" name="%s" value="%s" />',
		   CGI->escapeHTML( $key ),
		   CGI->escapeHTML( $key ),
		   CGI->escapeHTML( $value ),
		   );
}


##############################################################################

=head2 input

  input( $field, $value, %attrs )

Draws a input field widget.

Sets form field name to $field and value to $value.

C<$value> will be taken from query param C<$field> or C<$value>, in
turn.


Attributes:

  size: width of input field  (default is 30)

  maxlength: max number of chars (default is size times 3)

  tdlabel: Sets C<label> and separates it with a C<td> tag.

  label: draws a label before the field with the given text

  label_class: Adds a class to the C<label> tag

  separator: adds the unescaped string between label and input tag

  id: used for label. Defaults to C<$field>

  onchange: used for scripts, NOT html-escaped!

All other attributes are directly added to the input tag, with the
value html escaped.

Example:

  Drawing a input field widget with a label
  [% input('location_name', '', label=loc('Location')) %]



=cut

sub input
{
    my( $key, $value, $params ) = @_;

    $params ||= {};
    my $size = delete $params->{'size'} || 30;
    my $maxlength = delete $params->{'maxlength'} || $size*3;
    my $extra = '';

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

    if( my $onchange = delete $params->{'onchange'} )
    {
	$extra .= ' onchange="'. $onchange .'" ';
    }

    # Objects is defined but may stringify to undef
    unless( $value or Scalar::Util::looks_like_number($value) )
    {
	$value = '';
    }

    $params->{id} ||= $key;
    my $prefix = label_from_params($params);
    $extra .= tag_extra_from_params($params);

    # Stringify all params, in case they was objects
    return sprintf('%s<input type="text" name="%s" value="%s" size="%s" maxlength="%s"%s />',
		   $prefix,
		   CGI->escapeHTML( "$key" ),
		   CGI->escapeHTML( "$value" ),
		   CGI->escapeHTML( "$size" ),
		   CGI->escapeHTML( "$maxlength" ),
		   $extra,
		  );
}


##############################################################################

=head2 password

  password( $field, $value, %attrs )

Draws a password input field widget.

Sets form field name to $field and value to $value.

C<$value> will be taken from query param C<$field>


Attributes:

  size: width of input field  (default is 30)

  maxlength: max number of chars (default is size times 3)

  tdlabel: Sets C<label> and separates it with a C<td> tag.

  label: draws a label before the field with the given text

  label_class: Adds a class to the C<label> tag

  separator: adds the unescaped string between label and input tag

  id: used for label. Defaults to C<$field>

  onchange: used for scripts, NOT html-escaped!

All other attributes are directly added to the input tag, with the
value html escaped.

Example:

  Drawing a password input field widget with a label
  [% password('location_name', '', label=loc('Password')) %]



=cut

sub password
{
    my( $key, $value_in, $params ) = @_;

    my $size = delete $params->{'size'} || 30;
    my $maxlength = delete $params->{'maxlength'} || $size*3;
    my $extra = '';
    my $value; # Not using input value...

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

    if( my $onchange = delete $params->{'onchange'} )
    {
	$extra .= ' onchange="'. $onchange .'" ';
    }

    # Objects is defined but may stringify to undef
    unless( $value or Scalar::Util::looks_like_number($value) )
    {
	$value = '';
    }

    $params->{id} ||= $key;
    my $prefix = label_from_params($params);
    $extra .= tag_extra_from_params($params);

    # Stringify all params, in case they was objects
    return sprintf('%s<input type="password" name="%s" value="%s" size="%s" maxlength="%s"%s />',
		   $prefix,
		   CGI->escapeHTML( "$key" ),
		   CGI->escapeHTML( "$value" ),
		   CGI->escapeHTML( "$size" ),
		   CGI->escapeHTML( "$maxlength" ),
		   $extra,
		  );
}


##############################################################################

=head2 textarea

  textarea( $field, $value, %attrs )

Draws a textarea with fied name $field and value $value.

C<$value> will be taken from query param C<$field> or C<$value>, in
turn.

Attributes:

  cols: width (default is 60)

  rows: hight (default is 20)

  label: draws a label before the field with the given text

  tdlabel: Sets C<label> and separates it with a C<td> tag.

  label_class: Adds a class to the C<label> tag

  separator: adds the unescaped string between label and input tag

  id: used for label. Defaults to C<$field>

All other attributes are directly added to the input tag, with the
value html escaped.

The default wrap attribute is 'virtual'.

=cut

sub textarea
{
    my( $key, $value, $params ) = @_;

    my $rows = $params->{'rows'} || 20;
    my $cols = $params->{'cols'} || $params->{'size'} || 75;
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

    delete $params->{'rows'};
    delete $params->{'cols'};
    delete $params->{'size'};

    $params->{id} ||= $key;
    my $prefix = label_from_params($params);
    $params->{'wrap'} ||= "virtual";
    my $extra = tag_extra_from_params($params);

    return sprintf('%s<textarea name="%s" cols="%s" rows="%s"%s>%s</textarea>',
		   $prefix,
		   CGI->escapeHTML( $key ),
		   CGI->escapeHTML( $cols ),
		   CGI->escapeHTML( $rows ),
		   $extra,
		   CGI->escapeHTML( $value ),
		   );
}


##############################################################################

=head2 htmlarea

  htmlarea( $field, $value, %attrs )

Draws a htmlarea with fied name $field and value $value.

C<$value> will be taken from query param C<$field> or C<$value>, in
turn.

Attributes:

  cols: width (default is 60)

  rows: hight (default is 20)

  label: draws a label before the field with the given text

  tdlabel: Sets C<label> and separates it with a C<td> tag.

  label_class: Adds a class to the C<label> tag

  separator: adds the unescaped string between label and input tag

  id: used for label. Defaults to C<$field>

All other attributes are directly added to the input tag, with the
value html escaped.

The default wrap attribute is 'virtual'.

=cut

sub htmlarea
{
    my( $key, $value, $params ) = @_;

    my $rows = $params->{'rows'} || 20;
    my $cols = $params->{'cols'} || $params->{'size'} || 75;
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

    $params->{id} ||= $key;
    my $prefix = label_from_params($params);
    $params->{'wrap'} ||= "virtual";
    my $extra = tag_extra_from_params($params);


    $value =~ s/\"/\\\"/g;
    $value =~ s/\r/\\r/g;
    $value =~ s/\n/\\n/g;

    my $w = $cols * 10;
    $w = '100%';
    my $h = ($rows + 4) * 20;

    my $home = $Para::Frame::REQ->site->home_url_path;


    return $prefix .
      '<input type="hidden" name="'. $params->{'id'} .'" style="display:none" value="" '. $extra .' />'.
	'<script>document.getElementById(\''. $params->{'id'} . '\').value="'. $value .'"</script>'.
	  '<iframe id="'. $params->{'id'} .'___Frame" src="'. $home .'/pf/cms/fckeditor/editor/fckeditor.html?InstanceName='. $params->{'id'} .'&amp;Toolbar=ParaFrame" width="'. $w .'" height="'. $h .'" frameborder="0" scrolling="no"></iframe>';
}


##############################################################################

=head2 checkbox

  checkbox( $field, $value, $checked, %attrs )

  checkbox( $field, $value, %attrs )

  checkbox( $field, %attrs )

Draws a checkbox with fied name $field and value $value.

C<$checked> will be taken from query param C<$field> or C<$checked>,
in turn. Set to true if query param value equals C$value>. Set to
false if $checked is either false or 'f'.

Default C<$value> is C<1>.

Attributes:

  prefix_label: draws a label before the field with the given text

  suffix_label: draws a label after the field with the given text

  label: sets suffix_label

  label_class: Adds a class to the C<label> tag

  separator: adds the unescaped string between label and checkbox tag

  id: used for label. Defaults to C<$field>

All other attributes are directly added to the input tag, with the
value html escaped.

=cut

sub checkbox
{
    my( $field, $value, $checked, $params ) = @_;

    # Detecting how many params are given to the checkbox
    #
    if( ref $checked and
	not $params and
	(ref $checked eq 'HASH')
	)
    {
	$params = $checked;
	$checked = undef;
    }

    if( ref $value and
	not $checked and
	not $params and
	(ref $value eq 'HASH')
	)
    {
	$params = $value;
	$value = 1;
    }

    $value ||= 1;

    my @previous;

    if( my $q = $Para::Frame::REQ->q )
    {
	@previous = $q->param($field);
    }

    foreach my $prev ( @previous )
    {
	if( $prev eq $value )
	{
	    $checked = 1;
	    last;
	}
    }

    my $extra = "";
    my $prefix = "";
    my $suffix = "";
    my $separator = delete $params->{'separator'} || '';
    my $label_class = delete $params->{'label_class'};
    my $id = $params->{id} || ( $field.'-'.$IDCOUNTER++);

    my $suffix_label = $params->{'label'};
    if( $suffix_label ||= delete $params->{'suffix_label'} )
    {
	my $suffix_extra = "";
	if( $label_class )
	{
	    $suffix_extra .= sprintf " class=\"%s\"",
	    CGI->escapeHTML( $label_class );
	}
	$suffix .= sprintf('<label for="%s"%s>%s</label>',
			   CGI->escapeHTML( $id ),
			   $suffix_extra,
			   CGI->escapeHTML($suffix_label),
			   );
	$params->{id} = $id;
    }

    if( my $prefix_label = delete $params->{'prefix_label'} )
    {
	my $prefix_extra = "";
	if( $label_class )
	{
	    $prefix_extra .= sprintf " class=\"%s\"",
	    CGI->escapeHTML( $label_class );
	}
	$prefix .= sprintf('<label for="%s"%s>%s</label>',
			   CGI->escapeHTML( $id ),
			   $prefix_extra,
			   CGI->escapeHTML($prefix_label),
			   );
	$params->{id} = $id;
    }

    foreach my $key ( keys %$params )
    {
	$extra .= sprintf " $key=\"%s\"",
	  CGI->escapeHTML( $params->{$key} );
    }

    if( ref $checked )
    {
	confess "Checkbox called with a non-boolean value: $checked";
    }

    if( $checked and $checked ne 'f')
    {
	$extra .= ' checked="checked"';
    }

    if( $prefix )
    {
	$prefix .= $separator;
    }

    if( $suffix )
    {
	$suffix = $separator . $suffix;
    }

    return sprintf('%s<input type="checkbox" name="%s" value="%s"%s/>%s',
		   $prefix,
		   CGI->escapeHTML( $field ),
		   CGI->escapeHTML( $value ),
		   $extra,
		   $suffix,
		   );
}


##############################################################################

=head2 radio

  radio( $field, $value, $checked, %attrs )

  radio( $field, $value, %attrs )

Draws a radio button with field name $field and value $value.

C<$checked> will be taken from query param C<$field> or C<$checked>, in
turn. Set to false if $checked is either false or 'f'.

Attributes:

  prefix_label: draws a label before the field with the given text

  suffix_label: draws a label after the field with the given text

  label: sets suffix_label

  label_class: Adds a class to the C<label> tag

  separator: adds the unescaped string between label and checkbox tag

  id: used for label. Mandatory if label is set

All other attributes are directly added to the input tag, with the
value html escaped.

=cut

sub radio
{
    my( $field, $value, $checked, $params ) = @_;

    if( ref $checked )
    {
	$params = $checked;
	$checked = undef;
    }

    my @previous;

    if( my $q = $Para::Frame::REQ->q )
    {
	@previous = $q->param($field);
    }

    if( $#previous == 0 ) # Just one value
    {
	$checked = ($previous[0] eq $value) ? 1 : 0;
    }

    defined $value or croak "value param for radio missing";

    my $extra = "";
    my $prefix = "";
    my $suffix = "";
    my $separator = delete $params->{'separator'} || '';
    my $label_class = delete $params->{'label_class'};
    my $id = $params->{id} || $field .'_'. $value;

    my $suffix_label = $params->{'label'};
    if( $suffix_label ||= delete $params->{'suffix_label'} )
    {
	$id or croak "id param for radio missing";
	my $suffix_extra = "";
	if( $label_class )
	{
	    $suffix_extra .= sprintf " class=\"%s\"",
	    CGI->escapeHTML( $label_class );
	}
	$suffix .= sprintf('<label for="%s"%s>%s</label>',
			   CGI->escapeHTML( $id ),
			   $suffix_extra,
			   CGI->escapeHTML($suffix_label),
			   );
	$params->{id} = $id;
    }

    if( my $prefix_label = delete $params->{'prefix_label'} )
    {
	$id or croak "id param for radio missing";
	my $prefix_extra = "";
	if( $label_class )
	{
	    $prefix_extra .= sprintf " class=\"%s\"",
	    CGI->escapeHTML( $label_class );
	}
	$prefix .= sprintf('<label for="%s"%s>%s</label>',
			   CGI->escapeHTML( $id ),
			   $prefix_extra,
			   CGI->escapeHTML($prefix_label),
			   );
	$params->{id} = $id;
    }

    foreach my $key ( keys %$params )
    {
	$extra .= sprintf " $key=\"%s\"",
	  CGI->escapeHTML( $params->{$key} );
    }

    if( $checked and $checked ne 'f')
    {
	$extra .= ' checked="checked"';
    }

    if( $prefix )
    {
	$prefix .= $separator;
    }

    if( $suffix )
    {
	$suffix = $separator . $suffix;
    }

    return sprintf('%s<input type="radio" name="%s" value="%s"%s/>%s',
		   $prefix,
		   CGI->escapeHTML( $field ),
		   CGI->escapeHTML( $value ),
		   $extra,
		   $suffix,
		   );
}


##############################################################################

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

    return sprintf('<input type="file" name="%s" value="%s" size="%s" />',
		   CGI->escapeHTML( $key ),
		   CGI->escapeHTML( $value ),
		   CGI->escapeHTML( $cols ),
		   );
}


##############################################################################

=head2 selector

Name "selector" is because "select" is a protected term.

  selector( $field, $current, @data,
           {
            valkey => $valkey,
            tagkey => $tagkey,
            header => $header,
            %attrs,
           } )
  selector( $field, $current, %data, \%attrs )

Draws a dropdown menu from a list of records (from a DB).

First version:

The select field has the name $field.  @data is the list of records
returned from select_list().  $valkey is the field name holding the
values and $tagkey is the field holding the lables used in the
dropdown.  $current is the current value used for determining which
item to select.

If $header is defiend, it's a label first in the list without a value.

Example:

  <p>[% selector( "sender", "",
             select_list("from users"),
             valkey = "user_id", tagkey = "username",
             header = "Välj"
  ) %]

Second version:

%data is a hashref. The select will consist of all the keys and
values, sorted on the keys. $current value will be selected.  $field
is the name of fhe field.

Example:

  <p>[% selector("frequency", "",
  {
  	'1' = "every month",
  	'2' = "every week",
  	'3' = "every day",
  }) %]



  valkey is the key in the hash for the value

  tagkey is the key in the hash for the label

  relkey is the key in the hash for the rel; see usableforms...

  tdlabel: Sets C<label> and separates it with a C<td> tag.

  label: draws a label before the field with the given text

  label_class: Adds a class to the C<label> tag

  separator: adds the unescaped string between label and input tag

  id: used for label. Defaults to C<$field>

Special attrs include

=over

=item tag_attr

See L</tag_extra_from_params>

Used instead of deprecated attrs C<href_class>, C<href_target>,
C<href_id>, C<href_onchange> and C<href_style>.

=back

=cut

sub selector
{
    my( $name, $current, $data, $params ) = @_;

    my $valkey = delete $params->{'valkey'};
    my $tagkey = delete $params->{'tagkey'} || $valkey;
    my $relkey = delete $params->{'relkey'};
    my $header = delete $params->{'header'};
    my $out = '';

#    debug(datadump(\@_));

    my @previous;
    if( my $q = $Para::Frame::REQ->q )
    {
	@previous = $q->param($name);

	$current = $previous[0]
	  if( $#previous == 0 ); # Just one value
    }


    #### Label etc
    my $prefix = "";
    my $separator = delete($params->{'separator'}) || '';
    if( my $tdlabel = delete $params->{'tdlabel'} )
    {
	$separator = "</td><td>";
	$params->{'label'} = $tdlabel;
    }
    if( my $label = delete $params->{'label'} )
    {
	my $id = $params->{id} || $name;
	my $prefix_extra = "";
	if( my $class = delete $params->{'label_class'} )
	{
	    $prefix_extra .= sprintf " class=\"%s\"",
	    CGI->escapeHTML( $class );
	}
	$prefix .= sprintf('<label for="%s"%s>%s</label>',
			   CGI->escapeHTML( $id ),
			   $prefix_extra,
			   CGI->escapeHTML($label),
			   );
	$params->{id} = $id;
    }

    my $extra = jump_extra( undef, $params, {highlight_same_place=>0} );

    ###### DEPRECATED
    if( my $class = delete ${$params}{'href_class'} )
    {
	$extra .= " class=\"$class\"";
    }
    if( my $val = delete ${$params}{'href_target'} )
    {
	$extra .= " target=\"$val\"";
    }
    if( my $val = delete ${$params}{'href_id'} )
    {
	$extra .= " id=\"$val\"";
    }
    if( my $val = delete ${$params}{'href_onchange'} )
    {
	$extra .= " onChange=\"$val\"";
    }
    if( my $val = delete ${$params}{'href_style'} )
    {
	$extra .= " style=\"$val\"";
    }

    if( $prefix )
    {
	$prefix .= $separator;
    }
    ###########

    $out .= $prefix . '<select name="'. CGI->escapeHTML( $name ) .'"'.$extra.'>';

    if( $valkey )
    {
	my $rel = ( $relkey ? ' rel="nop"' : '' );
	$out .= '<option value=""'. $rel .'>'. CGI->escapeHTML( $header ) .'</option>'
	  if( $header );

	if( UNIVERSAL::isa $data, 'Para::Frame::List' )
	{
	    $data = $data->as_arrayref;
	}

	foreach my $row ( @$data )
	{
	    if( UNIVERSAL::can $row, $valkey )
	    {
		my $selected = ( $row->$valkey eq $current ?
				 ' selected="selected"' : '' );
		$rel = ( $relkey ? ' rel="'. $row->$relkey .'"' : '' );
		$out .= '<option value="'. $row->$valkey .'"'. $selected . $rel
		  .'>'. $row->$tagkey .'</option>';
	    }
	    else
	    {
		my $selected = ( $row->{$valkey} eq $current ?
				 ' selected="selected"' : '' );
		$rel = ( $relkey ? ' rel="'. $row->{$relkey} .'"' : '' );
		$out .= '<option value="'. $row->{$valkey} .'"'. $selected . $rel
		  .'>'. $row->{$tagkey} .'</option>';
	    }
	}
    }
    else
    {
	foreach my $key ( keys %$data )
	{
	    my $selected = ( $key eq $current ?
			     ' selected="selected"' : '' );

	    $out .= '<option value="'. $key .'"'.$selected.'>'.
	      $data->{$key} .'</option>';
	}
    }

    $out .= '</select>';

    return $out;
}


##############################################################################

=head2 label_from_params

Usage: $params->{id} ||= $key;
       $out .= label_from_params($params);

=cut

sub label_from_params
{
    my( $params ) = @_;

    my $out = '';


    my $separator = delete($params->{'separator'}) || '';
    if( my $tdlabel = delete $params->{'tdlabel'} )
    {
	$separator = "</td><td>";
	$params->{'label'} = $tdlabel;
    }

    my $label = delete $params->{'label'} // '';
    if( length $label )
    {
	debug 2, "Drawing a label: ". $label;

	my $prefix_extra = "";
	if( my $class = delete $params->{'label_class'} )
	{
	    $prefix_extra .= sprintf " class=\"%s\"",
	      CGI->escapeHTML( $class );
	}

	if( my $id = $params->{id} )
	{
	    $prefix_extra .= sprintf " for=\"%s\"",
	      CGI->escapeHTML( $id );
	}

	my $label_out;
	if( blessed $label and $label->can('as_html') )
	{
	    $label_out = $label->as_html;
	}
	else
	{
	    $label_out = CGI->escapeHTML( $label );
	}

	$out .= sprintf('<label%s>%s</label>',
			$prefix_extra,
			$label_out,
		       );
    }

    $out .= $separator
      if $out;


    return $out;
}

##############################################################################

=head2 tag_extra_from_params

Converts the rest of the params to tag-keys.

Example: $extra = tag_extra_from_params({ class => 'nopad', style => 'float: left' });

         --> $extra = ' class="nopad" style="float: left"'

=cut

sub tag_extra_from_params
{
    my( $params ) = @_;
    my $out = '';

    foreach my $key ( keys %$params )
    {
	if( my $keyval = $params->{$key} )
	{
	    $out .= sprintf " $key=\"%s\"",
	      CGI->escapeHTML( $keyval );
	}
    }

    return $out;
}


##############################################################################

=head2 css_header

Deprecated. Use $site->css->header() instead (L<Para::Frame::CSS/header>).

=cut

sub css_header
{
    return "";
}


##############################################################################

=head2 favicon_header

  favicon_header( $url )

Draws a favicon header.

Paths not beginning with / are relative to the site home.

=cut

sub favicon_header
{
    my( $url ) = @_;

    unless( $url )
    {
	$url = "pf/images/favicon.ico";
    }

    my $home = $Para::Frame::REQ->site->home_url_path;

    $url =~ s/^([^\/])/$home\/$1/;


    my $type = "image/x-icon";
    if( $url =~ /\.(\w+)$/ )
    {
	my $ext = lc($1);
	if( $ext eq 'ico' )
	{
	    $type = "image/x-icon";
	}
	elsif( $ext eq 'png' )
	{
	    $type = "image/png";
	}
	elsif( $ext eq 'gif' )
	{
	    $type = "image/gif";
	}
    }


    return "<link rel=\"shortcut icon\" href=\"$url\" type=\"$type\" />";
}



##############################################################################

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

Default:

  $headline    = 'Are you sure?'
  $text        = ''
  $button_name = 'Yes'

Example:

In an action:

  use Para::Frame::Widget qw( confirm_simple );
  confirm_simple("Remove $obj_name?");
  $obj->remove;

=cut

sub confirm_simple
{
    my( $headline, $text, $button_name ) = @_;

    $headline ||= 'Are you sure?';
    $text ||= '';
    $button_name ||= 'Yes';

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $page = $req->page;
    my $site = $page->site;

    foreach my $confirmed ( $q->param('confirmed') )
    {
	warn "Comparing '$confirmed' with '$headline'\n";
	return 1 if $confirmed eq $headline;
    }

    ## Set up route, confirmation data and throw exception
    # Sets the CURRENT as the next step, and with the CURRENT params
    #
    $req->session->route->plan_next(uri($page->url_path, store_params()));

    $req->set_error_response_path('/confirm.tt');
    my $result = $req->result;

    $result->{'info'}{'confirm'} =
    {
     title => $headline,
     text  => $text,
     button =>
     [
      [ $button_name, undef, 'next_step'],
      ['Backa', undef, 'skip_step'],
     ],
    };

    $q->append(-name=>'confirmed',-values=>[$headline]);
    $q->append(-name=>'step_add_params',-values=>['confirmed']);
    throw('confirm', $headline);
}

=head2 inflect

  inflect( $number, $one, $many )
  inflect( $number, $none, $one, $many )

If called without $none, it will use $many for $none.

Replaces %d with the $number.

Uses $many for negative numbers

example:

  inflect( 1, "no things", "a thing", "%d things")

returns "a thing"

  inflect(0, "a thing", "%d things")

returns "0 things"

=cut

sub inflect # inflection = böjning
{
    my( $number, $none, $one, $many ) = @_;

    # Support calling with or without the $none option

    if( $many )
    {
	# If called with %d, interpolate the number
	$many =~ s/\%d/$number/;
    }
    else
    {
	$many = $one;

	# If called with %d, interpolate the number
	$many =~ s/\%d/$number/;

	$one = $none;
	$none = $many;
    }


    if( $number == 0 )
    {
	return $none;
    }
    elsif( $number == 1 )
    {
	return $one;
    }
    else
    {
	# Also for negative numbers
	return $many;
    }
}


##############################################################################

=head2 pricify

Added as a filter to html burner.

=cut

sub pricify
{
    my( $price ) = @_;
    my $req = $Para::Frame::REQ;

    my $old_numeric = setlocale(LC_NUMERIC);
    my $old_monetary = setlocale(LC_MONETARY);
    if( $req->language->preferred eq "sv" )
    {
	setlocale(LC_MONETARY, "sv_SE");
    }
    else
    {
	setlocale(LC_MONETARY, "en_GB");
    }

    my ($thousands_sep, $grouping, $decimal_point) =
	@{localeconv()}{'mon_thousands_sep', 'mon_grouping', 'mon_decimal_point'};
    setlocale(LC_MONETARY, $old_monetary);

    # Apply defaults if values are missing
    $thousands_sep = '&nbsp;' if $thousands_sep eq ' ' or (not $thousands_sep);
    $decimal_point = ',' unless $decimal_point;

    my @grouping;
    if ($grouping) {
	@grouping = unpack("C*", $grouping);
    } else {
	#warn "Using default grouping!";
	@grouping = (3);
    }

    # To split it surely...
    setlocale(LC_NUMERIC, "sv_SE");
    $price = sprintf("%.2f", $price);
    my ($whole, $part) = split /,/, $price;
    setlocale(LC_NUMERIC, $old_numeric);

    # Thousand grouping
    $_ = $whole;
    1 while
	s/(\d)(\d{$grouping[0]}($|$thousands_sep))/$1$thousands_sep$2/;
#    warn "$_";
    $whole = $_;

    $price = join($decimal_point, $whole, $part);

    return $price;
}


##############################################################################

=head2 calendar

  calendar( $field, $value, \%args )

supported args are
  id
  tdlabel
  label
  label_class
  separator
  style
  class
  maxlength
  size
  onUpdate
  showsTime
  date

=cut

sub calendar
{
    my( $field, $value, $args ) = @_;

    my $q = $Para::Frame::REQ->q;
    my $out = "";

    $args ||= {};
    $value ||= $q->param($field);

    my $id = $args->{'id'} || $field;

    my $tdlabel = $args->{'tdlabel'};
    my $label = $args->{'label'} || '';
    my $label_class = $args->{'label_class'} || '';
    my $separator = $args->{'separator'};
    my $style = $args->{'style'} || 'display: inline-table';
    my $class = $args->{'class'} || '';
    my $maxlength = $args->{'maxlength'};
    my $size = $args->{'size'};

#    debug "CALENDAR";
#    debug datadump($args);


    if( $tdlabel )
    {
	$label = $tdlabel;
	$separator ||= "</td><td>";
    }

    if( $label )
    {
	my $label_out = CGI->escapeHTML( $label );

	$out .= "<label class=\"$label_class\" for=\"$field\">$label_out</label>";
	$out .= $separator;
    }

    $out .= "<table cellspacing=\"0\" cellpadding=\"0\" style=\"$style\" class=\"$class\">";
    $out .= "<tr><td>";

    my $input_style = "width: 100%";

    $out .= input( $field, $value,
		   {
		    size => $size,
		    maxlength => $maxlength,
		    id => $id,
		    class => $class,
		    style => $input_style,
		   });

    my $home = $Para::Frame::REQ->site->home_url_path;

    $out .=
      (
       "</td>".
       "<td valign=\"bottom\" style=\"width: 22px; text-align: right;vertical-align: bottom\">".
       "<img class=\"nopad\" alt=\"calendar\" id=\"${id}-button\" src=\"$home/pf/images/calendar.gif\"/>".
       "</td></tr>"
      );


    # inputField  : "$id",              // ID of the input field
    # ifFormat    : "%Y-%m-%d",        // the date format
    # button      : "[% id %]-button" // ID of the button


    my %setup  =
      (
       inputField  => "\"$id\"",
       ifFormat    => "\"%Y-%m-%d\"",
       button      => "\"${id}-button\"",
      );

    $args->{'onClose'} = $args->{'onUpdate'};

    # Unescaped values
    foreach my $key (qw( onClose showsTime ))
    {
	next unless defined $args->{$key};
	next unless length $args->{$key};
	$setup{$key} = $args->{$key};
    }

# TODO: Make it work
#    if( my $date_in = $args->{'date'} )
#    {
#	my $date_fmt = $date_in->internet_date;
#	my $val = "new Date(\"$date_fmt\")";
#	$setup{'date'} = $val;
#    }



    if( $args->{'showsTime'} )
    {
	$setup{'ifFormat'} = "\"%Y-%m-%d %H.%M\"";
    }

    my $setup_json = "{".join(',',map{"\"$_\":".$setup{$_}} keys %setup)."}";


#    my $setup_json = to_json(\%setup);
#    debug "CALENDER JSON ".$setup_json;

    $out .= qq[
    <script type="text/javascript">
      Calendar.setup($setup_json);
    </script>
];

    $out .= "</table>";

    return $out;
}


##############################################################################

=head2 input_image


$args->{'image_url'} ||
      $Para::Frame::CFG->{'images_uploaded_url'} ||
	'/images';

=cut

sub input_image
{
    my( $key, $value, $args ) = @_;

    my $q = $Para::Frame::REQ->q;
    my $out = "";

    $args ||= {};

    my $maxw = $args->{'maxw'} ||= 400;
    my $maxh = $args->{'maxh'} ||= 300;
    my $version = $args->{'version'};
    my $image_url = $args->{'image_url'} ||
      $Para::Frame::CFG->{'images_uploaded_url'} ||
	'/images';

    if( $value )
    {
	# TODO: rewrite code

	unless( $version )
	{
	    # Hack to recognise radio-context
	    # arc SHOULD be set...
	    $out .= hidden("check_$key", 1);
	    $out .= checkbox($key, $value, 1);
	}

	$out .= "<img alt=\"\" src=\"$image_url/$value\"/>";
    }
    else
    {
	$out .= filefield("${key}__file_image__maxw_${maxw}__maxh_${maxh}");
    }

    return $out;
}


##############################################################################
#### Methods

sub on_configure
{
    my( $class ) = @_;

    my $params =
    {
	'selectorder'     => \&selectorder,
	'selector'        => \&selector,
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
	'htmlarea'        => \&htmlarea,
        'checkbox'        => \&checkbox,
        'radio'           => \&radio,
	'filefield'       => \&filefield,
	'css_header'      => \&css_header,
	'favicon_header'  => \&favicon_header,
	'inflect'         => \&inflect,
	'calendar'        => \&calendar,
    };

    Para::Frame->add_global_tt_params( $params );



    # Define TT filters
    #
    Para::Frame::Burner->get_by_type('html')->add_filters({
	'pricify' => \&pricify,
    });


}


##############################################################################

sub on_reload
{
    # This will bind the newly compiled code in the params hash,
    # replacing the old code

    $_[0]->on_configure;
}


##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::Template::Components>

=cut
