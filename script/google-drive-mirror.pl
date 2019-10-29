#!/usr/bin/env perl
use Mojo::Base -strict;
use Net::Google::Drive::Simple::Mirror;
#use Net::Google::Drive;

use Mojo::File 'path';
use Data::Printer;
use Data::Dumper;

my $home = path($ENV{HOME});
# requires a ~/.google-drive.yml file containing an access token,
# see documentation of Net::Google::Drive::Simple

my $google_docs = Net::Google::Drive::Simple::Mirror->new(
    remote_root => '/',
    local_root  => $home->child('googledrive')->to_string,
    export_format => ['opendocument','html'],
    download_condition => sub {
        my ($self, $remote_file, $local_file) = @_;
	    return 0 if $remote_file->can( "exportLinks" );

        return 1 if $self->{force};

        my $date_time_parser = DateTime::Format::RFC3339->new();

        my $local_epoch =  (stat($local_file))[9];
        my $remote_epoch = $date_time_parser
                                ->parse_datetime($remote_file->modifiedDate())
                                ->epoch();
 # 		say Dumper $self->{net_google_drive_simple}->getFileMetadata('-file_id' => $remote_file->id);
        if (-f $local_file and $remote_epoch < $local_epoch ){
            return 0;
        }
        else {
            return 1;
        }
       return 0;
   }
);

$google_docs->mirror();