#!/usr/bin/env perl

use Mojo::File 'path';

my $lib;
BEGIN {
    my $gitdir = Mojo::File->curfile;
    my @cats = @$gitdir;
    while (my $cd = pop @cats) {
        if ($cd eq 'git') {
            $gitdir = path(@cats,'git');
            last;
        }
    }
    $lib =  $gitdir->child('utilities-perl','lib')->to_string;
};
use lib $lib;
use SH::UseLib;
use SH::ScriptX;
use Mojo::Base 'SH::ScriptX';
use open qw(:std :utf8);
use Net::Google::Drive::Simple;
use Clone 'clone';

#use Carp::Always;

=encoding utf8

=head1 NAME

delete-remote.pl - Delete or move remote files.

=head1 SYNOPSIS

    cd ~/googledrive
    delete-remot.pl path/file

=head1 DESCRIPTION

Delete or remove remote files. Script delete given file remote and locally and update no_delta_before value so other clients is forced to do a full update next time. This should stop the file to reoccur after file is deleted remote.

=cut

option 'dryrun!', 'Print to screen instead of doing changes';

has net_google_drive_simple => sub {Net::Google::Drive::Simple->new()};
has local_root  => sub{
    my $home = path($ENV{HOME});
    $home->child('googledrive');
};

sub force_full_update_next {
    my $self = shift;
    my $datafile = $self->local_root->child('Apps','googledrive.yml');
    my $tmp = $datafile->slurp;
    my @cont = split(/\n/, $tmp);
    for my $i (0 .. $#cont) {
        if ($cont[$i] =~/^no_delta_before\:/) {
            $cont[$i] = 'no_delta_before: ' . time;
        }
        $cont[$i].="\n";
    }
    $datafile->spurt(@cont);
    my $rfile = $self->pathlocal2remote($datafile);
#    say "$rfile";
    my ($fileid,$dirid,@ids) = $self->net_google_drive_simple->path_resolve("$rfile");
    die if ! $dirid;
#    say join('*',$fileid,$dirid,@ids);
    $self->net_google_drive_simple->file_upload( "$datafile", $dirid, $fileid );

    # TODO: force push $datafile;
}

sub pathlocal2remote {
    my ( $self, $mflpath ) = @_;
    my @fileparts = @{ $mflpath->to_array };
#    say join(':',@fileparts);
    for my $i ( @{ $self->local_root->to_array }) {
        shift @fileparts;
    }
#    say join(':',@fileparts);
    return Mojo::File->new('/',@fileparts);
}

sub main {
    my $self = shift;
    my @e = @{ $self->extra_options };
    my $curpath = path;
    my $do_force_full_update = 0;
#    $self->force_full_update_next;
    for my $finput (@e) {
        my @files;
        if ($finput !~ /^\// && $finput !~ /\*/) {
            @files=  ($curpath->child($finput) );
        } elsif($finput =~ /^\// && $finput !~ /\*/) {
            @files= (path($finput));
        } else {
            warn $finput;
            ...;
        }

        # verify and handle delete

        for my $f(@files) {
            if (-d $f) {
                die "Dir is not empty $f" if $f->list({dir=>1})->each;
            }
            die "File $f does not exists" if ! -e $f;
            my $r = '^' . $self->local_root->to_string;
            die "Not in $ENV{HOME}/googledrive $f" if $f !~ /$r/;
            my $rfile = $self->pathlocal2remote($f);
            my ($fileid,$dirid,@ids) = $self->net_google_drive_simple->path_resolve("$rfile");
            if (! $fileid) {
                warn "No file id for $rfile"
            } else {
                $do_force_full_update=1;
                $self->net_google_drive_simple->file_delete( $fileid );
            }
            unlink "$f";
        }
    }
    $self->force_full_update_next if $do_force_full_update;

}

__PACKAGE__->new(options_cfg=>{extra=>1})->main();
