package Net::Google::Drive::Simple::LocalSync;
use Mojo::Base -base;
use Net::Google::Drive::Simple;
use DateTime::Format::RFC3339;
use DateTime;
use Carp;
use Mojo::File 'path';
use Mojo::Home;
use Digest::MD5 qw /md5_hex/;
use utf8;
use Data::Dumper;
use Mojo::SQLite;
use Encode qw(decode encode);
use File::Copy;
use utf8;

use FindBin;
use lib "FindBin::Bin/../lib";
binmode STDOUT, ':encoding(UTF-8)';
our $VERSION = '0.54';

=head1 NAME


Net::Google::Drive::Simple::LocalSync - Locally syncronize a Google Drive folder structure

=head1 SYNOPSIS

	use lib "$FindBin::Bin/../lib";
	use Net::Google::Drive::Simple::LocalSync;

	# see documentation of Net::Google::Drive::Simple

	my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
    remote_root => path('/'),
    local_root  => $home->child('googledrive'),
    conflict_resolution => 'keep_remote',
	);

    $google_docs->mirror();


=head1 DESCRIPTION

Net::Google::Drive::Simple::LocalSync allows you to locally mirror a folder structure from Google Drive.

=head2 GETTING STARTED

For setting up your access token see the documentation of Net::Google::Drive::Simple.

=head1 ATTRIBUTES

=cut


has remote_root_ID =>sub {my $self = shift;
    my $gd=$self->net_google_drive_simple;
    my ( undef, $remote_root_ID ) = $gd->children( $self->remote_root );
    return $remote_root_ID};
has net_google_drive_simple => sub {Net::Google::Drive::Simple->new()};
has remote_root => sub{path('/')};
has delete_to => 'local'; # where to delete. Local or both or none.
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
has new_time => sub{time()};
has 'time';
has 'old_time' => sub {
    my $self =shift;
    my $tmp = $self->db->query('select value from replication_state_int where key = \'delta_sync_epoch\'')->hash;
    if (ref $tmp) {
        return $tmp->{value};
    } else {
        return 0;
    }
};
has last_end_run_time => sub {
    my $self =shift;
    my $tmp = $self->db->query('select value from replication_state_int where key = \'delta_sync_epoch_end_run\'',)->hash;
    if (ref $tmp) {
        return $tmp->{value};
    } else {
        return $self->old_time;
    }
};
#has drive_encoding => 'Latin1';  # Encoding for from title field

=head1 METHODS

=head2 mirror

Start syncronize local tree and remote tree on google drive.
Jump over google docs files.

=cut

sub mirror {
    my ($self, $args) = @_;
    my $path = Mojo::Home->new->child('migrations', 'files_state.sql');
	$self->sqlite->migrations->from_file($path->to_string)->migrate;

    $self->time(time);


    $self->new_time(time);
    say "LAST RUN:  ". localtime($self->old_time);
    say "START: ". (time - $self->time);
    #update database if new version

    # get list of localfiles:
	my %lc = map { $_ => -d $_ } map { $_->to_string } path($self->local_root)->list_tree({dont_use_nlink=>1,dir=>1})->each;
    my $remote_dirs = $self->remote_dirs;
    if (! -d $self->local_root) {
    	warn "Creating directory ".$self->local_root;
    	$self->local_root->make_path;
    }
    $remote_dirs->{$self->local_root } = $self->remote_root_ID;

#	say "localfile $_" for keys %lc;
    $self->remote_dirs($remote_dirs);
     $self->local_files( \%lc);

    say "BEFORE _process_folder " . $self->_timeused;
    #may add to remove_dirs
    $self->_process_delta;

    $self->db->query('replace into replication_state_int(key,value) VALUES(?,?)', "delta_sync_epoch",$self->new_time);
    $self->db->query('replace into replication_state_int(key,value) VALUES(?,?)', "delta_sync_epoch_end_run",time);

    say "FINISH SCRIPT " . $self->_timeused;

}

sub _timeused {
    my $self = shift;
    return time - $self->time;
}

=head2 remote_make_path

Recursive find or make path on google drive for a new pathfile

=cut

sub remote_make_path {
    my ( $self, $path_mf ) = @_;
   my $remote_dirs = $self->remote_dirs;
	my @ids = $self->path_resolveu($path_mf->to_string);
	if (@ids) {
		say join(',',map{$_//'__UNDEF__'} @ids);
		return $ids[0]  if $ids[0]; # Return correct path if ok
	}

	my $full_path = $path_mf->to_string;

    say "Makepath in: $full_path";

    return $self->remote_root_ID if $full_path eq '/' ;
    if ($full_path eq $self->local_root->to_string) {
       	return $self->remote_root_ID;
    }
	my $locfol = $path_mf->dirname;
    if ($locfol->to_string eq $self->local_root->to_string || $locfol->to_string eq '/') {
    	return $self->remote_root_ID;
    }
    #    die "Stop loop at $path_mf $full_path". $self->recursive_counter."\n".join("\n", sort keys %$remote_dirs)
	my $did = $remote_dirs->{$locfol->to_string};
	if (!$did) {
		my @ids = $self->path_resolveu($locfol->to_string);
		if (@ids) {
			$did= $ids[0] ;
			$remote_dirs->{$locfol->to_string} = $did;
		}
	}
	if (!$did) {
#			die "$lfs does not exists in ". Dumper  $remote_dirs;
			$did = $self->remote_make_path($locfol);
	}
	my $basename = $path_mf->basename;
	#my $parent_obj = $self->net_google_drive_simple->data_factory($self->net_google_drive_simple->file_metadata($did));
	my $children = $self->net_google_drive_simple->children_by_folder_id($did);
	for my $child(@$children) {
		return $did if _get_rem_value($child,'title') eq $basename;
	}
	say "Create new folder on Google Drive: $basename in $locfol $did";
	$did = $self->net_google_drive_simple->folder_create( $basename,  $did);
	$remote_dirs->{$full_path} = $did;
    $self->{recursive_counter}--;
    $self->remote_dirs($remote_dirs);
	return $did;
}

sub _get_rem_value {
	my $remote_file = shift;
	my $key=shift;
#	say ref $remote_file;
	confess Dumper $remote_file if ( ref $remote_file eq 'ARRAY' || ! ref $remote_file);
	if (ref $remote_file eq 'HASH') {
		return $remote_file->{$key}  if exists $remote_file->{$key};
		die "Missing key $key";
		return  if exists $remote_file->{$key};
		}
	return $remote_file->$key if $remote_file->can($key);
	print STDERR "NOT FOUND $key..".ref($remote_file)."\n";
	warn Dumper $remote_file;
	return;
}

sub _should_sync {
    my ( $self, $remote_file, $local_file ) = @_;
    my $loc_pathfile = $local_file->to_string;
    die "Not implemented" if $self->{force};
    die "NO LOCAL FILE" if ! $loc_pathfile ;

    my $date_time_parser = DateTime::Format::RFC3339->new();

    my ($loc_size,$loc_mod)  = ( stat($loc_pathfile ) )[7,9];
    my $rem_mod = $date_time_parser->parse_datetime( _get_rem_value($remote_file,'modifiedDate') )->epoch();
	return 'ok' if -d $loc_pathfile ;
	my $rffs = _get_rem_value($remote_file,'fileSize'); #object or hash
	return 'down' if ! defined $loc_mod;
	my $filedata = $self->db->query('select * from files_state where loc_pathfile = ?',$loc_pathfile )->hash;

	my $loc_md5_hex;

    if (! keys %$filedata) {
        # file exists in remote and local but not registered in sqlite cache

        for my $r( $self->db->query('select * from files_state where loc_pathfile like ?',substr($loc_pathfile ,0, 4).'%')->hashes->each ) {
            next if !$r;
            say $r if ref $r ne 'HASH';
            #say join('#', grep{$_} map{$self->_utf8ifing($_)} grep {$_} values %$r) ;
        }
        # die "No data cached data for $loc_pathfile";
        say "insert cache $loc_pathfile ";
        my $loc_md5_hex = md5_hex($self->_utf8ifing($loc_pathfile) );
        $self->db->query('insert into files_state(loc_pathfile, loc_size, loc_mod_epoch, loc_md5_hex
            , rem_file_id,   rem_filename, rem_mod_epoch, rem_md5_hex, act_epoch, act_action)
            VALUES(?,?,?,?,?, ?,?,?,?,?)'
            ,$loc_pathfile , $loc_size, $loc_mod, $loc_md5_hex, _get_rem_value($remote_file,'id'), $self->_decode_remote_string(_get_rem_value($remote_file,'title')), $rem_mod , _get_rem_value($remote_file,'md5Checksum'), time, 'registered'
        );
        $filedata = {loc_pathfile=>$loc_pathfile  , loc_size=>$loc_size, loc_mod_epoch=>$loc_mod, loc_md5_hex=>$loc_md5_hex,
            , _get_rem_value($remote_file,'id'), rem_filename =>$self->_decode_remote_string(_get_rem_value($remote_file,'title')), rem_mod_epoch=>$rem_mod, rem_md5_hex=>_get_rem_value($remote_file,'md5Checksum') ,
             act_epoch=>time, 'registered'};
    } else {
        # filter looping changes (Changes done by downloading)
        if ($filedata->{act_action} && $filedata->{act_action} =~/down|up/ && $loc_mod < $self->last_end_run_time && $filedata->{act_epoch} < $self->last_end_run_time && $self->last_end_run_time > $self->old_time) {
            return 'ok';
        }
    }

    if (! $loc_mod || ! $loc_size) {
        warn "File does not exists $loc_pathfile ".($loc_mod//'__UNDEF__').'  '. ($loc_size//'__UNDEF__');
    }


    # File not changed on disk
    if ( $loc_size == ($filedata->{loc_size}//-1) && $loc_mod == ($filedata->{loc_mod_epoch}//-1) ) {
    	$loc_md5_hex = $filedata->{loc_md5_hex}//md5_hex(path($local_file)->slurp);
    } else {
        printf "File changes on disk .%s$loc_size == %s && %s == %s, %s \n", $loc_size,($filedata->{loc_size}//-1),$loc_mod,($filedata->{loc_mod_epoch}//-1),($filedata->{loc_pathfile}//'__UNDEF__');
        say "calc md5 for changed file ". $local_file->to_string;
    	$loc_md5_hex = md5_hex(path($local_file)->slurp);
    }

	# filediffer up or down?
    if ( ($loc_md5_hex//-1) eq (_get_rem_value($remote_file,'md5Checksum')//-1) ) {
    	say "Equal md5 ok" ;
    	if (! defined $loc_md5_hex) {
    		$self->db->query('delete from files_state where loc_filepath = ?', $local_file->to_string);
    		return 'cleanup';
    	}
    	my ($act_epoch, $act_action) = (0,'register');

         my $tmp = $self->db->query('select * from files_state where loc_pathfile = ?', $loc_pathfile);
         if (ref $tmp && $tmp->{act_epoch}) {
         	$act_epoch = $tmp->{act_epoch};
         	$act_action = $tmp->{act_action};
         }
     	$self->db->query('replace into files_state ( loc_pathfile,loc_size, loc_mod_epoch, loc_tmp_md5_hex,rem_file_id,rem_md5_hex,act_epoch,act_action ) VALUES(?,?,?,?,?,?,?,?)',$loc_pathfile,$loc_size,$loc_mod,$loc_md5_hex,_get_rem_value($remote_file,'id'), _get_rem_value($remote_file,'md5Checksum'),$act_epoch,$act_action);
 		return 'ok';
    }

	#If a file is empty try to get it from other side
    say "local:$loc_mod vs remote:$rem_mod  #  $loc_md5_hex vs ".(_get_rem_value($remote_file,'md5Checksum')//-1). "  # $loc_size vs ".(_get_rem_value($remote_file,'fileSize') //-1);
    return 'ok' if   $loc_size == 0 && _get_rem_value($remote_file,'fileSize') == 0;
    return 'down' if $loc_size == 0;
    return 'up'   if _get_rem_value($remote_file,'fileSize') == 0;

    if($self->old_time>$rem_mod && $self->old_time>$loc_mod ) {
        warn "CONFLICT LOCAL VS REMOTE CHANGED AFTER LAST SYNC $loc_pathfile";
        my $conflict_bck = path($ENV{HOME},'.googledrive','conflict-removed',$loc_pathfile);
        $conflict_bck->dirname->make_path;
       	move($loc_pathfile, $conflict_bck->to_string);
       	say "LOCAL FILE MOVED TO ".decode('UTF8',$conflict_bck->to_string);
       	return 'down';
    }
    if ( -f $local_file and $rem_mod < $loc_mod ) {
        return 'up';
    } else {
        return 'down';
    }
}


#Try to fix utf8


sub _utf8ifing {
    my ($self, $malformed_utf8) = @_;
    #$malformed_utf8 =~ s/[\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]/_/;
    #$malformed_utf8=~s/Ã.+//;
	my $return;
    if ($malformed_utf8 =~ /[\xD8\xF8\FFFD]/) {
    	# no utf8 try latin1
    	$return = decode('ISO-8859-1', $malformed_utf8);
    } else {
 	    $return = decode('UTF-8', $malformed_utf8, Encode::FB_DEFAULT);
    }
    return $return;
}

######################################################################################
######################################################################################
#                                   COOMMON COE
######################################################################################
######################################################################################
sub _handle_sync{
    my ($self,$remote_file, $local_file, $folder_id) = @_;
    my $row;
    say "w $local_file  &  ". ($remote_file ? decode('UTF8', _get_rem_value($remote_file, 'title')) : '__UNDEF__').' folder_id:'.($folder_id//'__UNDEF__');
    my $s; # sync option chosed
    if (! defined $remote_file) {
    	# deleted on server try to find new remote_file_object
		my $remote_file_id = $self->_get_file_object_id_by_local_file($local_file,{dir=>0});

		$remote_file = $self->net_google_drive_simple->file_metadata($remote_file_id) if $remote_file_id;
    	# else delete
    	$row = $self->db->query('select * from files_state where loc_pathfile =?', $local_file->to_string)->hash;
    	if (! defined $remote_file) {
    		if( $row && $row->{rem_file_id}) {
		    	say decode('UTF8',"unlink $local_file");
		    	# $local_file->remove;
	 	   		return;
	 	   	} else {
	 	   		say "Should uploade. New file ".decode('UTF8',$local_file);
	 	 		$s='up';
	 	   	}
 	   	}
    }
#    if (ref $remote_file eq 'HASH') {
#    	 my $tmp = $self->net_google_drive_simple->data_factory($remote_file);
#    	 $remote_file =$tmp if (ref $tmp); #success
#    }

    #say Dumper $remote_file;
    my $remote_file_size = $remote_file ? _get_rem_value( $remote_file, 'fileSize') : undef;
    my $loc_pathfile = $local_file->to_string;
    print 'x ',$self->_utf8ifing($loc_pathfile),"\n";
    die "NO LOCAL FILE" if ! $loc_pathfile;
    $s ||= $self->_should_sync( $remote_file, $local_file );
    my ($loc_size, $loc_mod) = (stat($loc_pathfile))[7,9];
    if ( $s eq 'down' ) {
        return if ($remote_file_size//0) == 0;
        #atomic download
        print "$loc_pathfile ..downloading\n";
        my $tmpfile = "/tmp/"._get_rem_value($remote_file,'md5Checksum');
        $self->net_google_drive_simple->download( $remote_file, $tmpfile );
        if (-s $tmpfile) {
			if (! -e $local_file->dirname) {
				$local_file->dirname->make_path;
			}
            move($tmpfile, $loc_pathfile);
			 if (-f $loc_pathfile) {
 	            say "success download $loc_pathfile";
			 } else {
			 	die "ERROR DOWNLOAD $loc_pathfile";
			 }
        } else {
        	say "ERROR: file not found or empty $tmpfile";
            $self->db->query('replace into files_state (loc_pathfile,loc_size,act_epoch,act_action,rem_file_id,rem_md5_hex)
            	VALUES(?,?,?,?,?,?)',$loc_pathfile,0,time,'abort download of empty or none existing file'
            	, _get_rem_value( $remote_file, 'id'),_get_rem_value( $remote_file, 'md5Checksum'));
            return;
#            die "download error $tmpfile." .Dumper $remote_file;
        }
#		die Dumper $remote_file if ref $remote_file eq 'HASH';
        my $ps = _get_rem_value($remote_file,'parents');
        die "Not a array" . Dumper $ps if ! ref $ps eq 'ARRAY';
        my $rem_parent_id;
        $rem_parent_id  = $ps->[0]->{id};
        die Dumper $rem_parent_id if ref $rem_parent_id;
        $self->db->query('replace into files_state (loc_pathfile,loc_size,loc_mod_epoch,loc_md5_hex,
        rem_file_id, rem_parent_id, rem_md5_hex,
        act_epoch,act_action)
            VALUES (?,?,?,?,?,?,?,?,?)',$loc_pathfile,$loc_size,$loc_mod,_get_rem_value($remote_file,'md5Checksum'),
            _get_rem_value($remote_file,'id'),$rem_parent_id,_get_rem_value($remote_file,'md5Checksum'),
            time,'download');
    } elsif ( $s eq 'up' && $loc_size>0 ) {
        print "$loc_pathfile ..uploading\n";
        say "Folder_id set to ".($folder_id//-1);
        my $md5_hex = md5_hex($loc_pathfile);
        die Dumper $remote_file if ref $remote_file eq 'HASH';
		if (!$folder_id && $remote_file && $remote_file->can('parents')) {
			my $p = $remote_file->parents;
			if (@$p >1) {
				die "MANY PARENTS DO NOT WHICH TO CHOOSE"
			} elsif (@$p == 1) {
				$folder_id = $p->[0]->{id};
			}
		}

        if (! $folder_id) {
        	my $num_fold_local_root = @{$self->local_root->to_array};
        	my @tmp = @$local_file[$num_fold_local_root .. $#$local_file];
			my $rem_file = path('/',@tmp);
			say "REMOTEFILE.".$rem_file.'-'.join(',',@tmp).'-'.$num_fold_local_root;
            $folder_id = $self->remote_make_path($rem_file->dirname);# find or make remote folder

        }
        say "Folder_id set to $folder_id";
        die "folder_id is not a scalar\n" . Dumper $folder_id  if ref $folder_id;
        die "$local_file no +$folder_id" if ! $folder_id;

       	my $rem_file_id;
       	if ($remote_file) {
            $rem_file_id = $self->net_google_drive_simple->file_upload( $loc_pathfile, $folder_id, _get_rem_value($remote_file,'id') );
        } else {
        	$rem_file_id = $self->net_google_drive_simple->file_upload( $loc_pathfile, $folder_id);
        }
        print "$_;" for( $loc_pathfile,$loc_size,$loc_mod, $md5_hex,
            ,$folder_id, $md5_hex, time,'upload');
        print "\n\n";
        if ($rem_file_id) {
         	$self->db->query('replace into files_state (loc_pathfile,loc_size,loc_mod_epoch,loc_md5_hex, rem_file_id, rem_parent_id, rem_md5_hex, act_epoch,act_action)
             VALUES (?,?,?,?,?,?,?,?,?)',$loc_pathfile,$loc_size,$loc_mod, $md5_hex,
             , $rem_file_id,$folder_id, $md5_hex,
             time,'upload');
        }
    } elsif ( $s eq 'ok' ) {
        print $loc_pathfile," ..ok\n";
        my ($act_epoch, $act_action) = (0,'register');
        my $tmp = $self->db->query('select * from files_state where loc_pathfile = ?', $loc_pathfile);
        if (ref $tmp && $tmp->{act_epoch}) {
        	$act_epoch = $tmp->{act_epoch};
        	$act_action = $tmp->{act_action};
        }
       	$self->db->query('replace into files_state (loc_pathfile,loc_size,loc_mod_epoch,rem_file_id,rem_md5_hex,act_epoch,act_action) VALUES(?,?,?,?,?,?,?)'
            ,$loc_pathfile,$loc_size,$loc_mod,_get_rem_value($remote_file,'id'),_get_rem_value($remote_file,'md5Checksum'),$act_epoch, $act_action);
    } elsif ($s eq 'cleanup') {
    #
    } else {
        ...;
    }

}

sub _get_file_object_id_by_local_file {
    my ($self, $local_file,$args) = @_;
    die"Expect Mojo::File $local_file: ".ref $local_file  if  ref $local_file ne 'Mojo::File';
    die"Expect Mojo::File local_root".ref $self->local_root  if ref $self->local_root ne 'Mojo::File';
        my $parent_lockup = 0;
    $parent_lockup =1 if (defined $args && $args->{dir});
    my @path =();
    my $start = @{$self->local_root};
    my $end = @{$local_file->to_array} - 1 - $parent_lockup;
    for my $i($start .. $end) {
    	push(@path, $local_file->[$i]);
    }
   warn "ERROR: Could not find remote path for ".$local_file if ! @path;
    my $remote_path = path(@path);
    my @ids = $self->path_resolveu(encode('UTF8','/').$remote_path->to_string);
	return $ids[$parent_lockup]; # root is the last one
}

# _decode_remote_string
# Get takes string from "remote" like title and decod it.
sub _decode_remote_string {
	my $self = shift;
	my $rstring = shift;
    die $rstring if ! utf8::decode($rstring);
	return $rstring;
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
    my $new_delta_sync_epoch = time;
    my %lc = map { my @s = stat($_);$_=>{is_folder =>(-d $_), size => $s[7], mod => $s[9]} } map { $_->to_string } grep {defined $_} path( "$local_root" )->list_tree({dont_use_nlink=>1})->each;
    my $tmpc = $self->db->query('select * from files_state')->hashes->to_array;
    my %cache=();
    for my $r(@$tmpc) {
        die Dumper $r if !exists $r->{loc_pathfile};
        if (! $lc{$r->{loc_pathfile}}) {	# file only in db not locally
	        if ($self->delete_to eq 'local') {
	        	# TODO: Delete row if not exists
	        	$self->db->query('delete from files_state where loc_pathfile =?', $r->{loc_pathfile});
	        	next;
	        } elsif ($self->delete_to eq 'both') {
	        	...
	        	# prepare for deletion on remote
	        } else {
	        	die "Wrong delete_to option ".$self->delete_to;
	        }
        }
        my $lfn =  $r->{loc_pathfile};
        $cache{$lfn} = $r;
    }
    for my $lc_pathfile (keys %lc) {
        if ($lc{$lc_pathfile}{mod}>$self->new_time) {
            # probably changed by this script. Replicate next run.
            delete $lc{$lc_pathfile};
            next;
        }
        printf encode('UTF8','%s %s != %s || %s != %s'."\n"),decode('UTF8',$lc_pathfile), ($lc{$lc_pathfile}{size}//-1)
            ,($cache{$lc_pathfile}{loc_size}//-1),($lc{$lc_pathfile}{mod}//-1),($cache{$lc_pathfile}{loc_mod_epoch}//-1)
            if $ENV{NMS_DEBUG};
        say Dumper $cache{$lc_pathfile} if (! exists $cache{$lc_pathfile}{loc_size} || ! defined $cache{$lc_pathfile}{loc_size}) && $ENV{NMS_DEBUG};
        if (! defined $lc{$lc_pathfile}{size}) {
            warn $lc_pathfile . Dumper $lc{$lc_pathfile};
            die;
        }
        if (!keys %cache || ! exists $cache{$lc_pathfile} || ! $cache{$lc_pathfile} ) {
            $lc{$lc_pathfile}{sync} = 1;
        }
        elsif ($lc{$lc_pathfile}{size} != ($cache{$lc_pathfile}{loc_size}//0) || $lc{$lc_pathfile}{mod} != ($cache{$lc_pathfile}{loc_mod_epoch}//0) ) {
            $lc{$lc_pathfile}{sync} = 1;
        }
        else {
            $lc{$lc_pathfile}{sync} = 0;
        }
    }
    say "\nSTART PROCESS CHANGES REMOTE " . $self->_timeused;
    my $gd=$self->net_google_drive_simple;
	my @remote_changed_obj;
	my $page = 0;
	my $lastnum=-1;
    while ($page<20) {
	    my $rem_chg_objects = $gd->search({ maxResults => 10000 },{page =>$page},sprintf("trashed = false and mimeType != 'application/vnd.google-apps.folder' and modifiedDate > '%s' and modifiedDate < '%s'", $dt->format_datetime( DateTime->from_epoch(epoch=>$self->old_time)), $dt->format_datetime( DateTime->from_epoch(epoch=>$self->new_time)))  );
	    last if scalar(@$rem_chg_objects) == $lastnum; # guess same result as last query
	    push @remote_changed_obj,@$rem_chg_objects;
	    last if scalar(@$rem_chg_objects) <100;
	    $lastnum = scalar(@$rem_chg_objects);
	    say "$page: $lastnum";
	    $page++;
	}
	@remote_changed_obj = grep { _get_rem_vallue($_,'kind') eq 'drive#file' } @remote_changed_obj;
    say "Changed remote ". scalar @remote_changed_obj;
    if ($ENV{NMS_DEBUG}) {
	    say $_ for sort map{_get_rem_value($_,'title')} @remote_changed_obj;
    }

    # process changes

    # from remote to local
    for my $rem_object (@remote_changed_obj) {
    	next if ! _get_rem_value($rem_object,'downloadUrl'); # ignore google documents
        say "Remote ".$self->_decode_remote_string(_get_rem_value($rem_object,'title'));
        #se på å slå opp i cache før construct
        my $lf_name = $self->local_construct_path($rem_object);
        my $local_file = path($lf_name);
        #TODO $self->db->query(); replace into files_state (rem_file_id,loc_pathfile,rem_md5_hex)
        my $sync = $self->_should_sync($rem_object, $local_file);
        $self->_handle_sync($rem_object, $local_file) if $sync;
    }

    # from local to remote
    say "\nSTART PROCESS CHANGES LOCAL " . $self->_timeused;
    for my $key (keys %lc) {
        next if ! exists $lc{$key}{sync};
        next if ! $lc{$key}{sync};
        my $remote_file_id = $self->_get_file_object_id_by_local_file(path($key));
        my $rem_object;
        $rem_object = $self->net_google_drive_simple->file_metadata($remote_file_id) if $remote_file_id;
        #_get_remote_metadata_from_local_filename($key);
        $rem_object = undef if ref $rem_object eq 'ARRAY' && @$rem_object == 0;
        $rem_object = $self->net_google_drive_simple->data_factory($rem_object) if ref $rem_object eq 'HASH';
    	next if $rem_object && ref $rem_object && ! $rem_object->can('downloadUrl'); # ignore google documents
		my $local_file = path($key);
        $self->_handle_sync($rem_object, $local_file) if  $lc{$key}{sync};
    }
}




=head2 local_construct_path

Ensure the local path exists

=cut

sub local_construct_path {
    my $self = shift;
    my $rem_object = shift;
    my $i =0;
    my $parent_id = _get_rem_value($rem_object,'parents')->[0]->{id};
    my @r=$self->_decode_remote_string(_get_rem_value($rem_object,'title'));

    while (1) {
        $i++;
        last if !$parent_id || $parent_id eq 'root';

        die if ! defined $rem_object;
        #say $i.' '.join('/',@r).' '.$parent_id;
        $rem_object = $self->net_google_drive_simple->file_metadata($parent_id);
              last if ! $rem_object->{parents}->[0]->{id};
        unshift @r, $self->_decode_remote_string($rem_object->{title});
        my $ps = $rem_object->{parents};
        if (ref $ps eq 'ARRAY') {
            $parent_id = $ps->[0]->{id};
        } else {
            die Dumper $rem_object;
        }
        die "Endless loop" if $i>20;

        #$rem_object = $ros;
    }
    return Mojo::File->new($self->local_root, @r);
}


=head2 path_resolveu

Reimplementation of Net::Google::Drive::Simple::path_resolve
Fill in with undef if not found.

=cut

###########################################
sub path_resolveu {
###########################################
    my( $self, $path, $search_opts ) = @_;

    $search_opts = {} if !defined $search_opts;

    my @parts = split '/', $path;
    my @ids   = ();
    my $parent = $parts[0] = $self->remote_root_ID;
#    DEBUG "Parent: $parent";

    my $folder_id = shift @parts;
    push @ids, $folder_id;

    PART: for my $part ( @parts ) {

 #       DEBUG "Looking up part $part (folder_id=$folder_id)";
		if (! defined $folder_id) {
			unshift @ids, undef;
			next;
		}
#		my $tmp = $self->net_google_drive_simple->file_metadata($folder_id);
		say "part ".decode('UTF-8',$part) .($folder_id//'__UNDEF__');#. Dumper $tmp;
        my $children = $self->net_google_drive_simple->children_by_folder_id( $folder_id,
          { maxResults    => 100, # path resolution maxResults is different
          },
          { %$search_opts, title => $part },
        );

        if( ! defined $children ) {
            unshift @ids, undef;
            next;
        }

        for my $child ( @$children ) {
#            DEBUG "Found child ", $child->title();
			next if ! defined $child;
            if( _get_rem_value($child,'title') eq $part ) {
                $folder_id = $child->id();
                unshift @ids, $folder_id;
                $parent = $folder_id;
 #               DEBUG "Parent: $parent";
                next PART;
            }
        }

		#not found if got here
       unshift @ids, undef;

#        my $msg = "Child $part not found";
#        $self->error( $msg );
#        ERROR $msg;
#        return undef;
    }

    if( @ids == 1 ) {
          # parent of root is undef
        return( undef, @ids );
    }

    return( @ids );
}







1;

__END__


=head1 AUTHOR

Altered by Stein Hammer C<steihamm@gmail.com>

=head1 COPYRIGHT AND LICENSE

This module is a fork of the CPAN module Net::Google::Drive::LocalSync 0.053

Copyright (C) 2014 by :m)

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
