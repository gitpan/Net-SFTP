# $Id: Attributes.pm,v 1.3 2001/05/14 06:36:01 btrott Exp $

package Net::SFTP::Attributes;
use strict;

use Net::SFTP::Constants qw( :att );
use Net::SFTP::Buffer;

use vars qw( @FIELDS );
@FIELDS = qw( flags size uid gid perm atime mtime );

for my $f (@FIELDS) {
    no strict 'refs';
    *$f = sub {
        my $a = shift;
        $a->{$f} = shift if @_;
        $a->{$f};
    };
}

sub new {
    my $class = shift;
    my $a = bless { }, $class;
    $a->init(@_);
}

sub init {
    my $a = shift;
    my %param = @_;
    for my $f (@FIELDS) {
        $a->{$f} = 0;
    }
    if (my $stat = $param{Stat}) {
        $a->{flags} |= SSH2_FILEXFER_ATTR_SIZE;
        $a->{size} = $stat->[7];
        $a->{flags} |= SSH2_FILEXFER_ATTR_UIDGID;
        $a->{uid} = $stat->[4];
        $a->{gid} = $stat->[5];
        $a->{flags} |= SSH2_FILEXFER_ATTR_PERMISSIONS;
        $a->{perm} = $stat->[2];
        $a->{flags} |= SSH2_FILEXFER_ATTR_ACMODTIME;
        $a->{atime} = $stat->[8];
        $a->{mtime} = $stat->[9];
    }
    elsif (my $buf = $param{Buffer}) {
        $a->{flags} = $buf->get_int32;
        if ($a->{flags} & SSH2_FILEXFER_ATTR_SIZE) {
            $a->{size} = $buf->get_int64;
        }
        if ($a->{flags} & SSH2_FILEXFER_ATTR_UIDGID) {
            $a->{uid} = $buf->get_int32;
            $a->{gid} = $buf->get_int32;
        }
        if ($a->{flags} & SSH2_FILEXFER_ATTR_PERMISSIONS) {
            $a->{perm} = $buf->get_int32;
        }
        if ($a->{flags} & SSH2_FILEXFER_ATTR_ACMODTIME) {
            $a->{atime} = $buf->get_int32;
            $a->{mtime} = $buf->get_int32;
        }
    }
    $a;
}

sub as_buffer {
    my $a = shift;
    my $buf = Net::SFTP::Buffer->new;
    $buf->put_int32($a->{flags});
    if ($a->{flags} & SSH2_FILEXFER_ATTR_SIZE) {
        $buf->put_int64(int $a->{size});
    }
    if ($a->{flags} & SSH2_FILEXFER_ATTR_UIDGID) {
        $buf->put_int32($a->{uid});
        $buf->put_int32($a->{gid});
    }
    if ($a->{flags} & SSH2_FILEXFER_ATTR_PERMISSIONS) {
        $buf->put_int32($a->{perm});
    }
    if ($a->{flags} & SSH2_FILEXFER_ATTR_ACMODTIME) {
        $buf->put_int32($a->{atime});
        $buf->put_int32($a->{mtime});
    }
    $buf;
}

1;
