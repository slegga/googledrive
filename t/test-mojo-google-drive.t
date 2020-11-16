#!/usr/bin/env perl
use lib 'lib';
use Mojo::GoogleDrive::Mirror;
use Data::Printer;
use Mojo::File 'path';
use Test::More;
use Test::UserAgent;

# TEST UPLOAD

`rm -r t/local/*`;
`rm -r t/remote/*`;
`echo local-file >t/local/file.txt`;
`echo remote-file >t/remote/file.txt`;


my $o = Mojo::GoogleDrive::Mirror->new(local_root=>"t/local/", remote_root=>'/', ua=>Test::UserAgent->new(real_remote_root=>'t/remote/'));
my $f= $o->file('file.txt');
my $metadata = $f->get_metadata;
say STDERR "\n";



#p $metadata;
like ($metadata->{id},qr{\w},'id is set');
#my $list = $o->file('/');
#p $list;
#is (@$list,1,'file flound');
done_testing;
