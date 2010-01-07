package Para::Frame::SVG_Chart;

=head1

Para::Frame::SVG_Chart

=cut

use 5.010;
use strict;
use warnings;
use utf8;

use XML::Simple;


use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

use Exporter qw( import );
our @EXPORT_OK = qw( bar_chart_svg pie_chart_svg );

use constant PI => 4 * atan2(1, 1);


##############################################################################

=head2 pie_chart_svg

my $svg = pie_chart_svg( $parts );

 $parts   A list of parts, where each part is a hash-ref of:
   value
   label
   color

=cut

sub pie_chart_svg
{
    my( $parts ) = @_;

    my $line_w = 1;
    my $radius = 150;
    my $width = $radius * 2  +  $line_w * 2;

    my $svg = {
               xmlns         => 'http://www.w3.org/2000/svg',
               'xmlns:xlink' => 'http://www.w3.org/1999/xlink',
               viewBox       => join(' ', -($radius+$line_w),
                                     -($radius+$line_w),
                                     $width, $width),
              };

    my $lastx  = cos(0) * $radius;
    my $lasty  = sin(0) * $radius;
    my $nextx;
    my $nexty;
    my $bordercolor = 'black';

    my $i = 1;

    my $total = 0;
    map { $total += $_->{value} || 0 } @$parts;
    return
      unless $total;

    my $seg_rads = 0;
    my $old_rads = 0;

    my @paths;
    my @texts;

    foreach my $part (@$parts)
    {
        my $part_secs  = $part->{value};
        next unless $part_secs;

        $seg_rads += $part_secs/$total * 2*PI;  # this angle will be
                                                # current plus all
                                                # previous
        my $large_arc  = ($part_secs/$total > 1/2) ? 1 : 0;

        $nextx = cos($seg_rads) * $radius;
        $nexty = sin($seg_rads) * $radius;

        my $rel_x = $nextx - $lastx;
        my $rel_y = $nexty - $lasty;

        push @paths
          , {
             d                 => "M 0 0 l $lastx,$lasty a$radius,$radius 0"
                 ." $large_arc,1 $rel_x,$rel_y z",
             fill              => $part->{color},
             stroke            => $bordercolor,
             'stroke-width'    => $line_w,
             'stroke-linejoin' => 'round',
            };

        if( $part_secs/$total > .03 )
        {
            my $textx = cos(($seg_rads + $old_rads) / 2) * $radius *2/3 - 30;
            my $texty = sin(($seg_rads + $old_rads) / 2) * $radius *2/3;

            push @texts
              , {
                 x       => $textx,
                 y       => $texty,
                 fill    => $bordercolor,
                 content => ($part->{label} || $part) .' '
                     . int($part_secs * 100 / $total) .'%',
                };
        }

        $lastx    = $nextx;
        $lasty    = $nexty;
        $old_rads = $seg_rads;
        $i++;
    }

    $svg->{g} = [
                 { path => \@paths },
                 { text => \@texts },
                ];

    return XMLout( $svg, RootName => 'svg' );
}


##############################################################################

=head2

my $svg = pie_chart_svg( $parts,
                         label_func => \&sec_to_str,
                         label      => 'Header of all!',
                       );
 $parts   A list of parts, where each part is a hash-ref of:
   value
   label
   color

Properties can be:
  line_w
  bar_max_h
  grid_y_lines
  text_margin
  font_size_factor
  label_func
  label

=cut

sub bar_chart_svg
{
    my( $parts, %props ) = @_;

    return ''
      unless $parts and @$parts;

    my $line_w           = $props{line_w}           || 1;
    my $bar_max_h        = $props{bar_max_h}        || 200;
    my $grid_y_lines     = $props{grid_y_lines};
    my $text_margin      = $props{text_margin}      || 5;
    my $font_size_factor = $props{font_size_factor} || .7;
    my $label_func       = $props{label_func      } || sub{return @_};

    my $max          = 0;
    map { $max = ( $_->{value} > $max ? ( $_->{value} || 0 ) : $max ) } @$parts;

    return ''
      if $max == 0;

    unless( $grid_y_lines )
    {
	if( $max < 15 )
	{
	    $grid_y_lines = $max;
	}
	else
	{
	    my $step = int($max/11);

	    $grid_y_lines = 11;
	    $max = ($step+1) * 11;
	}
    }

    # Chart is from 0,0, with the first bars bottom left at $line_w,0
    my $grid_h       = $bar_max_h / $grid_y_lines;
    my $font_size    = $grid_h * .7;
    my $chart_h      = $bar_max_h  + $grid_h; # Add 1 grid_h
    my $chart_w      = $bar_max_h * 2;

    my $top_y        = -($chart_h + $line_w) - $font_size;
    $top_y -= $grid_h if( $props{label} );
    my $bottom_y     = $line_w / 2 + 150;

    my $height       = $bottom_y - $top_y;

    my $left_x       = -$font_size * 6 - $line_w;
    my $right_x      = $chart_w + $line_w;

    my $width        = $right_x - $left_x;
    my $bar_w        = ($chart_w - $line_w) / @$parts;
    my $bordercolor  = 'black';
    my $font_size_bottom  = $bar_w * .7;


    my $svg = {
               xmlns             => 'http://www.w3.org/2000/svg',
               'xmlns:xlink'     => 'http://www.w3.org/1999/xlink',
               viewBox           => "$left_x $top_y $width $height",
               g                 => [ {}, {}, {}, {} ], # Layers for rendering
               stroke            => $bordercolor,
               'stroke-linejoin' => 'round',
               'stroke-width'    => $line_w,
               'font-size'       => $font_size,
              };

    # Chart frame and background
    push @{$svg->{g}[0]{rect}}
      , {
         x      => 0,
         y      => -$chart_h,
         width  => $chart_w,
         height => $chart_h,
         fill   => 'none',
        };

    # Add top label
    if( $props{label} )
    {
        push @{$svg->{g}[0]{text}}
          , {
             x             => 0,
             y             => $top_y + $font_size,
             'text-anchor' => 'start',
             content       => $props{label},
            };
    }

    # Make grid
    foreach my $line (0 .. $grid_y_lines)
    {
        push @{$svg->{g}[1]{line}}
          , {
             x1 => -$line_w / 2  -  $text_margin / 2,
             y1 => -$line * $grid_h,
             x2 => $chart_w  -  $line_w / 2,
             y2 => -$line * $grid_h,
            };
        push @{$svg->{g}[1]{text}}
          , {
             x             => -($line_w + $text_margin),
             y             => -$line * $grid_h  +  $font_size / 3,
             'text-anchor' => 'end',
             content       => &$label_func(int($line * $max / $grid_y_lines)),
            };
    }

    my $current_x = $line_w;
    foreach my $part (@$parts)
    {
        unless( $part->{bars} )
        {
            $part->{bars}
              = [{
                  color             => $part->{color            },
                  value             => $part->{value            },
                  link              => $part->{link             },
                  value_label       => $part->{value_label      },
                  value_extra_label => $part->{value_extra_label},
                 }];
        }

        my $bar_y = 0;
        foreach my $bar (@{$part->{bars}})
        {
            my @groups; # Putting it all in SVG groups to get order
            my $bar_h = ( $bar->{value} || 0 ) * $bar_max_h / $max;
            $bar_y -= $bar_h;

            # The bar itself
            push @groups
              , { rect => [{
                            x       => $current_x,
                            y       => $bar_y,
                            width   => $bar_w - $line_w,
                            height  => $bar_h,
                            fill    => $bar->{color},
                            opacity => .8,
                           }]
                };

            # Text in top of bar
            if(     $bar->{value_label} and @{$part->{bars}} > 1
                and $bar_h > $font_size
              )
            {
                my $text_y = $bar_y + $font_size;

                push @groups
                  , { text => [{
                                x             => $current_x + $bar_w / 2,
                                y             => $text_y,
                                'text-anchor' => 'middle',
                                content       => $bar->{value_label},
                                'font-size'   => $font_size * 2/3,
                               }]
                    };
            }

            if(     $bar->{value_extra_label}
                and $bar_h > $font_size * 2
              )
            {
                my $text_x = $current_x + $bar_w * 2 / 3;
                my $text_y = $bar_y  +  $bar_h / 2;
                my $on_bar_font_size = $bar_w * 2/3 < $font_size ? $bar_w * 2/3
                  :                                                $font_size;
                push @groups
                  , { text => [{
                                x             => $text_x,
                                y             => $text_y,
                                'text-anchor' => 'middle',
                                content       => $bar->{value_extra_label},
                                'font-size'   => $on_bar_font_size,
                                transform     => "rotate(270 $text_x, $text_y )",
                               }]
                    };
            }

            if( $bar->{'link'} || $part->{'link'} )
            {
                push @{$svg->{g}[2]{a}}
                  , {
                     'xlink:href'  => $bar->{'link'}     || $part->{'link'},
                     'xlink:title' => $bar->{'link_alt'} || $part->{'link_alt'},
                     g             => \@groups,
                    };
            }
            else
            {
                push @{$svg->{g}[2]{g}}
                  , @groups;
            }
        }

        if( $part->{value_label} )
        {
            my $text_y = $bar_y - $font_size/3;

            push @{$svg->{g}[1]{text}}
              , { text => [{
                            x             => $current_x + $bar_w / 2,
                            y             => $text_y,
                            'text-anchor' => 'middle',
                            content       => $part->{value_label},
                            'font-size'   => $font_size * 2/3,
                           }]
                };
        }

        # Label under bar
        my $text_x = $current_x  +  $bar_w * 3 / 5;
        push @{$svg->{g}[1]{text}}
          , {
             x             => $text_x,
             y             => $text_margin * 2,
             'text-anchor' => 'end',
             transform     => "rotate(310 $text_x, $text_margin )",
             content       => $part->{label},
	     'font-size'   => $font_size_bottom,
            };

        $current_x += $bar_w;
    }

    return XMLout( $svg, RootName => 'svg' );
}


##############################################################################

1;
