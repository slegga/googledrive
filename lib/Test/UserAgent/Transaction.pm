package Test::UserAgent::Transaction;
use Mojo::Base -base, -signatures;
use Test::UserAgent::Transaction::Response;
=head1 NAME

Test::UserAgent::Transaction - Test object;

=head1 SYNOPSIS

    my $tx = $ua->res->body;

=head1 DESCRIPTION

Simulate Transaction object.

=head1 ATRIBUTES

=cut

has 'config_file';

=head1 METHODS


=head2 body

=cut

sub res($self) {
    return Test::UserAgent::Transaction::Response->new(config_file => $self->config_file);
}

=head2 code
=cut

sub req($self) {
    ...;
}
1;