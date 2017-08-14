package Para::Frame::Reload;
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

Para::Frame::Reload - Reloads updated modules in the app

=head1 SYNOPSIS

  use Para::Frame::Reload;

=head1 DESCRIPTION

Updated actions are always reloaded if touched.

For all other modules; Insert the use row in the module, and it will
be checkd for updates at the beginning of each request. The use row
must be loaded AFTER the definition of any C<import()> method. If
L<Exporter> is used, place C<use Para::Frame::Reload> after the C<use
base qw( Exporter) >.

=head2 call_import()

  Para::Frame::Reload->call_import()
  Para::Frame::Reload->call_import( $pkgname )

The Relod module will intercept calls to import(), regestring the
modules and the parameters they are sending.  When a registred module
is reloaded, the import() will be called from the perspective of each
calling module.

This will not be done if the registred module has defined a
on_reload() method. In that case, you will have to call this method
yourself;

If you can call it without $pkgname, it will be set to the caller
package.


The resone for this import() handling is that even if the module
is reloaded, the other modules that have imported functions still has
a reference to the old version. (If you used Exporter)

This is done by creating an import() function in the module that will
call the original import(). This original import is probably the
Exporter import() function, loaded by UNIVERSAL.

Subsequent imports are called via special on_reload_...() methods
placed in the module namespace;

=head2 sub on_reload

If the module has a on_reload() method, it will be called after the
modules has been reloaded.  This is not a method of
Para::Frame::Reload.

You can use this callback for calling the modules_importing_from_us()
method, like this:

  sub on_reload
  {
      Para::Frame::Reload->modules_importing_from_us;
  }

=head2 modules_importing_from_us()

  Para::Frame::Reload->modules_importing_from_us()
  Para::Frame::Reload->modules_importing_from_us( $pkgname )

If you can call it without C<$pkgname>, it will be set to the caller
package.

This will reload all modules that C<use>d C<$pkgname>. That reload
will take care of the import() calls, making the call_import() method
redundant.

This is necessary to do if $pkgname has exported any constants. See
c<sub on_reload> for example usage.

=head2 Compilation errors

All warnings during the recompilation will be hidden. If the
compilation failes, they will be shown along with the compilation
error messages.

The previous version of the module will remain in memory and continue
being used. This gives you time to correct the errors, without any
interruptions, if possible.

=cut

use 5.012;
use warnings;
use vars qw( %COMPILED %INCS %CALLER %IMPORTS );


our $DEBUG = 0;


##############################################################################

=head2 import

=cut

sub import
{
    my $class = shift;
    my( $package, $file ) = (caller)[0,1];

    $class->register_module($package, $file);
}


##############################################################################

=head2 register_module

=cut

sub register_module
{
    my( $class, $package, $file ) = @_;
    my $module = package_to_module($package);

    warn "REGISTER MODULE $package\n";

    if ( $file )
    {
        $INCS{$module} = $file;
    }
    else
    {
        $file = $INC{$module};
        return unless $file;
        $INCS{$module} = $file;
    }


    unless( $package eq __PACKAGE__ )
    {
        warn "  ******  $package registred as $module -> $file\n" if $DEBUG;
        if ( my $coderef = $package->can('import') )
        {
            warn "          $package has an import() function defined ($coderef)\n" if $DEBUG;
            unless ( $COMPILED{$module} )
            {
                $IMPORTS{ $module } = $coderef;
                no strict 'refs';
#		warn "  --> Should do wrapping up\n";
#		*{"$package\::import"} = sub
                my $subdef = '
                sub import
	        {
		    my $class = shift;
		    my $callpkg = caller(0);

		    warn "      \$Para::Frame::Reload::CALLER{$class}{$callpkg} = [@_]\n" if $Para::Frame::Reload::DEBUG;
		    $Para::Frame::Reload::CALLER{$class}{$callpkg} = [@_];

                    my $subcode = "
                      package $callpkg;
                      &{\$Para::Frame::Reload::IMPORTS{\'$module\'}}(\'$class\', \@_);
                    ";

                    warn "      Subcode defined:\n$subcode\n" if $Para::Frame::Reload::DEBUG > 1;
                    my $res = eval $subcode;
                    if( $@ )
                    {
                       die $@;
                    }

		    warn "      Returned $res from $coderef $class @_\n" if $Para::Frame::Reload::DEBUG;
		    return $res;
		}
';
                warn "Evaluating:\npackage $package; $subdef\n" if $DEBUG > 1;
                no warnings;
                eval "package $package; $subdef";

            }
            else
            {
                warn "  ------> But we already know that!\n" if $DEBUG;
            }
        }
    }

    $COMPILED{$module} = (stat $file)[9];
    warn "register done\n" if $DEBUG;
}


##############################################################################

=head2 check_for_updates

=cut

sub check_for_updates
{
#    $Exporter::Verbose = 1; # DEBUG

    while ( my($filename, $realfilename) = each %INCS )
    {
        my $mtime = (stat $realfilename)[9]
          or die "Lost contact with $realfilename";

        if ( $mtime > $COMPILED{$filename} )
        {
            warn "  New version of $filename detected!\n";

            Para::Frame::Reload->reload( $filename, $mtime );
        }
    }
}


##############################################################################

=head2 reload

  Para::Frame::Reload->reload( $module, $mtime )

C<$module> is the filename given to C<require>

=cut

sub reload
{
    my( $class, $module, $mtime ) = @_;

    unless ( $INCS{$module} )
    {
        warn "Skipping unregistred module $module during reload\n";
        return 0;
    }

    $mtime ||= (stat $INCS{$module})[9]
      or die "Lost contact with $module: $INCS{$module}";

    my $pkgname = module_to_package( $module );

    delete $INC{$module};
    my $errors = "";
    eval
    {
        # Get rid of warnings...
        open OLDERR, ">&", \*STDERR  or die "Can't dup STDERR: $!";
        close STDERR;
        open STDERR, '>', \$errors   or die "Can't redirect STDERR: $!";
        binmode(STDERR, ":utf8");

        require $module;
    };

    open STDERR, ">&OLDERR"    or die "Can't dup OLDERR: $!";
    close OLDERR;
    binmode(STDERR, ":utf8");

    if ( $@ )
    {
        my $error_out = "";
        foreach my $row ( split /\n/, $errors )
        {
            # Filters also Constant subroutine...
            next if $row =~ /^subroutine .{1,50} redefined at/i;
            $error_out .= "* $row\n";
        }

        if ( $error_out )
        {
            $error_out .= "* -----------------------\n";
        }

        foreach my $row ( split /\n/, $@ )
        {
            next if $row =~ /^Compilation failed/;
            $error_out .= "* $row\n";
        }

        warn "*************************\n";
        warn "****  COMPILATION FAILED: $module\n";
        warn $error_out;
        warn "*************************\n";

        # Set a global error state
        $Para::Frame::Result::COMPILE_ERROR{$module} = $@;

        $COMPILED{$module} = $mtime; # Do not try again
        return 0;
    }
    elsif ( length $errors )
    {
        foreach my $row ( split /\n/, $errors )
        {
            # Filters also Constant subroutine...
            next if $row =~ /subroutine .{1,50} redefined at/i;
            warn "$row\n";
        }
    }

    if ( $pkgname->can('on_reload') )
    {
        $pkgname->on_reload;
    }
    elsif ( $pkgname->can('import') )
    {
#	warn "============ call_import\n";
        Para::Frame::Reload->call_import($pkgname);
#	warn "============ call_import done\n";
    }

    Para::Frame->run_hook(undef, 'on_reload', $module );

    # Remove eventual global error state
    delete $Para::Frame::Result::COMPILE_ERROR{$module};

    $COMPILED{$module} = $mtime;
}


##############################################################################

=head2 call_import

=cut

sub call_import
{
    my( $class, $pkgname ) = @_;
    #
    # Call import for modules importing from $pkgname

    $pkgname ||= caller(0);

    warn "    $pkgname can import\n" if $DEBUG;
    my $module = package_to_module( $pkgname );
    if ( my $called = $CALLER{ $pkgname } )
    {
        warn "      has been called\n" if $DEBUG;
        foreach my $callerpkg ( keys %$called )
        {
			warn "        by $callerpkg\n" if $DEBUG;
			my $importsubname = $pkgname;
			$importsubname =~ s/::/__/g;

			# Sometimes ->can will return true but we
			# still won't find it via
			# &{"${callerpkg}::on_reload__$importsubname"}
			#
			my $coderef = $callerpkg->can("on_reload__$importsubname");
			unless( $coderef )
			{
			    warn "          Creating a callback sub\n" if $DEBUG;
			    no strict 'refs';

                my $callbacksub =  "
                            package $callerpkg;
                            sub on_reload__$importsubname
			    {
                                shift \@_;
                                #warn \"+++++++++++++++ in on_reload__$importsubname\\n\";
				&{\$Para::Frame::Reload::IMPORTS{\'$module\'}}(\'$pkgname\', \@_);
			    };
                            ";
			    warn "          Defining the callbacksub:\n$callbacksub\n" if $DEBUG > 1;
			    eval $callbacksub;
			    $coderef = $callerpkg->can("on_reload__$importsubname");
			}

			my $args = $called->{$callerpkg};
			warn "          Calling the callback sub with @$args\n" if $DEBUG;
			no strict 'refs';
            local ($^W) = 0 ;   # Disable redefine warnings
			&{$coderef}( $callerpkg, @$args );
#			$callerpkg->"on_reload__$importsubname"(@$args);
			warn "          DONE\n" if $DEBUG;
        }
    }

}


##############################################################################

=head2 modules_importing_from_us

=cut

sub modules_importing_from_us
{
    my( $class, $pkgname ) = @_;
    #
    # Reload the modules that imports from caller

    $pkgname ||= caller(0);

    warn "    $pkgname...\n" if $DEBUG;
    my $module = package_to_module( $pkgname );
    if ( my $called = $CALLER{ $pkgname } )
    {
        warn "      has been called\n" if $DEBUG;
        foreach my $callerpkg ( keys %$called )
        {
            warn "        by $callerpkg\n" if $DEBUG;
            $class->reload( $callerpkg );
        }
    }
}


##############################################################################

=head2 package_to_module

NOTE: Defined in Para::Frame::Utils but given here to avoid cyclic
dependency

=cut

sub package_to_module
{
    my $package = shift;
    $package =~ s/::/\//g;
    $package .= ".pm";
    return $package;
}


##############################################################################

=head2 module_to_package

=cut

sub module_to_package
{
    my $module = shift;
    $module =~ s/\//::/g;
    $module =~ s/\.pm$//;
    return $module;
}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
