#!/usr/bin/env perl

die "Deprecated. Use mojo-googledrive instead.";

use lib '.';
use Mojo::Base -strict;
use FindBin;
use Mojo::File 'path';
use Data::Printer;
use Data::Dumper;
use utf8;
use open qw(:std :utf8);
use lib "$FindBin::Bin/../lib";
use Net::Google::Drive::Simple::LocalSync;
#use Net::Google::Drive;


my $home = path($ENV{HOME});
# requires a ~/.google-drive.yml file containing an access token,
# see documentation of Net::Google::Drive::Simple

die "LOCALE IS WRONG: $ENV{LANG}" if ! $ENV{LANG} =~/UTF/;

my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
    remote_root => path('/'),
    local_root  => $home->child('googledrive'),
    conflict_resolution => 'keep_remote',
);

$google_docs->mirror(@ARGV);