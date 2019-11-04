package Mojo::File::Role::UTF8;
use Mojo::Base -role;
use Encode;

=head1 NAME

Mojo::File::Role::UTF8

=head1 DESCRIPTION

Add method for output string as decoded utf8.

=head2 to_string_utf8

Decode the string from Mojo::File to utf8.
So printing will be right.

=cut

sub to_string_utf8 {
    my $self = shift;
    my $string = $self->to_string;
    #
#    my $return =  decode('UTF-8', $string, Encode::FB_DEFAULT);
    #$return =~ s/\x{E000}-\x{FFFD}/_/g;
    return $string;
    #return decode(encode('UTF-8', $octets, Encode::FB_CROAK);
}

1;
