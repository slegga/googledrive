use Test::More;
use lib '.';
use Mojo::Base -strict;
use FindBin;
use Mojo::File 'path';
use Data::Printer;
use Data::Dumper;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";
use Net::Google::Drive::Simple::LocalSync;
use Mock::GoogleDrive;
use Mojo::SQLite;
use Mojo::File 'path';

use File::Spec::Functions 'catfile';
use File::Temp;
use Mojo::SQLite;
my $tempdir = File::Temp->newdir; # Deleted when object goes out of scope
my $tempfile = catfile $tempdir, 'test.db';
my $sql = Mojo::SQLite->new->from_filename($tempfile);
#my $testdbname = 't/data/temp-sqlite.db';

# TEST FULL

`rm -r t/local/*`;
`rm -r t/remote/*`;
`echo local-file >t/local/local-file.txt`;
`echo remote-file >t/remote/remote-file.txt`;

#my $sqlfile = Mojo::File->tempfile(DIR=>'/tmp');
#my $sql = Mojo::SQLite->new()->from_filename($sqlfile->to_string);

$sql->migrations->from_file('migrations/files_state.sql')->migrate;

#$sql->auto_migrate(1)->migrations->name('files_state')->from_data;
my $home = path('t/local');


{
    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root => path('/'),
        local_root  => $home,
        net_google_drive_simple => Mock::GoogleDrive->new,
        sqlite =>      $sql,
        lockfile =>     '/tmp/t-mirror.t.lck',
    );
    ok(1,'ok');
    $google_docs->mirror('full');
    ok (-f 't/remote/local-file.txt','local file is uploaded');
    ok (-f 't/local/remote-file.txt','remote file is downloaded');
}

# TEST DELTA
`rm -r t/local/local-file.txt`;
`rm -r t/remote/remote-file.txt`;
`mkdir t/local/local`;
`echo local-file >t/local/local/local-file.txt`;
`mkdir t/remote/remote`;
`echo remote-file >t/remote/remote/remote-file.txt`;
sleep 1;
#undef($google_docs);
    #read directory structure again after changes
{
    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root => path('/'),
        local_root  => $home,
        net_google_drive_simple => Mock::GoogleDrive->new,
        sqlite =>      $sql,
        lockfile =>     '/tmp/t-mirror.t.lck',
        );
    ok(1,'ok');
    $google_docs->mirror('delta');
    ok (! -f 't/remote/remote-file.txt','Local file is deleted when delete on remote');
    ok (-f 't/remote/local-file.txt','remote file is kept when deleted local');
    ok (-f 't/remote/local/local-file.txt','local file is uploaded');


    ok (-f 't/local/remote/remote-file.txt','remote file is downloaded');
    is ($sql->db->query('select count(*) from files_state')->array->[0],3,'Rows is kept between runs');
    is ($sql->db->query('select rem_file_id from files_state group by rem_file_id having count(*)>1')->array,undef,'No duplcate file_id');
		my $res =    $sql->db->query('select * from files_state')->hashes->to_array;
    diag Dumper $res;
#    is ($sql->db->query('select count(*) from replication_state_int')->array->[0],2,'Rows is kept between runs');
}

# PULL TEST AFTER FILE CHANGE REMOTE
`echo local-file >t/local/local-pull.txt`;
`echo remote-file >t/remote/remote-pull.txt`;

{
    #read directory structure again after changes
    is ($sql->db->query('select count(*) from files_state')->array->[0],3,'Rows is kept between runs');
    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root => path('/'),
        local_root  => $home,
        net_google_drive_simple => Mock::GoogleDrive->new,
        sqlite =>      $sql,
        lockfile =>     '/tmp/t-mirror.t.lck',
    );
    $google_docs->mirror('pull');
    ok (! -f 't/remote/local-pull.txt','Local file is not uploaded');
    ok (-f 't/local/remote-pull.txt','remote file is downloaded');
    is ($sql->db->query('select rem_file_id from files_state group by rem_file_id having count(*)>1')->array,undef,'No duplcate file_id');

}

sleep 1; #sleep both before and after file change

# PUSH TEST AFTER FILE CHANGE AND NEW FILE
diag 'PUSH';
`echo changed-file > t/remote/remote-push.txt`;
`echo changed-file > t/local/remote-pull.txt`;
`echo new-file > t/local/new-file.txt`;
sleep 1;

{
    #read directory structure again after changes
	$DB::single=2;
    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root => path('/'),
        local_root  => $home,
        net_google_drive_simple => Mock::GoogleDrive->new,
        sqlite =>      $sql,
        lockfile =>     '/tmp/t-mirror.t.lck',
    );
    $google_docs->mirror('push');
    is (path('t/remote/remote-pull.txt')->slurp, "changed-file\n",'Changed file is uploaded (remote-pull.txt)');
    ok (-f 't/local/new-file.txt','New file is pushed');
    ok (! -f 't/local/remote-push.txt','New file on remote is not download while push');
    is ($sql->db->query('select rem_file_id from files_state group by rem_file_id having count(*)>1')->array,undef,'No duplcate file_id');

}

# FULL TEST IF ALSO LOCAL IS CLEANED UP

diag 'FULL';
sleep 1;
#`echo changed-file > t/remote/remote-push.txt`;
#`echo changed-file > t/local/remote-pull.txt`;
#`echo new-file > t/local/new-file.txt`;

{
    #read directory structure again after changes
    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root => path('/'),
        local_root  => $home,
        net_google_drive_simple => Mock::GoogleDrive->new,
        sqlite =>      $sql,
        lockfile =>     '/tmp/t-mirror.t.lck',
    );
    $google_docs->mirror('full');
    my @locals =  sort map{substr($_,length('t/local'))} @{ path('t/local')->list_tree->to_array };
    my @remotes = sort map{substr($_,length('t/remote'))}@{path('t/remote')->list_tree->to_array };
	is_deeply(\@locals,\@remotes);
	is ($sql->db->query('select rem_file_id from files_state group by rem_file_id having count(*)>1')->array,undef,'No duplcate file_id');

	# tree t to see diff
}

# BOTH NEW
# TEST FULL

`rm -r t/local/*`;
`rm -r t/remote/*`;
`echo -n local-change >t/local/both-new.txt`;
`echo -n remote-change >t/remote/both-new.txt`;

#my $sqlfile = Mojo::File->tempfile(DIR=>'/tmp');
#my $sql = Mojo::SQLite->new()->from_filename($sqlfile->to_string);

$sql->migrations->from_file('migrations/files_state.sql')->migrate;

#$sql->auto_migrate(1)->migrations->name('files_state')->from_data;

{
    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root => path('/'),
        local_root  => $home,
        net_google_drive_simple => Mock::GoogleDrive->new,
        sqlite =>      $sql,
        lockfile =>     '/tmp/t-mirror.t.lck',
    );
    ok(1,'ok');
    $google_docs->mirror('full');
    ok (-f 't/remote/both-new.txt','local file is uploaded');
    ok (-f 't/local/both-new.txt','remote file is downloaded');
    is( path('t/remote/both-new.txt')->slurp,'remote-change');
    is( path('t/local/both-new.txt')->slurp,'remote-change');
}

# LOCAL CHANGE
sleep 1;
`echo -n local-change >t/local/both-new.txt`;

{
    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root => path('/'),
        local_root  => $home,
        net_google_drive_simple => Mock::GoogleDrive->new,
        sqlite =>      $sql,
        lockfile =>     '/tmp/t-mirror.t.lck',
    );
    ok(1,'ok');
    $google_docs->mirror('full');
    ok (-f 't/remote/both-new.txt','local file is uploaded');
    ok (-f 't/local/both-new.txt','remote file is downloaded');
    is( path('t/remote/both-new.txt')->slurp,'local-change');
    is( path('t/local/both-new.txt')->slurp,'local-change');
}

done_testing();
