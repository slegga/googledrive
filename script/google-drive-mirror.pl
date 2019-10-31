#!/usr/bin/env perl
use lib '.';
use Mojo::Base -strict;
use FindBin;
use Mojo::File 'path';
use Data::Printer;
use Data::Dumper;

use lib "$FindBin::Bin/../lib";
use Net::Google::Drive::Simple::LocalSync;
#use Net::Google::Drive;


my $home = path($ENV{HOME});
# requires a ~/.google-drive.yml file containing an access token,
# see documentation of Net::Google::Drive::Simple

my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
    remote_root => path('/'),
    local_root  => $home->child('googledrive'),
);

$google_docs->mirror();