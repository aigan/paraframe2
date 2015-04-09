#############################################

package Para::Frame::Renderer::Test_AJAX;

use base 'Para::Frame::Renderer::Custom';
use Test::More;
use JSON; # to_json from_json

sub render_output
{
    my( $rend ) = @_;

    my $file = $rend->url_path;
    my $req =  $rend->req;
    my $q = $req->q;
    my $u = $req->user;
    my $params = {};

    foreach my $key ( $q->param )
    {
        $params->{$key} = [];
        foreach my $val ( $q->param($key ) )
        {
            push @{$params->{$key}}, $val;
        }
    }

    my $out = to_json( {
                        path => $file,
                        params => $params,
                        user => $u->{username},
                       } );

    return \ $out;
}


1;
