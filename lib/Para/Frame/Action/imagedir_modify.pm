package Para::Frame::Action::imagedir_modify;

use 5.010;
use strict;
use warnings;

use Para::Frame::Utils qw( throw debug trim datadump );

use Para::Frame::Image;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    my $dir = $req->page->dir;

    if( $q->param('publish') )
    {
	my $pdir = $dir->parent;
	my $files = $dir->files;
	foreach my $file ( @$files )
	{
	    next unless $file->name =~ /(.*)\.(jpe?g|tif|gif)$/i;
	    my $basename = $1;
	    bless $file, 'Para::Frame::Image';

	    my $destname = $basename."-o.jpg";
	    if( $pdir->has_file($destname) )
	    {
		my $old = $pdir->get($destname);
		if( $old->mtime >= $file->mtime )
		{
		    debug "Skipping ".$file->name;
		    next;
		}
	    }

	    my $destfile = $pdir->sys_path_slash.$destname;
	    my $new = $file->save_as($destfile);
	    $req->may_yield;

	    $new->resize_normal;
	    $req->may_yield;
	    $new->resize_thumb_y;
	    $req->may_yield;
	    $new->resize_thumb_x;

	    $req->note('Published '.$file->name);
	}
    }


    my $refresh =  $q->param('refresh') || 0;
    if( $refresh )
    {
	my $files = $req->page->dir->files;
	foreach my $file ( @$files )
	{
#	    debug "Looking at ".$file->name;
	    next unless $file->name =~ /-o\./;

	    bless $file, 'Para::Frame::Image';
	    $req->may_yield;
	    $file->resize_normal;
	    $req->may_yield;
	    $file->resize_thumb_y;
	    $req->may_yield;
	    $file->resize_thumb_x;

	    $req->note('Resized '.$file->name);
	}
    }

    return "Done";
}

1;
