package Test::UserAgent::Transaction::Response;

use Mojo::Base -base,-strict,-signatures;

has 'config_file';

sub body($self) {
    ...;
}

sub code($self) {
    ...;
}

1;