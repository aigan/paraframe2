package Para::Frame::Client::Upload;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2013-2014 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Client::Upload - The client for uploads

=cut

use 5.010;
use strict;
use warnings;
use utf8; # Using 'Ã' in deunicode()

use Data::Dumper;
use Encode; # encode decode
use CGI;
use JSON::XS;
use JSON;
use Image::Magick;
use URI;
use Data::GUID;


use Apache2::RequestRec;
use Apache2::Connection;
use Apache2::Const -compile => qw( DECLINED DONE );
use Apache2::SubRequest ();

#use jQuery::File::Upload;

use Para::Frame::Reload;

our $r;
our $s;
our $DEBUG = 0;


=head1 DESCRIPTION

Using pf/share/html/pf/pkg/jQuery-File-Upload-8.7.1

=cut


##############################################################################

sub handler
{
    ( $r ) = @_;
    $s = Apache2::ServerUtil->server;

    my $dirconfig = $r->dir_config;
    my $method = $r->method;

    if( $dirconfig->{'site'} and $dirconfig->{'site'} eq 'ignore' )
    {
	return Apache2::Const::DECLINED;
    }

    $| = 1;

    $r->content_type('text/plain');

    my $ubase = $r->unparsed_uri;
    $ubase =~ s(/pf/upload/)(/files);

    my $sr = $r->lookup_uri($ubase);
    my $udir = $sr->filename;

    $s->log_error( "Uploading to $udir" ) if $DEBUG;


    # Based on jQuery::File::Upload; Reimplementing the functions here
    # because that module was too messy!

    my $ul = Para::Frame::Client::Upload->new();
    $ul->{upload_url_base} = $ubase;
    $ul->{script_url} = $r->unparsed_uri;
    $ul->{upload_dir} = $udir;
    $ul->{tmp_dir} = $udir;

    $ul->handle_request;


    $r->print( $ul->output );

#    $r->print(Dumper($ul)) if $DEBUG;

    $s->log_error("$$: Done") if $DEBUG;

    return Apache2::Const::DONE;

}

our %errors =  (
	'_validate_max_file_size' => 'File is too big',
	'_validate_min_file_size' => 'File is too small',
	'_validate_accept_file_types' => 'Filetype not allowed',
	'_validate_reject_file_types' => 'Filetype not allowed',
	'_validate_max_number_of_files' => 'Maximum number of files exceeded',
	'_validate_max_width' => 'Image exceeds maximum width',
	'_validate_min_width' => 'Image requires a minimum width',
	'_validate_max_height' => 'Image exceeds maximum height',
	'_validate_min_height' => 'Image requires a minimum height'
);


sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    my $self =
    {
		field_name => 'files[]',
		ctx => undef,
		cgi	=> undef,
		thumbnail_width => 80,
		thumbnail_height => 80,
		thumbnail_quality => 70,
		thumbnail_format => 'jpg',
		thumbnail_density => undef,
		format => 'jpg',
		quality => 70,

		thumbnail_filename => undef,
		thumbnail_prefix => 'thumb_',
		thumbnail_postfix => '',
		filename => undef,
		client_filename => undef,
		show_client_filename => 1,
		use_client_filename => undef,
		filename_salt => '',
		script_url => undef,
		tmp_dir => '/tmp',
		should_delete => 1,

		absolute_filename => undef,
		absolute_thumbnail_filename => undef,

		delete_params => [],

		upload_dir => undef,
		thumbnail_upload_dir => undef,
		upload_url_base => undef,
		thumbnail_url_base => undef,
		relative_url_path => '/files',
		thumbnail_relative_url_path => undef,
		relative_to_host => undef,
		delete_url => undef,

		data => {},

		#callbacks
		post_delete => sub {},
		post_post => sub {},
		post_get => sub {},

		#pre calls
		pre_delete => sub {},
		pre_post => sub {},
		pre_get => sub {},

		#scp/rcp login info
		scp => [],

		#user validation specifications
		max_file_size => undef,
		min_file_size => 1,
		accept_file_types => [],
		reject_file_types => [],
		require_image => undef,
		max_width => undef,
		max_height => undef,
		min_width => 1,
		min_height => 1,
		max_number_of_files => undef,
		
		#not to be used by users
		output => undef,
		handle => undef,
		tmp_filename => undef,
		fh => undef,
		error => undef,
		upload => undef,
		file_type => undef,
		is_image => undef,
		image_magick => undef,
		width => undef,
		height => undef,
		num_files_in_dir => undef,
		user_error => undef,
    };

    return bless $self, $class;
}

sub handle_request
{
    my( $ul ) = @_;

	my $method = $r->method;

	if($method eq 'GET')
    {
        $s->log_error( "GET Upload" ) if $DEBUG;
	}
	elsif($method eq 'PATCH' or $method eq 'POST' or $method eq 'PUT')
    {
        $ul->handle_post;
	}
	elsif($method eq 'DELETE')
    {
        $s->log_error( "DELETE Upload" ) if $DEBUG;
		if( $ul->should_delete )
        {
			$ul->_delete;
		}
	}
	else
    {
        $r->status(405);
	}

    $ul->_generate_output
}

sub handle_post
{
	my( $ul ) = @_;

	if( $ul->_prepare_file_attrs and $ul->_validate_file)
    {
		if($ul->is_image)
        {
			$ul->_create_thumbnail;
			$ul->_create_tmp_image;
		}
		$ul->_save;
	}

	#delete temporary files
	if($ul->is_image)
    {
		unlink( $ul->{tmp_thumb_path}, $ul->{tmp_file_path} );
	}
}

sub upload_dir { 
	my $self = shift;

  if (@_) {
 		$self->{upload_dir} = shift;
  }

	return $self->{upload_dir};
}

sub thumbnail_upload_dir { 
	my $self = shift;
	     
  if (@_) {
	  $self->{thumbnail_upload_dir} = shift;
  }
	
	#set upload_dir to directory of this script if not provided
	if(!(defined $self->{thumbnail_upload_dir})) { 
			$self->{thumbnail_upload_dir} = $self->upload_dir;
	}

	return $self->{thumbnail_upload_dir};
}

sub upload_url_base { 
	my $self = shift;
	     
  if (@_) {
  	$self->{upload_url_base} = shift;
  }
	
	if(!(defined $self->{upload_url_base})) { 
		$self->{upload_url_base} = $self->_url_base . $self->relative_url_path;
	}

	return $self->{upload_url_base};
}

sub _url_base { 
	my $self = shift;
	my $url;
		
	if($self->relative_to_host) {
		$url = $self->{uri}->scheme . '://' . $self->{uri}->host;
	}
	else { 
		$url = $self->script_url;
		$url =~ s/(.*)\/.*/$1/;
	}

	return $url;	
}

sub thumbnail_url_base { 
	my $self = shift;
	     
	if (@_) {
 	 $self->{thumbnail_url_base} = shift;
  }
	
	if(!(defined $self->{thumbnail_url_base})) { 
		if(defined $self->thumbnail_relative_url_path) { 
			$self->{thumbnail_url_base} = $self->_url_base . $self->thumbnail_relative_url_path;
		}
		else {
			$self->{thumbnail_url_base} = $self->upload_url_base;
		}
	}

	return $self->{thumbnail_url_base};
}


sub relative_url_path { 
	my $self = shift;

	if(@_) { 
		$self->{relative_url_path} = shift;
	}

	return $self->{relative_url_path};
}

sub thumbnail_relative_url_path { 
	my $self = shift;

	if(@_) { 
		$self->{thumbnail_relative_url_path} = shift;
	}

	return $self->{thumbnail_relative_url_path};
}

sub relative_to_host { 
	my $self = shift;

	if(@_) { 
		$self->{relative_to_host} = shift;
	}

	return $self->{relative_to_host};
}



sub field_name { 
	my $self = shift;
	     
    if (@_) {
        $self->{field_name} = shift;
    }
	
	return $self->{field_name};
}

sub ctx { 
	my $self = shift;
	     
    if (@_) {
        $self->{ctx} = shift;
    }
	
	return $self->{ctx};
}

sub cgi { 
	my $self = shift;
	     
    if (@_) {
	    $self->{cgi} = shift;
    }
	$self->{cgi} = CGI->new unless defined $self->{cgi};
	
	return $self->{cgi};
}

sub should_delete { 
	my $self = shift;
	     
    if (@_) {
        $self->{should_delete} = shift;
    }
	
	return $self->{should_delete};
}

sub scp { 
	my $self = shift;
	     
    if (@_) {
        $self->{scp} = shift;
    }
	
	return $self->{scp};
}

sub max_file_size { 
	my $self = shift;
	     
    if (@_) {
        $self->{max_file_size} = shift;
    }
	
	return $self->{max_file_size};
}

sub min_file_size { 
	my $self = shift;
	     
    if (@_) {
        $self->{min_file_size} = shift;
    }
	
	return $self->{min_file_size};
}

sub accept_file_types { 
	my $self = shift;
	     
  if (@_) {
	my $a_ref = shift;
	die "accept_file_types must be an array ref" unless UNIVERSAL::isa($a_ref,'ARRAY');
   	$self->{accept_file_types} = $a_ref;
  }

	if(scalar(@{$self->{accept_file_types}}) == 0 and $self->require_image) { 
		$self->{accept_file_types} = ['image/jpeg','image/jpg','image/png','image/gif'];
	}
	
	return $self->{accept_file_types};
}

sub reject_file_types { 
	my $self = shift;
	     
	if (@_) {
		my $a_ref = shift;
		die "reject_file_types must be an array ref" unless UNIVERSAL::isa($a_ref,'ARRAY');
		$self->{reject_file_types} = $a_ref;
	}

	return $self->{reject_file_types};
}

sub require_image { 
	my $self = shift;
	     
  if (@_) {
   	$self->{require_image} = shift;
  }
	
	return $self->{require_image};
}

sub delete_params { 
	my $self = shift;
	     
    if (@_) {
		my $a_ref = shift;
		die "delete_params must be an array ref" unless UNIVERSAL::isa($a_ref,'ARRAY');
        $self->{delete_params} = $a_ref;
    }
	
	return $self->{delete_params};
}

sub delete_url { 
	my $self = shift;

	if(@_) { 
		$self->{delete_url} = shift;
	}

	return $self->{delete_url} || '';
}

sub thumbnail_width { 
	my $self = shift;
	     
    if (@_) {
        $self->{thumbnail_width} = shift;
    }
	
	return $self->{thumbnail_width};
}

sub thumbnail_height { 
	my $self = shift;
	     
    if (@_) {
        $self->{thumbnail_height} = shift;
    }
	
	return $self->{thumbnail_height};
}

sub thumbnail_quality { 
	my $self = shift;
	     
    if (@_) {
        $self->{thumbnail_quality} = shift;
    }
	
	return $self->{thumbnail_quality};
}

sub thumbnail_format { 
	my $self = shift;
	     
    if (@_) {
        $self->{thumbnail_format} = shift;
    }
	
	return $self->{thumbnail_format};
}

sub thumbnail_density { 
	my $self = shift;
	     
    if (@_) {
        $self->{thumbnail_density} = shift;
    }
	
	return $self->{thumbnail_density};
}

sub thumbnail_prefix { 
	my $self = shift;
	     
    if (@_) {
        $self->{thumbnail_prefix} = shift;
    }
	
	return $self->{thumbnail_prefix};
}

sub thumbnail_postfix { 
	my $self = shift;
	     
    if (@_) {
        $self->{thumbnail_postfix} = shift;
    }
	
	return $self->{thumbnail_postfix};
}

sub thumbnail_final_width { 
	my $self = shift;

	if(@_) { 
		$self->{thumbnail_final_width} = shift;
	}

	return $self->{thumbnail_final_width};
}

sub thumbnail_final_height { 
	my $self = shift;

	if(@_) { 
		$self->{thumbnail_final_height} = shift;
	}

	return $self->{thumbnail_final_height};
}

sub quality { 
	my $self = shift;
	     
    if (@_) {
        $self->{quality} = shift;
    }
	
	return $self->{quality};
}

sub format { 
	my $self = shift;
	     
    if (@_) {
        $self->{format} = shift;
    }
	
	return $self->{format};
}

sub final_width { 
	my $self = shift;

	if(@_) { 
		$self->{final_width} = shift;
	}

	return $self->{final_width};
}

sub final_height { 
	my $self = shift;

	if(@_) { 
		$self->{final_height} = shift;
	}

	return $self->{final_height};
}

sub max_width { 
	my $self = shift;
	     
    if (@_) {
        $self->{max_width} = shift;
    }
	
	return $self->{max_width};
}

sub max_height { 
	my $self = shift;
	     
    if (@_) {
        $self->{max_height} = shift;
    }
	
	return $self->{max_height};
}

sub min_width { 
	my $self = shift;
	     
    if (@_) {
        $self->{min_width} = shift;
    }
	
	return $self->{min_width};
}

sub min_height { 
	my $self = shift;
	     
    if (@_) {
        $self->{min_height} = shift;
    }
	
	return $self->{min_height};
}

sub max_number_of_files { 
	my $self = shift;
	     
    if (@_) {
        $self->{max_number_of_files} = shift;
    }
	
	return $self->{max_number_of_files};
}

sub filename { 
	my $self = shift;
	     
    if (@_) {
        $self->{filename} = shift;
    }
	
	return $self->{filename};
}

sub absolute_filename { 
	my $self = shift;
	     
    if (@_) {
        $self->{absolute_filename} = shift;
    }
	
	return $self->{absolute_filename};
}

sub thumbnail_filename { 
	my $self = shift;
	     
    if (@_) {
        $self->{thumbnail_filename} = shift;
    }
	
	return $self->{thumbnail_filename};
}

sub absolute_thumbnail_filename { 
	my $self = shift;
	     
    if (@_) {
        $self->{absolute_thumbnail_filename} = shift;
    }
	
	return $self->{absolute_thumbnail_filename};
}

sub client_filename { 
	my $self = shift;
	     
    if (@_) {
        $self->{client_filename} = shift;
    }
	
	return $self->{client_filename};
}

sub show_client_filename { 
	my $self = shift;
	     
    if (@_) {
        $self->{show_client_filename} = shift;
    }
	
	return $self->{show_client_filename};
}

sub use_client_filename { 
	my $self = shift;
	     
    if (@_) {
        $self->{use_client_filename} = shift;
    }
	
	return $self->{use_client_filename};
}

sub filename_salt { 
	my $self = shift;
	     
    if (@_) {
        $self->{filename_salt} = shift;
    }
	
	return $self->{filename_salt};
}

sub tmp_dir { 
	my $self = shift;
	     
    if (@_) {
        $self->{tmp_dir} = shift;
    }
	
	return $self->{tmp_dir};
}

sub script_url { 
	my $self = shift;
	     
    if (@_) {
        $self->{script_url} = shift;
    }
	
	if(!(defined $self->{script_url})) {
		if(defined $self->ctx) { 
			$self->{script_url} = $self->ctx->request->uri;
		}
		else { 
			$self->{script_url} = $ENV{SCRIPT_URI};
		}
	}

	return $self->{script_url};
}

sub data { 
	my $self = shift;

	if(@_) { 
		$self->{data} = shift;
	}

	return $self->{data};
}

#GETTERS 
sub output { shift->{output} }
sub url { shift->{url} }
sub thumbnail_url { shift->{thumbnail_url} }
sub is_image { shift->{is_image} }
sub size { shift->{file_size} }

#sub _no_ext { 
#	my $self = shift;
#	$self->filename($_->{filename});
#	my ($no_ext) = $self->filename =~ qr/(.*)\.(.*)/;
#	return $no_ext;
#}

#PRE/POST METHODS
sub pre_delete { 
	my $self = shift;
	     
    if (@_) {
        $self->{pre_delete} = shift;
    }
	
	return $self->{pre_delete};
}

sub post_delete { 
	my $self = shift;
	     
    if (@_) {
        $self->{post_delete} = shift;
    }
	
	return $self->{post_delete};
}

sub pre_post { 
	my $self = shift;
	     
    if (@_) {
        $self->{pre_post} = shift;
    }
	
	return $self->{pre_post};
}

sub post_post { 
	my $self = shift;
	     
    if (@_) {
        $self->{post_post} = shift;
    }
	
	return $self->{post_post};
}

sub pre_get { 
	my $self = shift;
	     
    if (@_) {
        $self->{pre_get} = shift;
    }
	
	return $self->{pre_get};
}

sub post_get { 
	my $self = shift;
	     
    if (@_) {
        $self->{post_get} = shift;
    }
	
	return $self->{post_get};
}

sub _generate_output { 
	my $self = shift;
  	
	my $method = $self->_get_request_method;
	my $obj;

	if($method eq 'POST') {
		my %hash;
		unless($self->{user_error}) {
			$hash{'url'} = $self->url;
			$hash{'thumbnail_url'} = $self->thumbnail_url;
			$hash{'delete_url'} = $self->_delete_url;
			$hash{'delete_type'} = 'DELETE';
			$hash{error} = $self->_generate_error;
		}
		else { 
			$self->_prepare_file_basics;
			$hash{error} = $self->{user_error};
		}

        my $cfn = $self->client_filename;
        my $dcfn = "";
        while( length $cfn )
        {
            $dcfn .= decode("UTF-8", $cfn, Encode::FB_QUIET);
            $dcfn .= substr($cfn, 0, 1, "") if length $cfn;
        }
		$hash{'name'} = $dcfn;

		$hash{'size'} = $self->{file_size};
		$obj->{files} = [\%hash];
	}
	elsif($method eq 'DELETE') { 
		unless($self->{user_error}) {
			$obj->{$self->_get_param('filename')} = JSON::true;
		}
		else { 
			$obj->{error} = $self->{user_error};
		}
	}

	my $json = JSON::XS->new->ascii->pretty->allow_nonref;
	$self->{output} = $json->encode($obj);
}

sub _delete { 
	my $self = shift;

	my $filename = $self->_get_param('filename');
	my $thumbnail_filename = $self->_get_param('thumbnail_filename');
	my $image_yn = $self->_get_param('image');

	if(@{$self->scp}) { 
		for(@{$self->scp}) { 
			
			my $ssh2 = $self->_auth_user($_);
			$_->{thumbnail_upload_dir} = $_->{upload_dir} if $_->{thumbnail_upload_dir} eq '';

			my $sftp = $ssh2->sftp;
			$sftp->unlink($_->{upload_dir} . '/' . $filename);
			$sftp->unlink($_->{thumbnail_upload_dir} . '/' . $thumbnail_filename) if $image_yn eq 'y';
		}		
	}
	else { 
#		my $no_ext = $self->_no_ext;
		unlink $self->upload_dir . '/' . $filename;
		unlink($self->thumbnail_upload_dir . '/' . $thumbnail_filename) if $image_yn eq 'y';
	}

	$self->_generate_output;
}

sub _get_param { 
	my $self = shift;
	my ($param) = @_;

	if(defined $self->ctx) { 
		return $self->ctx->req->params->{$param};
	}
	else { 
		return $self->cgi->param($param);
	}
}

sub _delete_url { 
	my $self = shift;
	return if $self->delete_url ne '';
	my ($delete_params) = @_;

	my $url = $self->script_url;
	my $uri = $self->{uri}->clone;

	my $image_yn = $self->is_image ? 'y' : 'n';

	unless(defined $delete_params and scalar(@$delete_params)) { 
		$delete_params = [];
	}

	push @$delete_params, @{$self->delete_params} if @{$self->delete_params};
	push @$delete_params, ('filename',$self->filename,'image',$image_yn);
	push @$delete_params, ('thumbnail_filename',$self->thumbnail_filename) if $self->is_image;

	$uri->query_form($delete_params);

	$self->delete_url($uri->as_string);

	return $self->delete_url;
}

sub _script_url { 
	my $self = shift;

	if(defined $self->ctx) { 
		return $self->ctx->request->uri;	
	}
	else { 
		return $ENV{'SCRIPT_URI'};
	}
}

sub _prepare_file_attrs { 
	my $self = shift;

	#ORDER MATTERS
	return unless $self->_prepare_file_basics;
	$self->_set_tmp_filename;
	$self->_set_file_type;
	$self->_set_is_image;
	$self->_set_filename;
	$self->_set_absolute_filenames;
	$self->_set_image_magick;
	$self->_set_width;
	$self->_set_height;
	$self->_set_num_files_in_dir;
	$self->_set_uri;
	$self->_set_urls;

	return 1;
}

sub _prepare_file_basics { 
	my ($self) = @_;

	return undef unless $self->_set_upload_obj;
	$self->_set_fh;
	$self->_set_file_size;
	$self->_set_client_filename;

	return 1;
}

sub _set_urls { 
	my $self = shift;

	if($self->is_image) { 
		$self->{thumbnail_url} = $self->thumbnail_url_base . '/' . $self->thumbnail_filename;
	}
	$self->{url} = $self->upload_url_base . '/' . $self->filename;
}

sub _set_uri { 
	my $self = shift;
	#if catalyst, use URI already made?
	if(defined $self->ctx) {
		$self->{uri} = $self->ctx->req->uri;
	}
	else {
		$self->{uri} = URI->new($self->script_url);
	}
}

sub _generate_error { 
	my $self = shift;
	return undef unless defined $self->{error} and @{$self->{error}};

	my $restrictions = join ',', @{$self->{error}->[1]};
	return $errors{$self->{error}->[0]} . " Restriction: $restrictions Provided: " . $self->{error}->[2];
}

sub _validate_file { 
	my $self = shift;
	return undef unless
	$self->_validate_max_file_size and
	$self->_validate_min_file_size and
	$self->_validate_accept_file_types and
	$self->_validate_reject_file_types and
	$self->_validate_max_width and
	$self->_validate_min_width and
	$self->_validate_max_height and
	$self->_validate_min_height and
	$self->_validate_max_number_of_files;

	return 1;
}

sub _save { 
	my $self = shift;
	
	if(@{$self->scp}) { 
		$self->_save_scp;	
	}
	else { 
		$self->_save_local;
	}
}

sub _save_scp { 
	my $self = shift;

	for(@{$self->scp}) { 
		die "Must provide a host to scp" if $_->{host} eq '';

		$_->{thumbnail_upload_dir} = $_->{upload_dir} if $_->{thumbnail_upload_dir} eq '';

		my $path = $_->{upload_dir} . '/' . $self->filename;
		my $thumb_path = $_->{thumbnail_upload_dir} . '/' . $self->thumbnail_filename;

		if(($_->{user} ne '' and $_->{public_key} ne '' and $_->{private_key} ne '') or ($_->{user} ne '' and $_->{password} ne '')) { 
			my $ssh2 = $self->_auth_user($_);

			#if it is an image, scp both file and thumbnail
			if($self->is_image) { 
				$ssh2->scp_put($self->{tmp_file_path}, $path);
				$ssh2->scp_put($self->{tmp_thumb_path}, $thumb_path);
			}
			else { 
				$ssh2->scp_put($self->{tmp_filename}, $path);
			}

			$ssh2->disconnect;
		}
		else { 
			die "Must provide a user and password or user and identity file for connecting to host";
		}
		
	}
}

sub _auth_user { 
	my $self = shift;
	my ($auth) = @_;

	my $ssh2 = Net::SSH2->new;

	$ssh2->connect($auth->{host}) or die $!;

	#authenticate
	if($auth->{user} ne '' and $auth->{public_key} ne '' and $auth->{private_key} ne '') { 
		$ssh2->auth_publickey($auth->{user},$auth->{public_key},$auth->{private_key});	
	}
	else { 
		$ssh2->auth_password($auth->{user},$auth->{password});
	}

	unless($ssh2->auth_ok) { 
		die "error authenticating with remote server";
	}

	die "upload directory must be provided with scp hash" if $auth->{upload_dir} eq '';

	return $ssh2;
}

sub _save_local { 
	my $self = shift;

	#if image
	if($self->is_image) { 
		rename $self->{tmp_file_path}, $self->absolute_filename;
		rename $self->{tmp_thumb_path}, $self->absolute_thumbnail_filename;
	}
	#if non-image with catalyst
	elsif(defined $self->ctx) { 
		$self->{upload}->link_to($self->absolute_filename);
	}
	#if non-image with regular CGI perl
	else { 
		my $io_handle = $self->{fh}->handle;

		my $buffer;
		open (OUTFILE,'>', $self->absolute_filename);
		while (my $bytesread = $io_handle->read($buffer,1024)) {
			print OUTFILE $buffer;
		}

		close OUTFILE;
	}
}

sub _validate_max_file_size { 
	my $self = shift;
	return 1 unless $self->max_file_size;
	
	if($self->{file_size} > $self->max_file_size) { 
		$self->{error} = ['_validate_max_file_size',[$self->max_file_size],$self->{file_size}];
		return undef;
	}
	else { 
		return 1;
	}
}

sub _validate_min_file_size { 
	my $self = shift;
	return 1 unless $self->min_file_size;
	
	if($self->{file_size} < $self->min_file_size) { 
		$self->{error} = ['_validate_min_file_size',[$self->min_file_size],$self->{file_size}];
		return undef;
	}
	else { 
		return 1;
	}
}

sub _validate_accept_file_types { 
	my $self = shift;

	#if accept_file_types is empty, we except all types
	#so return true
	return 1 unless @{$self->accept_file_types};

	if(grep { $_ eq $self->{file_type} } @{$self->{accept_file_types}}) { 
		return 1;
	}
	else { 
		my $types = join ",", @{$self->accept_file_types};
		$self->{error} = ['_validate_accept_file_types',[$types],$self->{file_type}];
		return undef;	
	}
}

sub _validate_reject_file_types { 
	my $self = shift;

	#if reject_file_types is empty, we except all types
	#so return true
	return 1 unless @{$self->reject_file_types};

	unless(grep { $_ eq $self->{file_type} } @{$self->{reject_file_types}}) { 
		return 1;
	}
	else { 
		my $types = join ",", @{$self->reject_file_types};
		$self->{error} = ['_validate_reject_file_types',[$types],$self->{file_type}];
		return undef;	
	}
}

sub _validate_max_width { 
	my $self = shift;
	return 1 unless $self->is_image;

	#if set to undef, there's no max_width
	return 1 unless $self->max_width;

	if($self->{width} > $self->max_width) { 
		$self->{error} = ['_validate_max_width',[$self->max_width],$self->{width}];
		return undef;
	}
	else { 
		return 1;
	}	
}

sub _validate_min_width { 
	my $self = shift;
	return 1 unless $self->is_image;

	#if set to undef, there's no min_width
	return 1 unless $self->min_width;

	if($self->{width} < $self->min_width) { 
		$self->{error} = ['_validate_min_width',[$self->min_width],$self->{width}];
		return undef;
	}
	else { 
		return 1;
	}	
}

sub _validate_max_height { 
	my $self = shift;
	return 1 unless $self->is_image;

	#if set to undef, there's no max_height
	return 1 unless $self->max_height;

	if($self->{height} > $self->max_height) { 
		$self->{error} = ['_validate_max_height',[$self->max_height],$self->{height}];
		return undef;
	}
	else { 
		return 1;
	}	
}

sub _validate_min_height { 
	my $self = shift;
	return 1 unless $self->is_image;

	#if set to undef, there's no max_height
	return 1 unless $self->min_height;

	if($self->{height} < $self->min_height) { 
		$self->{error} = ['_validate_min_height',[$self->min_height],$self->{height}];
		return undef;
	}
	else { 
		return 1;
	}	
}

sub _validate_max_number_of_files { 
	my $self = shift;
	return 1 unless $self->max_number_of_files;

	if($self->{num_files_in_dir} > $self->max_number_of_files) { 
		$self->{error} = ['_validate_max_number_of_files',[$self->max_number_of_files],$self->{num_files_in_dir}];
		return undef;	
	}
	else { 
		return 1;
	}
}

sub _set_file_size { 
	my $self = shift;

	if(defined $self->ctx) { 
		$self->{file_size} = $self->{upload}->size;
	}
	else { 
		$self->{file_size} = -s $self->{upload};
	}

	return $self->{file_size};
}

sub _set_client_filename { 
	my $self = shift;
	return if defined $self->client_filename;

	if(defined $self->ctx) { 
		$self->client_filename($self->{upload}->filename);
	}
	else { 
		$self->client_filename($self->cgi->param($self->field_name));
	}

	return $self->client_filename;
}

sub _set_filename { 
	my $self = shift;
	return if defined $self->filename;

	if($self->use_client_filename) { 
		$self->filename($self->client_filename);
	}
	else { 
		my $filename = Data::GUID->new->as_string . $self->filename_salt;
		$self->thumbnail_filename($self->thumbnail_prefix . $filename . $self->thumbnail_postfix . '.' . $self->thumbnail_format) unless $self->thumbnail_filename;

		if($self->is_image) { 
			$filename .= '.' . $self->format;
		}
		else { 
			#add extension if present
			if($self->client_filename =~ qr/.*\.(.*)/) {
				$filename .= '.' . $1;
			}
		}
		$self->filename($filename) unless $self->filename;
	}

	return $self->filename;
}

sub _set_absolute_filenames { 
	my $self = shift;

	$self->absolute_filename($self->upload_dir . '/' . $self->filename) unless $self->absolute_filename;
	$self->absolute_thumbnail_filename($self->thumbnail_upload_dir . '/' . $self->thumbnail_filename) unless $self->absolute_thumbnail_filename;
}

sub _set_file_type { 
	my $self = shift;

	if(defined $self->ctx) { 
		$self->{file_type} = $self->{upload}->type;
	}
	else { 
		$self->{file_type} = $self->cgi->uploadInfo($self->client_filename)->{'Content-Type'};
	}

	return $self->{file_type};
}

sub _set_is_image { 
	my $self = shift;

	if($self->{file_type} eq 'image/jpeg' or $self->{file_type} eq 'image/jpg' or $self->{file_type} eq 'image/png' or $self->{file_type} eq 'image/gif') { 
		$self->{is_image} = 1;
	}
	else { 
		$self->{is_image} = 0;
	}

	return $self->is_image;
}

sub _set_image_magick { 
	my $self = shift;
	return unless $self->is_image;

	#if used in persistent setting, don't recreate object
	$self->{image_magick} = Image::Magick->new unless defined $self->{image_magick};

	$self->{image_magick}->Read(file => $self->{fh});

	return $self->{image_magick};
}

sub _set_width { 
	my $self = shift;
	return unless $self->is_image;

	$self->{width} = $self->{image_magick}->Get('width');
}

sub _set_height { 
	my $self = shift;
	return unless $self->is_image;

	$self->{height} = $self->{image_magick}->Get('height');
}

sub _set_tmp_filename { 
	my $self = shift;

	my $tmp_filename;
	if(defined $self->ctx) { 
		$self->{tmp_filename} = $self->{upload}->tempname;	
	}
	else { 
		$self->{tmp_filename} = $self->cgi->tmpFileName($self->client_filename);
	}
}

sub _set_upload_obj { 
	my $self = shift;

	if(defined $self->ctx) { 
		$self->{upload} = $self->ctx->request->upload($self->field_name);
	}
	else { 
		$self->{upload} = $self->cgi->upload($self->field_name);
	}

	return defined $self->{upload};
}

sub _set_fh { 
	my $self = shift;

	if(defined $self->ctx) { 
		$self->{fh} = $self->{upload}->fh;
	}
	else { 
		$self->{fh} = $self->{upload};
	}

	return $self->{fh};
}

sub _set_num_files_in_dir { 
	my $self = shift;
	return unless $self->max_number_of_files;

	#DO SCP VERSION
	if(@{$self->{scp}}) { 
		my $max = 0;
		for(@{$self->{scp}}) {
			my $ssh2 = $self->_auth_user($_);
			my $chan = $ssh2->channel();
			$chan->exec('ls -rt ' . $_->{upload_dir} . ' | wc -l');
			my $buffer;
			$chan->read($buffer,1024);
			($self->{num_files_in_dir}) = $buffer =~ qr/(\d+)/;
			$max = $self->{num_files_in_dir} if $self->{num_files_in_dir} > $max;
		}
		
		#set to maximum of hosts because we know if one's over that's too many
		$self->{num_files_in_dir} = $max;
	}
	else {
		my $dir = $self->upload_dir;
		my @files = <$dir/*>;
	   	$self->{num_files_in_dir} = @files;
	}

	return $self->{num_files_in_dir};
}

sub _get_request_method { 
	my $self = shift;
	
	my $method = '';
	if(defined $self->ctx) { 
		$method = $self->ctx->req->method;
	}
	else { 
		$method = $self->cgi->request_method;
	}

	return $method;
}

sub _set_status { 
	my $self = shift;
	my ($response) = @_;

	if(defined $self->ctx) { 
		$self->ctx->response->status($response);	
	}
	else { 
		print $self->cgi->header(-status=>$response);	
	}
}

sub _set_header { 
	my $self = shift;
	my ($key,$val) = @_;

	if(defined $self->ctx) { 
		$self->ctx->response->header($key => $val);	
	}
	else { 
		print $self->cgi->header($key,$val);
	}
}

sub _create_thumbnail {
  my $self = shift;
   
  my $im = $self->{image_magick}->Clone;
   
	#thumb is added at beginning of tmp_thumb_path as to not clash with the original image file path
  my $output  = $self->{tmp_thumb_path} = $self->tmp_dir . '/thumb_' . $self->thumbnail_filename;
  my $width   = $self->thumbnail_width;
  my $height  = $self->thumbnail_height;
 
  my $density = $self->thumbnail_density || $width . "x" . $height;
  my $quality = $self->thumbnail_quality;
  my $format  = $self->thumbnail_format;
 
  # source image dimensions  
  my ($o_width, $o_height) = $im->Get('width','height');
   
  # calculate image dimensions required to fit onto thumbnail
  my ($t_width, $t_height, $ratio);
  # wider than tall (seems to work...) needs testing
  if( $o_width > $o_height ){
    $ratio = $o_width / $o_height;
    $t_width = $width;    
    $t_height = $width / $ratio;
 
    # still won't fit, find the smallest size.
    while($t_height > $height){
      $t_height -= $ratio;
      $t_width -= 1;
    }
  }
  # taller than wide
  elsif( $o_height > $o_width ){
    $ratio = $o_height / $o_width;  
    $t_height = $height;
    $t_width = $height / $ratio;
 
    # still won't fit, find the smallest size.
    while($t_width > $width){
      $t_width -= $ratio;
      $t_height -= 1;
    }
  }
  # square (fixed suggested by Philip Munt phil@savvyshopper.net.au)
  elsif( $o_width == $o_height){
    $ratio = 1;
    $t_height = $width;
    $t_width  = $width;
     while (($t_width > $width) or ($t_height > $height)){
       $t_width -= 1;
       $t_height -= 1;
     }
  }

  # Create thumbnail
  if( defined $im ){
    $im->Resize( width => $t_width, height => $t_height );
    $im->Set( quality => $quality );
    $im->Set( density => $density );
     
	$self->final_width($t_width);
	$self->final_height($t_height);

	$im->Write("$format:$output");
  }
}

sub _create_tmp_image { 
  my $self = shift;
  my $im = $self->{image_magick};
   
	#main_ is added as to not clash with thumbnail tmp path if thumbnail_prefix = '' and they have the same name
  my $output  = $self->{tmp_file_path} = $self->tmp_dir . '/main_' . $self->filename;
  my $quality = $self->thumbnail_quality;
  my $format  = $self->thumbnail_format;

  if( defined $im ){
    $im->Set( quality => $quality );
     
	$im->Write("$format:$output");

	$self->final_width($im->Get('width'));
	$self->final_height($im->Get('height'));
  }
}



#sub old_handler
#{
#
#
#
#    # stupid jQuery::File::Upload wants to print header
#    #
#    $r->assbackwards(1);
#    #$r->content_type('text/plain');
#
#    #sleep 20;
#    #print "Content-type: text/plain\n\n";
#    #say "Hello";
#    #say $ubase;
#    #say $udir;
#    #return Apache2::Const::DONE;
#
#    #simplest implementation
#    my $j_fu = jQuery::File::Upload->new;
#    $j_fu->upload_url_base( $ubase );
#    $j_fu->script_url( $r->unparsed_uri );
#    $j_fu->upload_dir( $udir );
#    $j_fu->tmp_dir( $udir );
#
#    my $output;
#
#    $j_fu->post_post
#      (sub{
#           my $j_fu = shift;
#           $s->log_error("in post post");
#
#
##           $j_fu->{user_error} = "No no no";
#
#
#
#           my $file = $j_fu->filename;
#
#           $s->log_error( "Filename (post) ".$j_fu->filename ) if $DEBUG;
#           chmod 0660, "$udir/$file";
#           chmod 0660, "$udir/thumb_$file" if -r "$udir/thumb_$file";
#
#           return;
#
#
#           my $cfn = $j_fu->client_filename;
#
#           my $dcfn = "";
#           while( length $cfn )
#           {
#               $dcfn .= decode("UTF-8", $cfn, Encode::FB_QUIET);
#               $dcfn .= substr($cfn, 0, 1, "") if length $cfn;
#           }
#
#           $j_fu->client_filename($dcfn);
#
##           $j_fu->_generate_output;
##           $output = $j_fu->output;
##           $s->log_error("output:\n$output");
#
#           return "Yes yes yes";
#       });
#
#
#    $j_fu->handle_request(1);
#
#
##    $j_fu->_generate_output;
##    my $output = $j_fu->output;
##    $s->log_error("output:\n$output");
##    $r->print( $output );
#    #$j_fu->print_response;
#
#    $s->log_error("$$: Done") if $DEBUG;
#
#    return Apache2::Const::DONE;
#}
#print $j_fu->output//'';

##############################################################################

sub validate_utf8
{
    if( utf8::is_utf8(${$_[0]}) )
    {
	if( utf8::valid(${$_[0]}) )
	{
	    if( ${$_[0]} =~ /Ã/ )
	    {
		return "DOUBLE-ENCODED utf8";
	    }
	    else
	    {
		return "valid utf8";
	    }
	}
	else
	{
	    return "as INVALID utf8";
	}
    }
    else
    {
	if( ${$_[0]} =~ /Ã/ )
	{
	    return "UNMARKED utf8";
	}
	else
	{
	    return "NOT Marked as utf8";
	}
    }
}

##############################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>, L<Apache>

=cut
