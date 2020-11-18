package Test::UserAgent::Transaction::Response;

use Mojo::Base -base,-strict,-signatures;
use Carp::Always;
use Data::Dumper;
use Mojo::JSON qw/to_json/;
use Mojo::Util qw /url_unescape/;
use Mojo::File 'path';

has 'ua';  # Test::UserAgent ?
has 'req_res';

=head1 NAME

Test::UserAgent::Transaction::Respone::GoogleDrive

=head1 SYNOPSIS

    my $ua = Test::UserAgent->new(response=>Test::UserAgent::Transaction::Respone::GoogleDrive->new);
    my $gd = Mojo::GoogleDrive::Mirror->new(ua=>$ua);

=head1 DESCRIPTION

A response mocked object for Mojo::Message::Response object.

=head1 METHODS

=head2 body

    $string = $tx->res->body:

Return response body.

=cut

sub body($self) {
    my $key='';
    for my $method(qw/method url header payload/) {
        my $k = $self->ua->$method;
        next if ! $k;
        if (! ref $k) {
            $key .= "$k¤";
        }
        elsif (ref $k eq 'HASH') {
            $key .= to_json($k).'¤';
        }
        elsif ($k->can('to_string')) {
            $key .= $k->to_string.'¤';
        }
        else {
            die "Unknown object: " . ref $k;
        }
    }

#https://www.googleapis.com/drive/v3/files/root?fields=id%2Ckind%2Cname%2CmimeType%2Cparents%2CmodifiedTime%2Ctrashed%2CexplicitlyTrashed
# POPULER REQ_RES basert på config file.
# GJØR LOOKUP OR RETUR.

#    my $ua = $self->ua;
#    warn "No valid return found. ua: ".  ref $ua;
    my $hash_ret={};
    if (lc($self->ua->method) eq 'get') {
        if ( $self->ua->url =~ m|https:\/\/www.googleapis.com\/drive\/v3\/files\/(\w+)\?fields\=(.+)|) {
            # id%2Ckind%2Cname%2CmimeType%2Cparents%2CmodifiedTime%2Ctrashed%2CexplicitlyTrashed
            my ($file_id,$fields)=($1,$2);
            if ($file_id eq 'root') {
                my $root = {id=>'/', kind=>"drive#file", name=>'Min disk', mimeType=>'application/vnd.google-apps.folder',trashed=>0,explicitlyTrashed=>0,modifiedTime=>'2013-10-19T11:06:57.289Z'};
                return to_json($root);
            #https://www.googleapis.com/drive/v3/files/?q=mimeType+%3D+%27application%2Fvnd.google-apps.folder%27+and+%27t%2Fremote%2F%27+in+parents+and+name+%3D+%27t%27
            } else {
                die "No data for GET: $file_id:   $key";
            }
        } elsif ($self->ua->url =~ m|https:\/\/www.googleapis.com\/drive\/v3\/files\/\?q\=(.+)|) {
            my $attr = url_unescape($1);
            my @a = split/\+and\+/,$attr;
            my %crit;
            for my $x (@a) {
                if (my($key,$type,$value)= $x =~/^'?(.*?)'?\+(=|in)\+'?(.*?)'?$/) {
                    if ($type eq 'in') {
                        $type = $key;
                        $key = $value;
                        $value = $type;
                        $crit{$key} = $value;
                    } elsif($type='=') {
                        $crit{$key} = $value;
                    }
                    else {
                        ...;
                    }
                } else {
                    ...;
                }
            }
#            die Dumper \%crit;
            my $allfiles = path($self->ua->real_remote_root)->list_tree({dir=>1});
            if ($crit{mimeType} && $crit{mimeType} eq 'application/vnd.google-apps.folder') {
                $allfiles = $allfiles->grep(sub{-d "$_"});
            }
            if($crit{parents}) {
                my $re = quotemeta($crit{parents});
                if ($crit{parents} eq '/') {
                    $re= quotemeta(path($self->ua->real_remote_root)->to_string).'.';
                }
                $allfiles = $allfiles->grep(sub{ "$_"=~/$re/});
            }
            if($crit{name} ) {
                $allfiles = $allfiles->grep(sub{ $_->basename eq $crit{name}});
            }
            my $root = $self->ua->real_remote_root;
            if($root =~/\/$/) {
                chop($root);
            }
            my $root_length=length($root);
            return to_json({files=>$allfiles->map(sub{$self->_metadata(substr("$_",$root_length))})->to_array});
        } else {
            die "No value for key: ".$key;
        }
    } else {
        die "Unkown method ". $self->ua->method;
    }
}

sub _metadata($self,$pathfile) {
    my $p = path($pathfile);
    my $f = path($self->ua->real_remote_root,$pathfile);
    my $return={id=>"$pathfile"||'/',name => $p->basename||'/', parents=>[path($pathfile)->dirname->to_string||'/'],trashed=>0,explicitlyTrashed=>0, modifiedTime =>'2013-10-19T11:06:57.289Z'};
    if(-d "$f") {
        $return->{mimeType} = 'application/vnd.google-apps.folder';
    }
    return $return;
}

=head2 code

    $httpcode = $tx->res->code:

Return response code.

=cut


sub code($self) {
#    for my $key(qw/config_file method url header payload/) {
#        print $key .":  ".($self->ua->$key//'__UMDEF__') . "  " if defined $self->ua->can($key);
#    }
    return 200;
}


1;
