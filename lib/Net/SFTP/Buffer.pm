# $Id: Buffer.pm,v 1.2 2001/05/14 06:36:01 btrott Exp $

package Net::SFTP::Buffer;
use strict;

use Net::SSH::Perl::Buffer qw( SSH2 );
use base qw( Net::SSH::Perl::Buffer );

use Net::SSH::Perl::Util qw( :ssh2mp );

sub get_int64 {
    my $buf = shift;
    my $off = defined $_[0] ? shift : $buf->{offest};
    $buf->{offset} += 8;
    bin2mp( $buf->bytes($off, 8) );
}

sub put_int64 {
    my $buf = shift;
    $buf->{buf} .= mp2bin($_[0], 8);
}

sub get_attributes {
    my $buf = shift;
    Net::SFTP::Attributes->new(Buffer => $buf);
}

sub put_attributes {
    my $buf = shift;
    $buf->{buf} .= $_[0]->as_buffer->bytes;
}

1;
