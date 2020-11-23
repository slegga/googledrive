package Test::UserAgent;
use Mojo::Base -base, -signatures;
use Data::Dumper;
use Test::UserAgent::Transaction;
use Mojo::JSON qw /to_json/;

=head1 NAME

Test::UserAgent - Dropping mocked useragent for dropping for Mojo::UserAgent

=head1 SYNOPSIS

    my $ua = Test::UserAgent->new( config_file => 't/data/some-api.yml' );

=head1 DESCRIPTION

For unittest without accessing external apis.


=head1 ATTRIBUTES

=cut

has 'real_remote_root';
has 'config_file';
has 'method';
has 'url';
has 'header';
has 'payload';
has  'metadata';

=head1 METHODS

=head2 get

=cut

sub get($self,$url,@) {
    my %params=(method=>'GET', config_file=>$self->config_file, url=>$url);
    if  (ref $url) {
        $url =$url->to_string;
    }
    shift @_;# remove self
    shift @_;# remove url
    if (@_) {
        for my $i(0 .. $#_) {
            my $v= $_[$i];
            if (ref $v eq 'HASH') {
                if ($v->{Authorization}) {
                    $v->{Authorization} = 'Bearer: X';
                }
                $params{header} = to_json($v);
            } elsif (!$v) {
                #
            } else {
                die "Unkown $i  $v  ".ref $v;
            }
        }
    }
    $self->$_($params{$_}) for keys %params;
    return Test::UserAgent::Transaction->new( ua => $self );
}

=head2 post

=cut

sub post($self,$url,@) {
    my %params=(method=>'post', config_file=>$self->config_file, url=>$url);
    if  (ref $url) {
        $url =$url->to_string;
    }
    shift @_;# remove self
    shift @_;# remove url
    my $param;
    if (@_) {
        for my $i(0 .. $#_) {
            my $v= $_[$i];
            if (ref $v eq 'HASH') {
                if ($v->{Authorization}) {
                    $v->{Authorization} = 'Bearer: X';
                }
                $params{header} = $v;
            } elsif (!$v) {
                ...;
            } elsif ($v eq 'multipart') {
              $param=$v;
            } elsif (ref $v eq 'ARRAY') {
                if ($param eq 'multipart') {
                    $self->metadata($v->[0]);
                    $self->payload($v->[1]);
                    die if exists $v->[2];
                } else {
                    warn "$param  $v";
                    ...;
                }
            } else {
                die "Unkown $i  $v  ".ref $v;
            }

        }
    }
    $self->$_($params{$_}) for keys %params;

    return Test::UserAgent::Transaction->new( ua => $self );
}


=head2 AUTOLOAD

=cut

1;
