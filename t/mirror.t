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

#my $testdbname = 't/data/temp-sqlite.db';

# TEST FULL

`rm -r t/local/*`;
`rm -r t/remote/*`;
`echo local-file >t/local/local-file.txt`;
`echo remote-file >t/remote/remote-file.txt`;

my $sql = Mojo::SQLite->new()->from_filename(':memory:');

$sql->migrations->from_file('migrations/files_state.sql')->migrate;


#$sql4->auto_migrate(1)->migrations->name('files_state')->from_data;
my $home = path('t/local');


{
    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root => path('/'),
        local_root  => $home,
        net_google_drive_simple => Mock::GoogleDrive->new,
        sqlite =>      $sql,
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

{
    #read directory structure again after changes
    my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
        remote_root => path('/'),
        local_root  => $home,
        net_google_drive_simple => Mock::GoogleDrive->new,
        sqlite =>      $sql,
    );
    ok(1,'ok');
    $google_docs->mirror('delta');
    ok (-f 't/remote/local-file.txt','Local file is kept');
    ok (-f 't/remote/local-file.txt','remote file is kept');
    ok (-f 't/remote/local/local-file.txt','local file is uploaded');
    ok (-f 't/local/remote/remote-file.txt','remote file is downloaded');
}

# PULL TEST AFTER FILE CHANGE REMOTE

# PUSH TEST AFTER FILE CHANGE AND NEW FILE

# FULL TEST IF ALSO LOCAL IS CLEANED UP

done_testing();
