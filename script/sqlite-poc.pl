#!/usr/bin/env perl
use Mojo::Base -strict;
use Mojo::SQLite;
use Mojo::Home;
use Mojo::File 'path';
use Digest::MD5 'md5_hex';
use Encode 'decode';

my $local_root = path($ENV{HOME},'googledrive');
my $dbfile  = $ENV{HOME}.'/.googledrive/files_state.db';
say $dbfile;
die "MISSING DBFILE".$dbfile if ! -f $dbfile;
my $sql = Mojo::SQLite->new()->from_filename($dbfile);
my $db = $sql->db;
# Migrate to latest version if necessary
my $path = Mojo::Home->new->child('migrations', 'files_state.sql');
$sql->auto_migrate(2)->migrations->name('files_state')->from_file("$path");

# get list of localfiles:
my %lc = map { $_ => -d $_ } map {decode('UTF-8', $_->to_string)} $local_root->list_tree({dont_use_nlink=>1,dir=>1})->each;
for my $pathfile (keys %lc) {
	say 'start '.$pathfile;
	my ($filesize,$filemod) = (stat($pathfile))[7,9];
	my $filedata = $db->query('select * from files_state where filepath = ?',$pathfile)->hash;
	if (! keys %$filedata) {
		my $md5 = md5_hex($pathfile);
		$db->query('insert into files_state(loc_pathfile, loc_size, loc_mod_epoch,md5hex) VALUES(?,?,?,?)',$pathfile,
		$filesize,$filemod, $md5);
		say "NEW FILE ". $pathfile;
	}
	if ($filesize == $filedata->{loc_size} && $filemod == $filedata->{loc_mod_epoch}) {
		say "OK ". $pathfile;
	}
	die "File change".$pathfile ;
}
