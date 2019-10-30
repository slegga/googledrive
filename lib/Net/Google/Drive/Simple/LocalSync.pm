package Net::Google::Drive::Simple::LocalSync;
use Mojo::Base -base;
use Net::Google::Drive::Simple;
use DateTime::Format::RFC3339;
use DateTime;
use Carp;
use Mojo::File 'path';
use Digest::MD5 qw /md5_hex/;
use Encode qw /decode encode/;
use utf8;
use Data::Dumper;

our $VERSION = '0.54';

# sub new {
#     my ( $class, %options ) = @_;
#
#     croak "Local folder '$options{local_root}' not found"
#         unless -d $options{local_root};
#     $options{local_root} .= '/'
#         unless $options{local_root} =~ m{/$};
#
#     my $gd = Net::Google::Drive::Simple->new();
#     $options{remote_root} = '/' . $options{remote_root}
#         unless $options{remote_root} =~ m{^/};
#
#     # XXX To support slashes in folder names in remote_root, I would have
#     # to implement a different remote_root lookup mechanism here:
#     my ( undef, $remote_root_ID ) = $gd->children( $options{remote_root} );
#
#     my $self = {
#         remote_root_ID          => $remote_root_ID,
# #        export_format           => [ 'opendocument', 'html' ],
# #        sync_condition          => \&_should_sync,
# #        force                   => undef,                        # XXX move this to mirror()
#         net_google_drive_simple => $gd,
#         local_files => undef,
#         remote_dirs => {},
#
#         %options
#     };
#
#     bless $self, $class;
# }

has remote_root_ID =>sub {my $self = shift;
    my $gd=$self->net_google_drive_simple;
    my ( undef, $remote_root_ID ) = $gd->children( $self->remote_root );
    return $remote_root_ID};
has net_google_drive_simple => sub {Net::Google::Drive::Simple->new()};
has remote_root => sub{path('/')};
has 'local_root';
has 'local_files';
has 'remote_dirs';

sub mirror {
    my $self = shift;

    # get list of localfiles:
	my %lc = map { $_ => -d $_ } map {decode('UTF-8', $_->to_string)} path($self->local_root)->list_tree({dont_use_nlink=>1,dir=>1})->each;
    my $remote_dirs = $self->remote_dirs;
    $remote_dirs->{$self->local_root } = $self->remote_root_ID;

#	say "localfile $_" for keys %lc;
    $self->remote_dirs($remote_dirs);
     $self->local_files( \%lc);

    #may add to remove_dirs
    $self->_process_folder( $self->remote_root_ID, $self->local_root );

    #update remote_dirs;
    $remote_dirs = $self->remote_dirs;

	# uploads new files
   	for my $lf (keys %{$self->local_files}) {
        my $local_file = path($lf);
		next if $local_file->to_string =~/\/Camera Uploads\//; #do not replicate camera
		next if $local_file->to_string =~ /\/googledrive\/googledrive/; #do not replicate camera
        next if $local_file->to_string =~ /\/googledrive[^\/]/; #do not replicate camera
		my $locfol = $local_file->dirname;
		my $local_dir = $locfol->to_string;
		#$local_dir .='/' if $local_dir !~/\/$/; # secure last /

		my $did = $remote_dirs->{$local_dir};
		$did = $self->_make_path($locfol) if (!$did);
		die if ! $did;

#		say "push new file "$local_file->basename. $did . ' # '.  $local_file->dirname->to_string;
		die "No local_file" if ! "$local_file";
		if (! $did) {
			warn "No directory id";
            $remote_dirs = $self->remote_dirs;
			die Dumper $remote_dirs;
		}


		if ($self->local_files->{"$local_file"}) { #check if dir
		} else {
			say "Create new file on Google Drive ".$local_file->basename ." in dir ".$local_file->dirname;
			$self->net_google_drive_simple->file_upload( $local_file->to_string,  $did);
		}
   	}

}

# _make_path - recursive make path on google drive for a file
sub _make_path {
    my ( $self, $path_mf ) = @_;
    my $remote_dirs = $self->remote_dirs;
	my $full_path = $path_mf->to_string;
   	#$full_path .='/' if $full_path !~/\/$/; # secure last /
    $self->recursive_counter($self->recursive_counter+1);
    say $full_path;
    die "looping $path_mf" if $self->recursive_counter>8;
    die"Stop loop at $path_mf $self->recursive_counter \n".join("\n", sort keys %$remote_dirs) if $full_path eq '/' || $full_path eq $self->local_root->to_string;
	my $locfol = $path_mf->dirname;
	#my $lfs = $locfol->to_string;
	#$lfs .='/' if $lfs !~/\/$/; # secure last /
	my $did = $remote_dirs->{$locfol->to_string};
	if (!$did) {
#			die "$lfs does not exists in ". Dumper  $remote_dirs;
			$did = $self->_make_path($locfol);
	}
	my $basename = $path_mf->basename;
	say "Create new folder on Google Drive $basename in $locfol $did";
	$did = $self->net_google_drive_simple->folder_create( $basename,  $did);
	$remote_dirs->{$full_path} = $did;
    $self->{recursive_counter}--;
    $self->remote_dirs($remote_dirs);
	return $did;
}

sub _process_folder {
    my ( $self, $folder_id, $path_mf ) = @_;
    return if $path_mf->to_string =~ /\/googledrive\/googledrive/; #do not replicate camera
    my $gd       = $self->net_google_drive_simple;
    my $children = $gd->children_by_folder_id($folder_id);
    my $remote_dirs = $self->remote_dirs;
    my $local_files = $self->local_files;

    for my $child (@$children) {
        my $file_name = $child->title();
        $file_name =~ s{/}{_};
        my $local_file = $path_mf->child($file_name);
        delete $local_files->{$local_file};

        # a google document: export to preferred format
        next if $child->can("exportLinks");

        # pdfs and the like get downloaded directly
        if ( $child->can("downloadUrl") ) {
            die "NO LOCAL FILE" if ! "$local_file";
            my $s = $self->_should_sync( $child, $local_file );
            if ( $s eq 'down' ) {
                print "$local_file ..downloading\n";
                $gd->download( $child, "$local_file" );
            } elsif ( $s eq 'up' ) {
                print "$local_file ..uploading\n";
                $gd->file_upload( "$local_file", $folder_id );
            } elsif ( $s eq 'ok' ) {
                print "$local_file ..ok\n";
            } else {
                ...;
            }
            next;
        }
        # if we reach this, we could not "fetch" the file. A dir, then..
        my $dir = $path_mf->child($file_name);
        # "$dir" .='/' if "$dir" !~/\/$/; # secure last /
        $remote_dirs->{"$dir"} = $child->id();
        mkdir( "$dir" ) unless -d "$dir";

        # write hashes to object
        $self->remote_dirs($remote_dirs);
        $self->local_files($local_files);
        _process_folder( $self, $child->id(), $dir );
        $remote_dirs = $self->remote_dirs();
        $local_files = $self->local_files();

    }
    $self->local_files($local_files);
}

sub _should_sync {
    my ( $self, $remote_file, $local_file ) = @_;

    die "Not implemented" if $self->{force};
    die "NO LOCAL FILE" if ! $local_file;
#    if ( $remote_file->labels->{trashed} ) {
#        return 'delete_local';
#    }

    my $date_time_parser = DateTime::Format::RFC3339->new();

    my $local_epoch  = ( stat("$local_file") )[9];
    my $remote_epoch = $date_time_parser->parse_datetime( $remote_file->modifiedDate() )->epoch();
	return 'ok' if -d $local_file;
	my $rffs = $remote_file->fileSize();
	my $lffs = -s "$local_file";
	return 'down' if ! defined $lffs;
    if ( $remote_file->fileSize() == -s "$local_file" && $remote_file->md5Checksum() eq md5_hex(path($local_file)->slurp)  ) {
        return 'ok';
    }

	warn sprintf "%s    %s:%s    %s:%s", $local_file, int( $remote_epoch / 10 ), int( $local_epoch / 10 ) , $remote_file->fileSize() , -s "$local_file";
    if ( -f $local_file and $remote_epoch < $local_epoch ) {
        return 'up';
    } else {
        return 'down';
    }
}

1;

__END__

=head1 NAME

Net::Google::Drive::Simple::Mirror - Locally mirror a Google Drive folder structure

=head1 SYNOPSIS

    use Net::Google::Drive::Simple::Mirror;

    # requires a ~/.google-drive.yml file containing an access token,
    # see documentation of Net::Google::Drive::Simple
    my $google_docs = Net::Google::Drive::Simple::Mirror->new(
        remote_root => '/folder/on/google/docs',
        local_root  => 'local/folder',
        export_format => ['opendocument', 'html'],
    );

    $google_docs->mirror();


=head1 DESCRIPTION

Net::Google::Drive::Simple::Mirror allows you to locally mirror a folder structure from Google Drive.

=head2 GETTING STARTED

For setting up your access token see the documentation of Net::Google::Drive::Simple.

=head1 METHODS

=over 4

=item C<new()>

Creates a helper object to mirror a remote folder to a local folder.

Parameters:

remote_root: folder on your Google Docs account. See "CAVEATS" below.

local_root: local folder to put the mirrored files in.

export_format: anonymous array containing your preferred export formats.
Google Doc files may be exported to several formats. To get an idea of available formats, check 'exportLinks()' on a Google Drive Document or Spreadsheet, e.g.

    my $gd = Net::Google::Drive::Simple->new(); # 'Simple' not 'Mirror'
    my $children = $gd->children( '/path/to/folder/on/google/drive' );
    for my $child ( @$children ) {
        if ($child->can( 'exportLinks' )){
            foreach my $type (keys %{$child->exportLinks()}){
                print "$type";
            }
        }
    }

Now, specify strings that your preferred types match against. The default is ['opendocument', 'html']

download_condition: reference to a sub that takes the remote file name and the local file name as parameters. Returns true or false. The standard implementation is:

    sub _should_download{
        my ($self, $remote_file, $local_file) = @_;

        return 1 if $self->{force};

        my $date_time_parser = DateTime::Format::RFC3339->new();

        my $local_epoch =  (stat($local_file))[9];
        my $remote_epoch = $date_time_parser
                                ->parse_datetime
                                    ($remote_file->modifiedDate())
                                ->epoch();

        if (-f $local_file and $remote_epoch < $local_epoch ){
            return 0;
        }
        else {
            return 1;
        }
    }

download_condition can be used to change the behaviour of mirror(). I.e. do not download but list al remote files and what they became locally:

    my $google_docs = Net::Google::Drive::Simple::Mirror->new(
        remote_root   => 'Mirror/Test/Folder',
        local_root    => 'test_data_mirror',
        export_format => ['opendocument','html'],
        # verbosely download nothing:
        download_condition => sub {
            my ($self, $remote_file, $local_file) = @_;
            say "Remote:     ", $remote_file->title();
            say "`--> Local: $local_file";
            return 0;
        }
    );

    $google_docs->mirror();


force: download all files and replace local copies.

=item C<mirror()>

Recursively mirrors Google Drive folder to local folder.

=back

=head1 CAVEATS

At the moment, remote_root must not contain slashes in the file names of its folders.

    remote_root => 'Folder/Containing/Letters A/B'

is not existing because folder "Letters A/B" contains a slash:

    Folder
         `--Containing
                     `--Letters A/B

This will be resolved to:

    Folder
         `--Containing
                     `--Letters A
                                `--B

The remote_root 'Example/root' may contain folders and files with slashes. These get replaced with underscores in the local file system.

    remote_root => 'Example/root';

    Example
          `--root
                `--Letters A/B

With local_root 'Google-Docs-Mirror' this locally becomes:

    local_root => 'Gooogle-Docs-Mirror';

    Google-Docs-Mirror
                    `--Letters A_B

(Net::Google::Drive::Simple::Mirror uses folder ID's as soon as it has found the remote_root and does not depend on folder file names.)

=head1 AUTHOR

Altered by Stein Hammer C<steihamm@gmail.com>

=head1 COPYRIGHT AND LICENSE

This module is a fork of the CPAN module Net::Google::Drive::Mirror 0.053

Copyright (C) 2014 by :m)

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
