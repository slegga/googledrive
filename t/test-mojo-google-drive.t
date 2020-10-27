#!/usr/bin/env perl
use lib 'lib';
use Mojo::GoogleDrive::Mirror;
use Data::Printer;
use Mojo::File 'path';
use Test::More;
use Test::UserAgent;
my $o = Mojo::GoogleDrive::Mirror->new(local_root=>"$ENV{HOME}/testgd", remote_root=>'/test/', ua=>Test::UserAgent->new());
my $metadata = $o->file('testfil.txt')->upload->metadata;
like ($metadata->{id},qr{\w},'id is set');
ok(1,'dummy');
done_testing;