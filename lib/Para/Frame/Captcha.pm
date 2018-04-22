package Para::Frame::Captcha;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2018 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Captcha - Frontend to Captcha::reCAPTCHA

=cut

use 5.012;
use warnings;

use Captcha::reCAPTCHA;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::L10N qw( loc );
#use Para::Frame::Time qw( now );


##############################################################################

=head2 new

=cut

sub new
{
	my( $this, $site ) = @_;
	my $class = ref($this) || $this;

	my $req = $Para::Frame::REQ;
	$site ||= $req->site;


	my $c = $req->{'captcha'} ||= bless
	{
	 site => $site,
	}, $class;

	return $c;
}


##############################################################################

=head2 as_html

  $c->as_html

  $c->as_html( \%options )

For options, see
http://recaptcha.net/apidocs/captcha/client.html#look-n-feel

Default theme is set to C<clean>

=cut

sub as_html
{
	my( $c, $opt ) = @_;

	my $site = $c->{'site'} or die "No site given";

	my $public_key = $site->{'recaptcha_key_public'} or
		die "No recaptcha_key_public found for site ". $site->desig;

	my $co = Captcha::reCAPTCHA->new;

	my $err = $c->{'error'};

	$opt ||= {};
	#$opt->{'theme'} ||= 'clean';

	#return $co->get_html_v2( $public_key, $err, 0, $opt );
	return $co->get_html_v2( $public_key, $opt );
}


##############################################################################

=head2 is_valid

=cut

sub is_valid
{
	my( $c ) = @_;

	my $site = $c->{'site'} or die "No site given";

	my $private_key = $site->{'recaptcha_key_private'} or
		die "No recaptcha_key_private found for site ". $site->desig;

	$c->{'error'} = 'no-response';

	my $q = $Para::Frame::REQ->q;
	my $chal = $q->param( 'recaptcha_challenge_field' ) or
		return 0;
	my $resp = $q->param( 'recaptcha_response_field' ) or
		return 0;

	my $co = Captcha::reCAPTCHA->new;

	my $result = $co->check_answer(
																 $private_key,
																 $ENV{'REMOTE_ADDR'},
																 $resp,
																);

	if ( $result->{'is_valid'} )
	{
		return 1;
	}
	else
	{
		$c->{'error'} = $result->{'error'};
		return 0;
	}
}


##############################################################################

=head2 active

=cut

sub active
{
	my( $c ) = @_;

	my $site = $c->{'site'} or return 0;
	$site->{'recaptcha_key_public'} or return 0;
	$site->{'recaptcha_key_private'} or return 0;

	return 1;
}


##############################################################################

=head2 error_as_text

=cut

sub error_as_text
{
	my( $c ) = @_;

	if ( my $err = $c->{'error'} )
	{
		return loc( 'recaptcha-'.$err );
	}

	return "";
}


##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut
