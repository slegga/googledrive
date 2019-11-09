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
my $testdbname = 't/data/temp-sqlite.db';

unlink($testdbname) if -f $testdbname;

my $sql = Mojo::SQLite->new($testdbname);

$sql->migrations->from_file('migrations/files_state.sql')->migrate;


#$sql4->auto_migrate(1)->migrations->name('files_state')->from_data;

my $home = path('t/local');
# requires a ~/.google-drive.yml file containing an access token,
# see documentation of Net::Google::Drive::Simple


my $google_docs = Net::Google::Drive::Simple::LocalSync->new(
    remote_root => path('/'),
    local_root  => $home,
    net_google_drive_simple => Mock::GoogleDrive->new,
    dbfile => $testdbname,
);
ok(1,'ok');
$google_docs->mirror();
done_testing;