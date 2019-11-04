#!/usr/bin/env perl
###########################################
# google-drive-init
# Mike Schilli, 2014 (m@perlmeister.com)
###########################################
use Mojo::Base -strict;

use OAuth::Cmdline::GoogleDrive;
use OAuth::Cmdline::Mojo;

my $oauth = OAuth::Cmdline::GoogleDrive->new(
    client_id     => "1091193974752-j8csoj3ehtdotqt3ptuii6f8680crbqn.apps.googleusercontent.com",
    client_secret => "lwfQ_Z27DydGCGuYxl_Baz0R",
#    {"installed":{"client_id":"1091193974752-j8csoj3ehtdotqt3ptuii6f8680crbqn.apps.googleusercontent.com","project_id":"drive-sync-257406","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","auth_provider_x509_cert_url":"https://www.googleapis.com/oauth2/v1/certs","client_secret":"lwfQ_Z27DydGCGuYxl_Baz0R","redirect_uris":["urn:ietf:wg:oauth:2.0:oob","http://localhost"]}}",
    login_uri     => "https://accounts.google.com/o/oauth2/auth",
    token_uri     => "https://accounts.google.com/o/oauth2/token",
    scope         => "https://www.googleapis.com/auth/drive",
    access_type   => "offline",
);

my $app = OAuth::Cmdline::Mojo->new(
    oauth => $oauth,
);

$app->start( 'daemon', '-l', $oauth->local_uri );