use Mojo::File 'path';
use Test::More;
use Mojo::Base -strict;
use FindBin;
use Data::Dumper;
use utf8;
use Encode qw'decode encode';

sub utf {
	return encode('UTF-8',shift);
}
my $utf8 = utf('æøå');
is(path($utf8,$utf8.'.txt')->to_string, "$utf8/$utf8.txt");
# path($FindBin::Bin,'utf8')->to_string;
my @list = path($FindBin::Bin,'utf8')->list->each;
#die Dumper \@list;
is($list[0]->to_string,$ENV{HOME}.encode('UTF-8','/git/googledrive/t/utf8/æøå.txt'));
done_testing;
