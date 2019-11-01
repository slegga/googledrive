package Net::Google::Drive::Simple::LocalSync;
use Mojo::Base -base;
use Net::Google::Drive::Simple;
use DateTime::Format::RFC3339;
use DateTime;
use Carp;
use Mojo::File 'path';
use Mojo::Home;
use Digest::MD5 qw /md5_hex/;
use Encode qw /decode encode/;
use utf8;
use Data::Dumper;
use Mojo::SQLite;
use Encode qw(decode encode);

use FindBin;
use lib "FindBin::Bin/../lib";
use Mojo::File::Role::UTF8;
binmode STDOUT, ':encoding(UTF-8)';


our $VERSION = '0.54';
has remote_root_ID =>sub {my $self = shift;
    my $gd=$self->net_google_drive_simple;
    my ( undef, $remote_root_ID ) = $gd->children( $self->remote_root );
    return $remote_root_ID};
has net_google_drive_simple => sub {Net::Google::Drive::Simple->new()};
has remote_root => sub{path('/')};
has dbfile => $ENV{HOME}.'/.googledrive/files_state.db';
has sqlite => sub {
	my $self = shift;
	if ( -f $self->dbfile) {
		return Mojo::SQLite->new()->from_filename($self->dbfile);
	} else {
		my $path = path($self->dbfile)->dirname;
		if (!-d "$path" ) {
			$path->make_path;
		}
		return Mojo::SQLite->new("file:".$self->dbfile);
	#	die "COULD NOT CREATE FILE ".$self->dbfile if ! -f $self->dbfile;
	}

};
has db => sub {shift->sqlite->db};

has 'local_root';
has 'local_files';
has 'remote_dirs';
has recursive_counter => 0;
has 'time';

sub mirror {
    my ($self, $args) = @_;
    $self->time(time);
    say "START: ". (time - $self->time);
    #update database if new version
    my $path = Mojo::Home->new->child('migrations', 'files_state.sql')->with_roles('Mojo::File::Role::UTF8');
	$self->sqlite->migrations->from_file($path->to_string_utf8)->migrate;

    # get list of localfiles:
	my %lc = map { $_ => -d $_ } map { $_->with_roles('+UTF8')->to_string_utf8 } path($self->local_root)->list_tree({dont_use_nlink=>1,dir=>1})->each;
    my $remote_dirs = $self->remote_dirs;
    $remote_dirs->{$self->local_root } = $self->remote_root_ID;

#	say "localfile $_" for keys %lc;
    $self->remote_dirs($remote_dirs);
     $self->local_files( \%lc);

    say "BEFORE _process_folder " . $self->_timeused;
    #may add to remove_dirs
    $self->_process_folder_full( $self->remote_root_ID, $self->local_root );

    say "AFTER _process_folder " . $self->_timeused;

    #update remote_dirs;
    $remote_dirs = $self->remote_dirs;

	# uploads new files
   	for my $lf (keys %{$self->local_files}) {
        my $local_file = path($lf)->with_roles('Mojo::File::Role::UTF8');
        my $lf_name = $local_file->to_string_utf8;
		next if $lf_name =~/\/Camera Uploads\//; #do not replicate camera
		next if $lf_name =~ /\/googledrive\/googledrive/; #do not replicate camera
        next if $lf_name =~ /\/googledrive[^\/]/; #do not replicate camera
		my $locfol = $local_file->dirname;

        #$locfol = $locfol->with_roles('Mojo::File::Role::UTF8'); This did not work on 8.25
		my $local_dir = Encode::decode('UTF-8', $locfol->to_string);
		#$local_dir .='/' if $local_dir !~/\/$/; # secure last /

		my $did = $remote_dirs->{$local_dir};
		$did = $self->_make_path($locfol) if (!$did);
		die if ! $did;

#		say "push new file $local_file->basename. $did . ' # '.  $local_file->dirname->to_string;
		die "No local_file" if ! $lf_name;
		if (! $did) {
			warn "No directory id";
            $remote_dirs = $self->remote_dirs;
			die Dumper $remote_dirs;
		}


		if (! $self->local_files->{$lf_name}) { #check if not dir
			say "Create new file on Google Drive ".Encode::decode('UTF8',$local_file->basename) ." in dir ".Encode::decode('UTF8', $local_file->dirname);
            my $try = 1;
            while ($try) {
                eval {
                    if (-f $lf_name) {
                        $self->net_google_drive_simple->file_upload( $lf_name, $did ) ;
                    } else {
                        say "File does not exists locally $lf_name ignore file. Probably encoding errors";
                    }
                    $try=0;
                    1;
                } or warn $@;
            }

            say "Finish $lf_name";
		}
   	}
    say "FINISH SCRIPT " . $self->_timeused;

}

sub _timeused {
    my $self = shift;
    return time - $self->time;
}

# _make_path - recursive make path on google drive for a file
sub _make_path {
    my ( $self, $path_mf ) = @_;
    my $remote_dirs = $self->remote_dirs;
	my $full_path = $path_mf->to_string_utf8;
   	#$full_path .='/' if $full_path !~/\/$/; # secure last /
    $self->recursive_counter($self->recursive_counter+1);
    say "Makepath in: $full_path";
    die "looping $path_mf" if $self->recursive_counter>8;
    die"Stop loop at $path_mf $self->recursive_counter \n".join("\n", sort keys %$remote_dirs) if $full_path eq '/' || $full_path eq $self->local_root->with_roles('Mojo::File::Role::UTF8')->to_string_utf8;
	my $locfol = $path_mf->dirname;
	#my $lfs = $locfol->to_string;
	#$lfs .='/' if $lfs !~/\/$/; # secure last /
	my $did = $remote_dirs->{$locfol->to_string_utf8};
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

sub _process_folder_full {
    my ( $self, $folder_id, $path_mf ) = @_;
    return if $path_mf->to_string =~ /\/googledrive\/googledrive/; #do not replicate camera
    my $gd       = $self->net_google_drive_simple;
    my $children = $gd->children_by_folder_id($folder_id);
    my $remote_dirs = $self->remote_dirs;
    my $local_files = $self->local_files;

    for my $child (@$children) {
        my $file_name = decode('UTF-8',$child->originalFilename||$child->title); #latin1 or utf8 ?
        # $file_name =~ s{/}{_};
        my $local_file = $path_mf->child($file_name)->with_roles('Mojo::File::Role::UTF8');
        my $loc_file_name = $local_file->to_string_utf8;
        delete $local_files->{$loc_file_name};

        # Ignore document. Edit on line instead.
        next if $child->can("exportLinks");

        # pdfs and the like get downloaded directly
        if ( $child->can("downloadUrl") ) {
            die "NO LOCAL FILE" if ! $loc_file_name;
            my $s = $self->_should_sync( $child, $local_file );
            if ( $s eq 'down' ) {
                print "$loc_file_name ..downloading\n";
                $gd->download( $child, $loc_file_name );
                my ($local_size, $local_mod) = (stat($loc_file_name))[7,9];
                $self->db->query('replace into files_state (loc_pathfile,loc_size,loc_mod_epoch,loc_md5_hex)
                	VALUES (?,?,?,?)',$loc_file_name,$local_size,$local_mod,$child->md5Checksum);
            } elsif ( $s eq 'up' ) {
                print "$loc_file_name ..uploading\n";
                my $try = 1;
                while ($try) {
                    eval {
                        $gd->file_upload( $loc_file_name, $folder_id );
                        $try=0;
                        1;
                    } or warn $@;
                }
#                $self->db->query('replace into files_state (loc_pathfile,loc_size,loc_mod_epoch,loc_md5_hex)
#                  	VALUES (?,?,?,?)',$loc_file_name ,$local_size,$local_mod,$child->md5Checksum);
            } elsif ( $s eq 'ok' ) {
                print "$loc_file_name ..ok\n";
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
        _process_folder_full( $self, $child->id(), $dir );
        $remote_dirs = $self->remote_dirs();
        $local_files = $self->local_files();

    }
    $self->local_files($local_files);
}

sub _should_sync {
    my ( $self, $remote_file, $local_file ) = @_;
    my $loc_file_name = $local_file->to_string_utf8;
    die "Not implemented" if $self->{force};
    die "NO LOCAL FILE" if ! $loc_file_name ;
#    if ( $remote_file->labels->{trashed} ) {
#        return 'delete_local';
#    }

    my $date_time_parser = DateTime::Format::RFC3339->new();

    my ($loc_size,$loc_mod)  = ( stat($loc_file_name ) )[7,9];
    my $rem_mod = $date_time_parser->parse_datetime( $remote_file->modifiedDate() )->epoch();
	return 'ok' if -d $loc_file_name ;
	my $rffs = $remote_file->fileSize();
	return 'down' if ! defined $loc_mod;
	my $filedata = $self->db->query('select * from files_state where loc_pathfile = ?',$loc_file_name )->hash;

	my $loc_md5_hex;

    if (! keys %$filedata) {
        # file exists in remote and local but not registered in sqlite cache

        for my $r( $self->db->query('select * from files_state where loc_pathfile like ?',substr($loc_file_name ,0, 4).'%')->hashes->each ) {
            next if !$r;
            say $r if ref $r ne 'HASH';
            say join('#', grep{$_} map{$self->_utf8ifing($_)} grep {$_} values %$r) ;
        }
        # die "No data cached data for $loc_file_name";
        say "insert cache $loc_file_name ";
        my $loc_md5_hex = md5_hex($loc_file_name );
        $self->db->query('insert into files_state(loc_pathfile, loc_size, loc_mod_epoch, loc_md5_hex
            , rem_file_id,   rem_filename, rem_mod_epoch, rem_md5_hex, act_epoch, act_action)
            VALUES(?,?,?,?,?, ?,?,?,?,?)'
            ,$loc_file_name , $loc_size, $loc_mod, $loc_md5_hex, $remote_file->id(), $remote_file->title(), $rem_mod , $remote_file->md5Checksum(), time, 'registered'
        );
        $filedata = {loc_pathfile=>$loc_file_name  , loc_size=>$loc_size, loc_mod_epoch=>$loc_mod, loc_md5_hex=>$loc_md5_hex,
            , $remote_file->id(), rem_filename =>$remote_file->title(), rem_mod_epoch=>$rem_mod, rem_md5_hex=>$remote_file->md5Checksum() ,
             act_epoch=>time, 'registered'};
    }
    if (! $loc_mod) {
        die "File does not exists $loc_file_name";
        # $self->db->query('insert into files_state(loc_pathfile, loc_size, loc_mod_epoch, loc_md5_hex)',?,?,?,?);
    }

    # File not changed on disk
    if ( $loc_size == $filedata->{loc_size} && $loc_mod == $filedata->{loc_mod_epoch} ) {
    	$loc_md5_hex = $filedata->{loc_md5_hex};
    } else {
        say "calc md5 for changed file ". $local_file;
    	$loc_md5_hex = md5_hex(path($local_file)->slurp);
    	$self->db->query('update files_state set loc_tmp_md5_hex = ? where loc_pathfile = ?',$loc_md5_hex, $loc_file_name );
    }

	# filediffer up or down?
    if ($loc_md5_hex eq $remote_file->md5Checksum()) {
 		return 'ok';
    }

	#warn sprintf "%s    %s:%s    %s:%s", $local_file, int( $rem_mod / 10 ), int( $loc_mod / 10 ) , $remote_file->fileSize() , -s $loc_file_name ;
    if ( -f $local_file and $rem_mod < $loc_mod ) {
        return 'up';
    } else {
        return 'down';
    }
}


#Try to fix utf8


sub _utf8ifing {
    my ($self, $malformed_utf8) = @_;
    $malformed_utf8 =~ s/[\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]/_/;
    #$malformed_utf8=~s/Ã.+//;

    $return = decode('UTF-8', $malformed_utf8, Encode::FB_DEFAULT);
    $return =~ s/\x{E000}-\x{FFFD}/_/g;
    return $return;
}

######################################################################################
######################################################################################
#                                  DELTA CODE
######################################################################################
######################################################################################


sub _process_delta {
    # look for changes
    my $self = shift;
    my $local_root = $self->local_root;
    my $dt = DateTime::Format::RFC3339->new();
    my %lc = map { my @s = stat($_);$_=>{is_folder =>(-d $_), size => $s[7], mod => $s[9]} } map { $_->with_roles('+UTF8')->to_string_utf8 } path( "$local_root" )->list_tree({dont_use_nlink=>1,dir=>1})->each;
    my $cache = $self->db->query('select * from files_state')->hashes->to_array;
    for my $lc_pathfile (keys %lc) {
        if (! exists $cache->{$lc_pathfile} || ! $cache->{$lc_pathfile} ) {
            $lc{$lc_pathfile}{sync} = 1;
        }
        elsif ($lc{$lc_pathfile}{size} != $cache->{$lc_pathfile}{loc_size} || $lc{$lc_pathfile}{loc_mod_epoch} != $cache->{$lc_pathfile}{loc_mod_epoch} ) {
            $lc{$lc_pathfile}{sync} = 1;
        }
        else {
            $lc{$lc_pathfile}{sync} = 0;
        }
    }
    my $gd=$self->net_google_drive_simple;
    my $cache_last_delta_sync_epoch  = $self->db->query("select value from replication_state_int where key = 'delta_sync_epoch'")->hash->{value};
    my $rem_chg_objects = $gd->search(sprintf("modifiedDate > '%s'", $dt->format_datetime(DateTime->from_epoch($cache_last_delta_sync_epoch))));
    print Dumper $rem_chg_objects;

    # process changes

    # from remote to local
    for my $rem_object (@$rem_chg_objects) {
        say "Remote".$rem_object->title;
        # if ($self->_should_sync())
    }

}










1;

__END__

=head1 NAME

Net::Google::Drive::Simple::LocalSync - Locally mirror a Google Drive folder structure

=head1 SYNOPSIS

    use Net::Google::Drive::Simple::LocalSync;

    # requires a ~/.google-drive.yml file containing an access token,
    # see documentation of Net::Google::Drive::Simple
    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root => '/folder/on/google/docs',
        local_root  => 'local/folder',
        export_format => ['opendocument', 'html'],
    );

    $google_docs->mirror();


=head1 DESCRIPTION

Net::Google::Drive::Simple::LocalSync allows you to locally mirror a folder structure from Google Drive.

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

    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root   => 'Mirror/Test/Folder',
        local_root    => 'test_data_mirror',
        export_format => ['opendocument','html'],
        # verbosely download nothing:
        download_condition => sub {
            my ($self, $remote_file, $local_file) = @_;
            say "Remote:     ", $remote_file->title();
            say "`--> Local: $loc_file_name;
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

(Net::Google::Drive::Simple::LocalSync uses folder ID's as soon as it has found the remote_root and does not depend on folder file names.)

=head1 AUTHOR

Altered by Stein Hammer C<steihamm@gmail.com>

=head1 COPYRIGHT AND LICENSE

This module is a fork of the CPAN module Net::Google::Drive::LocalSync 0.053

Copyright (C) 2014 by :m)

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
