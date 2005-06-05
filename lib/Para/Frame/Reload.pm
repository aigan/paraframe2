#  $Id$  -*-perl-*-
package Para::Frame::Reload;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Reload class
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

Para::Frame::Reload - Reloads updated modules in the app

=head1 SYNOPSIS

  use Para::Frame::Reload;

=head1 DESCRIPTION

Updated actions are always reloaded if touched.

For all other modules; Insert the use row in the module, and it will
be checkd for updates at the beginning of each request.

=cut

use strict;
use vars qw( %COMPILED %INCS );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n"
	unless $Psi::QUIET; # houerly_active.pl
}

use Para::Frame::Utils qw( package_to_module module_to_package );

sub import
{
    my $class = shift;
    my( $package, $file ) = (caller)[0,1];

    $class->register_module($package, $file);
}

sub register_module
{
    my( $class, $package, $file ) = @_;
    my $module = package_to_module($package);

    if( $file )
    {
        $INCS{$module} = $file;
    }
    else
    {
        $file = $INC{$module};
        return unless $file;
        $INCS{$module} = $file;
    }

    $COMPILED{$module} = (stat $file)[9];
}

sub check_for_updates
{
    while( my($filename, $realfilename) = each %INCS )
    {
	my $mtime = (stat $realfilename)[9]
	  or die "Lost contact with $realfilename";

	if( $mtime > $COMPILED{$filename} )
	{
	    warn "  New version of $filename detected !!!\n";

	    my $pkgname = module_to_package( $filename );
#	    my $pkgspace = $pkgname ."::";
#	    # Save global vars
#
#	    no strict 'refs';
#	    warn "    Take a look at what we have:\n";
#	    foreach my $key ( keys %{$pkgspace} )
#	    {
#		my $val = ${*{$pkgspace.$key}{SCALAR}};
#		next unless $val;
#		warn "      $key -> $val\n";
#	    }

	    delete $INC{$filename};
	    require $filename;

	    if( $pkgname->can('on_reload') )
	    {
		warn "    Calling $pkgname->on_reload()\n";
		$pkgname->on_reload;
	    }


#	    warn "    After require:\n";
#	    foreach my $key ( keys %{$pkgspace} )
#	    {
#		my $val = ${*{$pkgspace.$key}{SCALAR}};
#		next unless $val;
#		warn "      $key -> $val\n";
#	    }

	    $COMPILED{$filename} = $mtime;
	}
    }
}

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
