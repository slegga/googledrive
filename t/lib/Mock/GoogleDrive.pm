package Mock::GoogleDrive;
use Mojo::Base -base;
use Mojo::File 'path';
use Digest::MD5 qw/md5_base64 md5_hex/ ;
use DateTime;
use DateTime::Format::RFC3339;
use Carp qw/confess/;
use Data::Dumper;

has remote_root => sub {path('t/remote')};
has remote_root_id => 'rootid';
has dateformatter => sub { DateTime::Format::RFC3339->new() };
has file_ids => sub {
	my $self = shift;
	my @remote_paths = $self->remote_root->list_tree({dir=>1});
	my $return={};
	my $num_fold_local_root = @{$self->remote_root->to_array};
	for my $path(@remote_paths) {

       	my @tmp = @$path[$num_fold_local_root .. $#$path];
		my $rem_pathfile = path('/',@tmp);
		my ($key,$value) = $self->_return_new_file_metadata_from_filename("$rem_pathfile");
		$return->{$key} = $value;
		}
	my ($key,$value) = $self->_return_new_file_metadata_from_filename( '/' );
	$return->{$key} = $value;
	return $return;
}; # TODO Regnut md5_base64 for alle kataloger og filer i remote fra stifillnavn


#		push @$return,$return $self->_return_new_file_metadata($rem_pathfile);
sub _return_new_file_metadata_from_filename {
	my $self = shift;
	my $remote_filename = shift;
	return if ! $remote_filename;
	confess "Expect an string $remote_filename" if ref $remote_filename;
	my $file = path($remote_filename);
	my $key = md5_base64($remote_filename);
	my $parent;
	if ($remote_filename eq '/') {
		$key = $self->remote_root_id;
		$parent = undef;
	} else {
		$parent = md5_base64($file->dirname->to_string);
	}
	my $value = {
			id => "$key",
			remote_pathname => $remote_filename,
			real_path => $remote_filename eq '/'  ? $self->remote_root->realpath : $file->realpath,
			modifiedDate => $self->dateformatter->format_datetime(DateTime->from_epoch(epoch => $file->stat->mtime)),
			downloadUrl => 'x',
			title => $file->basename,
			parents => [{id => $parent}],
			fileSize => $file->stat->size,
			md5Checksum => md5_hex($remote_filename),
		};
	return ($key,$value);
}

sub children {
	my $self = shift;
	warn 'children '. join(',',@_);
	my $file_id = 'children FILE_ID LEGG INN NOE LURT HER';
	my $parent_id = 'children PARENT_ID LEGG INN NOE LURT HER';
	$parent_id = $self->remote_root_id if $_[0] eq '/';
	return ($file_id,$parent_id) if wantarray;
	return $file_id;
}

sub _get_remote_path_from_full_path_file {
	...;
#	return
}

sub children_by_folder_id {
	my( $self, $folder_id, $opts, $search_opts ) = @_;
	my $remote_dir = $self->file_ids->{$folder_id}->{real_path};
	if (! defined $remote_dir) {
		warn "try to get $folder_id -> real_path";
		my $file_ids = $self->file_ids;
		die Dumper $file_ids;
	}
	my @return;
	for my $f( $remote_dir->list_tree) {
		my $remote_dir_name = $self->get_remote_name_from_full_path($f);
		my $tmp = $self->file_ids->{md5_base64($remote_dir_name)};
		die "Not found $remote_dir_name in file_ids ".md5_base64($remote_dir_name).Dumper $self->file_ids if ! defined $tmp ;
		push @return, $tmp;
	}
	warn 'children_by_folder_id '. join(',',@_);
	return \@return;
}

sub get_remote_name_from_full_path{
	my ($self,$full_path) = @_;
	my $root_num_of_dirs = @{$self->remote_root};
	my $return = path(@$full_path[$root_num_of_dirs .. $#$full_path]);
	return $return->to_string;
}

sub search{
	my $self = shift;
	my ($c,$d,$search) = @_;
	warn 'search '. join(',',@_);
	my @return;
	if ( $search =~ /^(\w+)\s*>\s*\'([\w\-\:]+)\'\s*[aA][nN][dD]\s*(\w+)\s*<\s*\'([\w\-\:]+)\'$/) {
		my ($key1,$value1,$key2,$value2) =($1,$2,$3,$4);
		my $dateparser =DateTime::Format::RFC3339->new();
		if ($key1 =~/Date$/ && $key2 =~/Date$/) {
			$value1 = $dateparser->parse_datetime( $value1 )->epoch;
			$value2 = $dateparser->parse_datetime( $value2 )->epoch;

			for my $fmd (values %{$self->file_ids}) {
				if (exists $fmd->{$key1} && $dateparser->parse_datetime( $fmd->{$key1} )->epoch > $value1
				&& exists  $fmd->{$key1} && $dateparser->parse_datetime( $fmd->{$key2} )->epoch < $value2) {
					push @return, $fmd;
				}
			}
			return \@return;
		}
	}
	die 'No handling of search. Please add regexp to handle : '.$search;
}

sub path_resolve {
	my $self = shift;
	warn 'path_resolve '. join(',',@_);
	my $remote_file  = $self->remote_root->child(shift);
	return if ! -f $remote_file->to_string;
	return 'path_resolve LEGG INN NOE LURT HER'
}

sub file_metadata {
	my $self = shift;
	my $file_id = shift;
	warn 'file_metada '. join(',',@_);

	return $self->file_ids->{$file_id};
}

sub file_upload {
	my $self = shift;
	warn 'file_upload '. join(',',@_);
	my $local_pathfile = shift;
	my $remote_folder_id = shift;
	my $file_id = shift;
	... if $file_id;
	my $local_file = path($local_pathfile);
	my $filename = $local_file->basename;
	my $upload_path = $self->remote_root->child($filename);
	$local_file->copy_to($upload_path->to_string);
	my ($key,$value) = $self->_return_new_file_metadata($upload_path->to_string);
	my $file_ids = $self->file_ids;
	$file_ids->{$key} = $value;
	$self->file_ids($file_ids);
	return $key;
}
1;