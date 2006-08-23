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
use Carp qw( cluck confess croak );
use Data::Dumper;
use IO::File;
use CGI;

use locale;
use POSIX qw(locale_h);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use base qw( Exporter );
BEGIN
{
    @Para::Frame::Widget::EXPORT_OK

      = qw( slider jump submit go go_js forward forward_url preserve_data alfanum_bar rowlist list2block selectorder param_includes hidden input textarea filefield css_header confirm_simple inflect  );

}


use Para::Frame::Reload;
use Para::Frame::Utils qw( trim throw debug uri store_params );
use Para::Frame::L10N qw( loc );

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

Draw a link to C<$template> with text C<$label> and query params
C<%attrs>.

A 'href_target' attribute will set the target frame for the link.

A 'href_onclick' attribute will set the corresponding tag attribute.

A 'href_class' attribute will set the class for the link.

A 'href_id' attribute will set the id for the link.

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

sub jump_extra
{
    my( $template, $attr ) = @_;

    $attr ||= {};

    my $extra = "";
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

    my $class_val = delete ${$attr}{'href_class'};
    if( $class_val )
    {
	$extra .= " class=\"$class_val\"";
    }
    elsif( not defined $class_val )
    {
	if( $Para::Frame::REQ->is_from_client and $template )
	{
	    # Mark as same_place if link goes to current page
	    if( $Para::Frame::REQ->page->url_path eq $template and not $attr->{'run'} )
	    {
		$extra .= " class=\"same_place\"";
	    }
	}
    }

    return $extra;
}


#######################################################################

=head2 submit

  submit( $label, $setval )

Draw a form submit button with text $label and value $setval.

Default label = 'Forts�tt'

Default setval is to not have a value

=cut

sub submit
{
    my( $label, $setval, $attr ) = @_;

    die "Too many args for submit()" if $attr and not ref $attr;

    $label ||= 'Continue';
    $attr ||= {};

    my $extra = "";

    my $label_out = loc($label);

    if( my $class = $attr->{'href_class'} )
    {
	$extra .= " class=\"$class\"";
    }

    my $name = '';
    $name = "name=\"$setval\"" if $setval;

    return "<input type=\"submit\" $name value=\"$label_out\">";
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

All fields set by %attrs must exist in the form. (Maybe as hidden
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

    my $extra = "";
    if( my $val = delete $attr->{'href_target'} )
    {
	$extra .= "target=\"$val\" ";
    }
    if( my $val = delete $attr->{'href_class'} )
    {
	$extra .= "class=\"$val\" ";
    }

    my $query = join '', map sprintf("document.f.$_.value='%s';", $attr->{$_}), keys %$attr;
    return "<input type=\"button\" value=\"$label\" onClick=\"${query}go('$template', '$run')\" $extra />";
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

    my $extra = jump_extra( $template, $attr );

    my $url = forward_url( $template, $attr );

    $label = '???' unless length $label;

    return "<a href=\"$url\"$extra>$label</a>";
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
	    $text .= "<input type=\"hidden\" name=\"$key\" value=\"$val\" />\n";
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
    my $text = join(' | ', map "<a href=\"$template?$name=$part$_\"$extra>\U$_</a>", 'a'..'z','�','�','�');
    $text = "| <a href=\"$template?$name=\">0-9</a> | ".$text." |";
    $text =~ s/�/&aring;/g;
    $text =~ s/�/&auml;/g;
    $text =~ s/�/&ouml;/g;
    $text =~ s/�/&Aring;/g;
    $text =~ s/�/&Auml;/g;
    $text =~ s/�/&Ouml;/g;

#    return "\U�ke �rlansson\n";
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
    foreach my $row ( split /\r?\n/, ($q->param($name)||'') )
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

    return sprintf('<input type="hidden" name="%s" value="%s" />',
		   CGI->escapeHTML( $key ),
		   CGI->escapeHTML( $value ),
		   );
}

#######################################################################

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

  tdlabel: sets the separator to '<td>'

  id: used for label. Defaults to C<$field>

All other attributes are directly added to the input tag, with the
value html escaped.

Example:

  Drawing a input field widget wit a label
  [% input('location_name', '', label=loc('Location')) %]



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
    my $prefix = "";
    my $separator = delete($params->{'separator'}) || '';
    if( my $tdlabel = delete $params->{'tdlabel'} )
    {
	$separator = "<td>";
	$params->{'label'} = $tdlabel;
    }
    if( my $label = delete $params->{'label'} )
    {
	my $id = $params->{id} || $key;
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
	$params->{id} = $key;
    }

    foreach my $key ( keys %$params )
    {
	$extra .= sprintf " $key=\"%s\"",
	  CGI->escapeHTML( $params->{$key} );
    }

    if( $prefix )
    {
	$prefix .= $separator;
    }

    return sprintf('%s<input type="text" name="%s" value="%s" size="%s" maxlength="%s"%s />',
		   $prefix,
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

C<$value> will be taken from query param C<$field> or C<$value>, in
turn.

Attributes:

  cols: width (default is 60)

  rows: hight (default is 20)

  label: draws a label before the field with the given text

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
    my $cols = $params->{'cols'} || 75;
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

    my $extra = "";
    my $prefix = "";
    my $separator = delete $params->{'separator'} || '';
    if( my $label = delete $params->{'label'} )
    {
	my $id = $params->{id} || $key;
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

    $params->{'wrap'} ||= "virtual";

    foreach my $key ( keys %$params )
    {
	$extra .= sprintf " $key=\"%s\"",
	  CGI->escapeHTML( $params->{$key} );
    }

    if( $prefix )
    {
	$prefix .= $separator;
    }

    return sprintf('%s<textarea name="%s" cols="%s" rows="%s"%s>%s</textarea>',
		   $prefix,
		   CGI->escapeHTML( $key ),
		   CGI->escapeHTML( $cols ),
		   CGI->escapeHTML( $rows ),
		   $extra,
		   CGI->escapeHTML( $value ),
		   );
}


#######################################################################

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
    my $id = $params->{id} || $field;

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

    if( $checked and $checked ne 'f')
    {
	$extra .= " checked";
    }

    if( $prefix )
    {
	$prefix .= $separator;
    }

    if( $suffix )
    {
	$suffix = $separator . $suffix;
    }

    return sprintf('%s<input type="checkbox" name="%s" value="%s"%s>%s',
		   $prefix,
		   CGI->escapeHTML( $field ),
		   CGI->escapeHTML( $value ),
		   $extra,
		   $suffix,
		   );
}


#######################################################################

=head2 radio

  radio( $field, $value, $checked, %attrs )

  radio( $field, $value, %attrs )

Draws a radio button with fied name $field and value $value.

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
	$checked = $previous[0]?1:0;
    }

    defined $value or croak "value param for radio missing";

    my $extra = "";
    my $prefix = "";
    my $suffix = "";
    my $separator = delete $params->{'separator'} || '';
    my $label_class = delete $params->{'label_class'};
    my $id = $params->{id};

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
	$extra .= " checked";
    }

    if( $prefix )
    {
	$prefix .= $separator;
    }

    if( $suffix )
    {
	$suffix = $separator . $suffix;
    }

    return sprintf('%s<input type="radio" name="%s" value="%s"%s>%s',
		   $prefix,
		   CGI->escapeHTML( $field ),
		   CGI->escapeHTML( $value ),
		   $extra,
		   $suffix,
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

    return sprintf('<input type="file" name="%s" value="%s" size="%s" />',
		   CGI->escapeHTML( $key ),
		   CGI->escapeHTML( $value ),
		   CGI->escapeHTML( $cols ),
		   );
}



#######################################################################

=head2 css_header

  css_header( \%attrs )
  css_header( $url )

Draws a css header.

Paths not beginning with / are relative to the site home.

The style may be given by using L<Para::Frame::Template::Meta/css> or
by setting a TT param either for the site or globaly.

The persistant styles will always be used and is a ref to list of URLs.

The alternate can be switched between using the browser, or via
javascript, and is a ref to ha hash of stylenames and listrefs holding
the URLs. The default points to which of the alternate styles to use
if no special one is selected.

The persitant and alternate list items may be coderefs. The code will
be run with req as first param. They should return the paths for the
stylefiles. Those may be translated as above.

Example:
    $attrs =
     {
      persistent => [ "css/default.css" ],
      alternate =>
      {
       light => [ "css/light.css" ],
       blue => [ sub{"css/blue.css"} ],
      },
      default => 'blue',
     };

=cut

sub css_header
{
    my( $p ) = @_;

    my $req = $Para::Frame::REQ;
    my $home = $req->site->home_url_path;

    if( $p )
    {
	unless( ref $p )
	{
	    $p =
	    {
	     'persistent' => [ $p ],
	    };
	}
    }
    else
    {
	$p =
	{
	 'persistent' => ['pf/css/default.css'],
	};
    }

    my $default = $Para::Frame::U->style || $p->{'default'} || 'default';
    my $persistent = $p->{'persistent'} || [];
    my $alternate = $p->{'alternate'} || {};
    $persistent = [$persistent] unless ref $persistent;

    unless( $alternate->{$default} )
    {
	$default = $p->{'default'};
    }

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

    foreach my $style_in ( @$persistent )
    {
	my $style = $style_in;
	$style = &$style($req) if UNIVERSAL::isa($style,'CODE');
	$style =~ s/^([^\/])/$home\/$1/;
	$out .= "<link rel=\"Stylesheet\" href=\"$style\" type=\"text/css\" />\n";
    }

    if( $default )
    {
	foreach my $style ( @{$alternate->{$default}} )
	{
	    $style = &$style($req) if UNIVERSAL::isa($style,'CODE');
	    $style =~ s/^([^\/])/$home\/$1/;
	    $out .= "<link rel=\"Stylesheet\" title=\"$default\" href=\"$style\" type=\"text/css\" />\n";
	}
    }

    foreach my $title ( keys %$alternate )
    {
	next if $title eq $default;
	foreach my $style ( @{$alternate->{$title}} )
	{
	    $style = &$style($req) if UNIVERSAL::isa($style,'CODE');
	    $style =~ s/^([^\/])/$home\/$1/;
	    $out .= "<link rel=\"alternate stylesheet\" title=\"$title\" href=\"$style\" type=\"text/css\" />\n";
	}
    }

    return $out;
}






#######################################################################

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

Default:

  $headline    = '�r du s�ker?'
  $text        = ''
  $button_name = 'Ja'

Example:

In an action:

  use Para::Frame::Widget qw( confirm_simple );
  confirm_simple("Remove $obj_name?");
  $obj->remove;

=cut

sub confirm_simple
{
    my( $headline, $text, $button_name ) = @_;

    $headline ||= '�r du s�ker?';
    $text ||= '';
    $button_name ||= 'Ja';

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


    $page->set_error_template('/confirm.tt');
    my $result = $req->result;
    my $home = $site->home_url_path;

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

sub inflect # inflection = b�jning
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


=head2 pricify

Added as a filter to html burner.

=cut

sub pricify
{
    my( $price ) = @_;

    my $old_numeric = setlocale(LC_NUMERIC);
    my $old_monetary = setlocale(LC_MONETARY);
    if( preferred_language() eq "sv" )
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
        'checkbox'        => \&checkbox,
        'radio'           => \&radio,
	'filefield'       => \&filefield,
	'css_header'      => \&css_header,
	'favicon_header'  => \&favicon_header,
	'inflect'         => \&inflect,
    };

    Para::Frame->add_global_tt_params( $params );



    # Define TT filters
    #
    Para::Frame::Burner->get_by_type('html')->add_filters({
	'pricify' => \&pricify,
    });


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

L<Para::Frame>, L<Para::Frame::Template::Components>

=cut
