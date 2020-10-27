package Test::UserAgent;
use Mojo::Base -base, -signatures;
use Data::Dumper;
use Test::UserAgent::Transaction;

=head1 NAME

Test::UserAgent - Dropping mocked useragent for dropping for Mojo::UserAgent

=head1 SYNOPSIS

    my $ua = Test::UserAgent->new( config_file => 't/data/some-api.yml' );

=head1 DESCRIPTION

For unittest without accessing external apis.


=head1 ATTRIBUTES

=cut

has 'config_file';

=head1 METHODS

=head2 get

=cut

sub get($self,@) {
    return Test::UserAgent::Transaction->new(method=>'GET',config_file=> $self->config_file,@_);
}

=head2 post

=cut

sub post($self,@) {
    return Test::UserAgent::Transaction->new(method=>'POST',config_file=> $self->config_file,@_);
}


=head2 AUTOLOAD

=cut

1;