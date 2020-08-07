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
    }
    $datafile->spurt(@cont);
    my $file = clone $datafile;
    for my $i ( @{ $self->local_root }) {
        shift @$file;
    }
    my @ids = $self->net_google_drive_simple->path_resolve("$file");
    $self->net_google_drive_simple->file_upload( $datafile, $ids[-2], $ids[-1] );

    # TODO: force push $datafile;
}

sub main {
    my $self = shift;
    my @e = @{ $self->extra_options };
    my $curpath = path;
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
        $self->force_full_update_next;
        for my $f(@files) {
            ... if -d $f;
            die "Not a file $f" if ! -f $f;
            my $r = '^' . $self->local_root->to_string;
            die "Not in $ENV{HOME}/googledrive $f" if $f !~ /$r/;
            my @ids = $self->net_google_drive_simple->path_resolve("$f");
            say "$self->net_google_drive_simple->file_delete( $ids[-1] )";
            say 'unlink "$f" '.$f;
        }
        $self->force_full_update_next;
    }

}

__PACKAGE__->new(options_cfg=>{extra=>1})->main();
