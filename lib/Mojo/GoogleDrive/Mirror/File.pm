package Mojo::GoogleDrive::Mirror::File;
use Mojo::Base -base, -signatures;
use Mojo::UserAgent;
use Mojo::File 'path';
use Mojo::URL;
use File::MMagic;
use Mojo::JSON qw /encode_json decode_json/;
use Data::Dumper;
use Mojo::Collection;
use Mojo::GoogleDrive::Mirror;

=head1 NAME

Mojo::GoogleDrive::Mirror::File - Google Drive file object

=head1 SYNOPSIS

    use Mojo::GoogleDrive::Mirror;
    use Mojo::GoogleDrive::Mirror::File;
    my $mgm= Mojo::GoogleDrive::Mirror->new(local_root=>$ENV{HOME}.'/googledrive');
    my $file = $mgm->file('/test/testfile.txt');
    $file->download;

=head1 DESCRIPTION

A help file for Mojo::GoogleDrive::Mirror, usually this object is not ment to be used by others.
Responsible to implement common logic for each file.

=head1 ATTRIBUTES

=over 4

=item pathfile - String containing relative path on GoogleDrive

=item metadata - Hash containing meta data from googledrive

=back

=head1 METHODS

=cut

our %metadata_all=();

has 'pathfile';
has 'remote_root' => '/';
has 'local_root';# => "$ENV{HOME}/googledrive/";
#has 'api_file_url' => "https://www.googleapis.com/drive/v3/files/";
#has 'api_upload_url' => "https://www.googleapis.com/upload/drive/v3/files/";
#has 'oauth';     #     => OAuth::Cmdline::GoogleDrive->new();
#has 'sync_direction';# => 'both-cloud'; # both ways clound wins if in conflict
has 'metadata' => sub{{}};
#has ua => sub { Mojo::UserAgent->new};
has mgm => sub { Mojo::GoogleDrive::Mirror->new()};

=head2 INTERESTING_FIELDS

Constant set to minimum meta data for a file.

=cut

sub INTERESTING_FIELDS {
    return 'id,kind,name,mimeType,parents,modifiedTime,trashed,explicitlyTrashed';
}

=head2 lfile

    $file->lfile

Full local path to file mirrored from google drive.

=cut

sub lfile($self) {
    die "Missing local_root" if ! $self->local_root;
    return path($self->local_root)->child($self->pathfile);
}

=head2 rfile

    $fullpath = $file->rfile

Full remote file path.

=cut

sub rfile($self) {
    $self->remote_root('/') if ! $self->remote_root;
    return path($self->remote_root)->child($self->pathfile);
}


=head2 get_metadata

    $metadata = $file->get_metadata();

Look up cashed data, if not as google drive for an update.

=cut

sub get_metadata($self) {
    my $metadata;
    $metadata = $self->metadata if ($self->metadata);
    if (! ref $metadata || ! keys %$metadata) {
        $metadata = $metadata_all{$self->rfile->to_string};
    }
    if (! ref $metadata || ! keys %$metadata) {
        my @pathobj;
        @pathobj = $self->path_resolve->map(sub{$_->metadata})->each;
#        say STDERR Dumper \@pathobj;
        $metadata = $pathobj[$#pathobj] if @pathobj;# kunne vært get_metadata
    }
    return $metadata;
}

=head2 upload

    my $meta = $file->upload;

Uploads the file to google drive.

=cut

sub upload {
    #POST https://www.googleapis.com/upload/drive/v3/files
    # https://mojolicious.io/blog/2017/12/11/day-11-useragent-content-generators/
    my $self = shift;
    my $main_header = {$self->{oauth}->authorization_headers()};
    $main_header ->{'Content-Type'} = 'multipart/related';
    my $local_file_content = $self->lfile->slurp;
    my $byte_size;
    {
            use bytes;
            $byte_size = length($local_file_content);
    }
    my $metadata = $self->get_metadata;
    my $metapart = {'Content-Type' => 'application/json; charset=UTF-8', 'Content-Length'=>$byte_size, content => encode_json($metadata),};
    my $urlstring = Mojo::URL->new($self->mgm->api_upload_url)->query(uploadType=>'multipart')->to_string;
    say $urlstring;
    my $meta = $self->mgm->http_request('post',$urlstring, $main_header ,   multipart => [
    $metapart,
    {
      'Content-Type' => $self->file_mime_type,
      content => $local_file_content,
    }
  ] );
    my $md = $self->metadata;
    $md->{$_} = $meta->{$_} for (keys %$meta);
    $self->metadata($md);
    $metadata_all{$self->rfile->to_string} = $md;
    return $self;
}

=head2 file_mime_type

    my $mime_type = $file->file_mime_type;

Return mime type for the local file.

=cut

sub file_mime_type {
    my ( $self, $file ) = @_;

    # There don't seem to be great implementations of mimetype
    # detection on CPAN, so just use this one for now.

    if ( !$self->{magic} ) {
        $self->{magic} = File::MMagic->new();
    }

    return $self->{magic}->checktype_filename($file);
}

=head2 path_resolve

    $collectonoffiles = $file->path_resolve;

Get File objects for each element in path include


=cut

sub path_resolve($self) {
    my @parts = grep { $_ ne '' } @{ $self->rfile->to_array };

    my @return;
    my $folder_id;
#    say  "Parent: $folder_id" if $ENV{MOJO_DEBUG};

    # get root
    my $parent_id='root';
    my $id;
    my $root_meta;
    if(exists $metadata_all{'/'}) {
        $root_meta = $metadata_all{'/'};
    }
    if (!$id) {
        my $url = Mojo::URL->new($self->mgm->api_file_url)->path($parent_id)->query(fields=> INTERESTING_FIELDS );
        say $url;
        $root_meta = $self->mgm->http_request('get',$url,'');
        $metadata_all{'/'} = $root_meta;
    }
    die "Can not find root" if !$root_meta;
    push @return, $root_meta;
    $parent_id = $root_meta->{id};
    my $tmppath=path('/');
    my $old_part='/';
    my $i = -1;
  PART: for my $part (@parts) {
        $i++;
        say  "Looking up part $part (folder_id=$folder_id)" if $ENV{MOJO_DEBUG};
        my $dir;
        if (exists $metadata_all{$tmppath->to_string}) {
            $dir = $self->{mgm}->file_from_metadata($metadata_all{$tmppath->to_string});
        }

        if (! $dir) {
            $dir = $self->{mgm}->file_from_metadata({id => $parent_id, name => $old_part},pathfile => $tmppath->to_string);
        }
        $tmppath = $tmppath->child($part);
        my %param=(name=>$part);
        if ($i<$#parts) {
            $param{dir_only}=1;
        }
        my @children = $dir->list(%param)->each;

        $old_part=$part;
        return Mojo::Collection->new() unless @children;
#        die Dumper $children;# if ! ref $children eq 'ARRAY';

        for my $child (@children) {
            say "Found child ", $child->metadata->{name} if $ENV{MOJO_DEBUG};
            if ( $child->metadata->{name} eq $part ) {
                $parent_id = $child->metadata->{id};
                push @return,$child->metadata;
                next PART;
            }
        }

        my $msg = "Child $part not found";
#        $self->error($msg);
#        ERROR $msg;
        die $msg;
        return;

    }
    #die Dumper \@return;
     @return = map{ $self->{mgm}->file_from_metadata($_)} @return;
    return Mojo::Collection->new(@return);
}

=head2 list

    print $_->metadata->{name} for $file->list;

Return Mojo::Collection of files if object is a directory. Else return empty.

=cut

sub list($self, %options) {
    my $folder_id;
    my @return;
    my $meta = $self->get_metadata;
    $folder_id = $meta->{id} if exists $meta->{id};
    if (! $folder_id && $self->rfile->to_string) {
        $folder_id = $metadata_all{$self->rfile->to_string}->{parents}->[0] if exists $metadata_all{$self->rfile->to_string};
    }
    if ($self->pathfile && ! $folder_id) {
        ...;
        return;
    }
    my    $opts= \%options;
    $opts->{q}='';
    if ($options{dir_only}) {
        $opts->{q} = q_and($opts->{q},"mimeType = 'application/vnd.google-apps.folder'");
    }

    $opts->{q} = q_and($opts->{q},"'$folder_id' in parents");

    if ($options{name}) {
        $opts->{q} = q_and($opts->{q},"name = '$options{name}'");
    }

    my @children = ();
    delete $opts->{dir_only};
    delete $opts->{name};

    my $url = Mojo::URL->new($self->mgm->api_file_url)->query($opts);

    my $data = $self->mgm->http_request('get',$url,'');

    my @objects =  map {$self->{mgm}->file_from_metadata($_)} @{ $data->{files} };
    return Mojo::Collection->new(@objects);
}

=head2 q_and

    $q = q_and($q,"name = 'filename.txt'");

=cut

sub q_and($old,$add) {
    my $return=$old;
    $return .=' and ' if $return;
    $return .= $add;
    return $return;
}
1;
