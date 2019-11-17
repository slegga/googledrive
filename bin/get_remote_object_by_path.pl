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

# stein@minnepinne:~/git/googledrive$ bin/get_remote_object_by_path.pl /Familie/sopp.md

my $home = path($ENV{HOME});
# requires a ~/.google-drive.yml file containing an access token,
# see documentation of Net::Google::Drive::Simple

my $google_drive = Net::Google::Drive::Simple::LocalSync->new(
    remote_root => path('/'),
    local_root  => $home->child('googledrive'),
    conflict_resolution => 'keep_remote',
);

my ($file_id,$parent) =  $google_drive->path_resolveu($ARGV[0]);
say $file_id;
say Dumper $google_drive->net_google_drive_simple->file_metadata($file_id);
#$google_docs->mirror();