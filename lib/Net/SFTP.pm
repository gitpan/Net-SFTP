# $Id: SFTP.pm,v 1.11 2001/05/15 06:51:50 btrott Exp $

package Net::SFTP;
use strict;

use Net::SFTP::Constants qw( :fxp :flags :status :att SSH2_FILEXFER_VERSION );
use Net::SFTP::Util qw( fx2txt );
use Net::SFTP::Attributes;
use Net::SFTP::Buffer;
use Net::SSH::Perl::Constants qw( :msg2 );
use Net::SSH::Perl;

use Carp qw( croak );

use vars qw( $VERSION );
$VERSION = 0.02;

use constant COPY_SIZE => 8192;

sub new {
    my $class = shift;
    my $sftp = bless { }, $class;
    $sftp->{host} = shift;
    $sftp->init(@_);
}

sub init {
    my $sftp = shift;
    my %param = @_;
    $sftp->{debug} = delete $param{debug};
    $param{ssh_args} ||= [];

    $sftp->{_msg_id} = 0;

    my $ssh = Net::SSH::Perl->new($sftp->{host}, protocol => 2,
        debug => $sftp->{debug}, @{ $param{ssh_args} });
    $ssh->login($param{user}, $param{password});
    $sftp->{ssh} = $ssh;

    my $channel = $sftp->_open_channel;
    $sftp->{channel} = $channel;

    $sftp->send_init;

    $sftp;
}

sub _open_channel {
    my $sftp = shift;
    my $ssh = $sftp->{ssh};

    my $channel = $ssh->_session_channel;
    $channel->open;

    $channel->register_handler(SSH2_MSG_CHANNEL_OPEN_CONFIRMATION, sub {
        my($channel, $packet) = @_;
        $channel->{ssh}->debug("Sending subsystem: sftp");
        my $r_packet = $channel->request_start("subsystem", 1);
        $r_packet->put_str("sftp");
        $r_packet->send;
    });

    my $subsystem_reply = sub {
        my($channel, $packet) = @_;
        my $id = $packet->get_int32;
        if ($packet->type == SSH2_MSG_CHANNEL_FAILURE) {
            $channel->{ssh}->fatal_disconnect("Request for " .
                "subsystem 'sftp' failed on channel '$id'");
        }
        $channel->{ssh}->break_client_loop;
    };

    my $cmgr = $ssh->channel_mgr;
    $cmgr->register_handler(SSH2_MSG_CHANNEL_FAILURE, $subsystem_reply);
    $cmgr->register_handler(SSH2_MSG_CHANNEL_SUCCESS, $subsystem_reply);

    $sftp->{incoming} = Net::SFTP::Buffer->new;
    $channel->register_handler("_output_buffer", sub {
        my($channel, $buffer) = @_;
        $sftp->{incoming}->append($buffer->bytes);
        $channel->{ssh}->break_client_loop;
    });

    ## Get channel confirmation, etc. Break once we get a response
    ## to subsystem execution.
    $ssh->client_loop;

    $channel;
}

sub send_init {
    my $sftp = shift;
    my $ssh = $sftp->{ssh};

    $sftp->debug("Sending SSH2_FXP_INIT");
    my $msg = $sftp->new_msg(SSH2_FXP_INIT);
    $msg->put_int32(SSH2_FILEXFER_VERSION);
    $sftp->send_msg($msg);

    $msg = $sftp->get_msg;
    my $type = $msg->get_int8;
    if ($type != SSH2_FXP_VERSION) {
        croak "Invalid packet back from SSH2_FXP_INIT (type $type)";
    }
    my $version = $msg->get_int32;
    $sftp->debug("Remote version: $version");

    ## XXX Check for extensions.

    $sftp;
}

sub debug {
    my $sftp = shift;
    if ($sftp->{debug}) {
        $sftp->{ssh}->debug("sftp: @_");
    }
}

## Server -> client methods.

sub get_attrs {
    my $sftp = shift;
    my($expected_id) = @_;
    my $msg = $sftp->get_msg;
    my $type = $msg->get_int8;
    my $id = $msg->get_int32;
    $sftp->debug("Received stat reply T:$type I:$id");
    croak "ID mismatch ($id != $expected_id)" unless $id == $expected_id;
    if ($type == SSH2_FXP_STATUS) {
        my $status = $msg->get_int32;
        warn "Couldn't stat remote file: ", fx2txt($status);
        return;
    }
    elsif ($type != SSH2_FXP_ATTRS) {
        croak "Expected SSH2_FXP_ATTRS packet, got $type";
    }
    $msg->get_attributes;
}

sub get_status {
    my $sftp = shift;
    my($expected_id) = @_;
    my $msg = $sftp->get_msg;
    my $type = $msg->get_int8;
    my $id = $msg->get_int32;

    croak "ID mismatch ($id != $expected_id)" unless $id == $expected_id;
    if ($type != SSH2_FXP_STATUS) {
        croak "Expected SSH2_FXP_STATUS packet, got $type";
    }

    $msg->get_int32;
}

sub get_handle {
    my $sftp = shift;
    my($expected_id) = @_;

    my $msg = $sftp->get_msg;
    my $type = $msg->get_int8;
    my $id = $msg->get_int32;

    croak "ID mismatch ($id != $expected_id)" unless $id == $expected_id;
    if ($type == SSH2_FXP_STATUS) {
        my $status = $msg->get_int32;
        warn "Couldn't get handle: ", fx2txt($status);
        return;
    }
    elsif ($type != SSH2_FXP_HANDLE) {
        croak "Expected SSH2_FXP_HANDLE packet, got $type";
    }

    $msg->get_str;
}

## Client -> server methods.

sub _send_str_request {
    my $sftp = shift;
    my($code, $str) = @_;
    my($msg, $id) = $sftp->new_msg_w_id($code);
    $msg->put_str($str);
    $sftp->send_msg($msg);
    $sftp->debug("Sent message T:$code I:$id");
    $id;
}

sub _send_str_attrs_request {
    my $sftp = shift;
    my($code, $str, $a) = @_;
    my($msg, $id) = $sftp->new_msg_w_id($code);
    $msg->put_str($str);
    $msg->put_attributes($a);
    $sftp->send_msg($msg);
    $sftp->debug("Sent message T:$code I:$id");
    $id;
}

sub do_stat {
    my $sftp = shift;
    my($path) = @_;
    my $id = $sftp->_send_str_request(SSH2_FXP_STAT, $path);
    $sftp->get_attrs($id);
}

sub do_fsetstat {
    my $sftp = shift;
    my($handle, $a) = @_;
    my $id = $sftp->_send_str_attrs_request(SSH2_FXP_FSETSTAT, $handle, $a);
    my $status = $sftp->get_status($id);
    warn "Couldn't fsetstat: ", fx2txt($status)
        unless $status == SSH2_FX_OK;
    $status;
}

sub do_open {
    my $sftp = shift;
    my($path, $flags, $a) = @_;
    my($msg, $id) = $sftp->new_msg_w_id(SSH2_FXP_OPEN);
    $msg->put_str($path);
    $msg->put_int32($flags);
    $msg->put_attributes($a);
    $sftp->send_msg($msg);
    $sftp->debug("Sent SSH2_FXP_OPEN I:$id P:$path");
    $sftp->get_handle($id);
}

sub do_opendir {
    my $sftp = shift;
    my($path) = @_;
    my $id = $sftp->_send_str_request(SSH2_FXP_OPENDIR, $path);
    $sftp->get_handle($id);
}

sub do_close {
    my $sftp = shift;
    my($handle) = @_;
    my $id = $sftp->_send_str_request(SSH2_FXP_CLOSE, $handle);
    my $status = $sftp->get_status($id);
    warn "Couldn't close file: ", fx2txt($status)
        unless $status == SSH2_FX_OK;
    $status;
}

## High-level client -> server methods.

sub get {
    my $sftp = shift;
    my($remote, $local) = @_;
    my $ssh = $sftp->{ssh};

    my $a = $sftp->do_stat($remote) or return;

    local *FH;
    if ($local) {
        open FH, ">$local" or croak "Can't open $local: $!";
    }

    my $handle = $sftp->do_open($remote, SSH2_FXF_READ,
        Net::SFTP::Attributes->new);

    my $offset = 0;
    my $ret = '';
    while (1) {
        my($id, $expected_id, $msg, $type);

        ($msg, $id) = $sftp->new_msg_w_id(SSH2_FXP_READ);
        $expected_id = $id;
        $msg->put_str($handle);
        $msg->put_int64(int($offset));
        $msg->put_int32(COPY_SIZE);
        $sftp->send_msg($msg);
        $sftp->debug("Sent message SSH2_FXP_READ I:$id O:$offset");

        $msg = $sftp->get_msg;
        $type = $msg->get_int8;
        $id = $msg->get_int32;
        $sftp->debug("Received reply T:$type I:$id");
        croak "ID mismatch ($id != $expected_id)" unless $id == $expected_id;
        if ($type == SSH2_FXP_STATUS) {
            my $status = $msg->get_int32;
            if ($status == SSH2_FX_EOF) {
                last;
            }
            else {
                warn "Couldn't read from remote file: ", fx2txt($status);
                $sftp->do_close($handle);
                return;
            }
        }
        elsif ($type != SSH2_FXP_DATA) {
            croak "Expected SSH2_FXP_DATA packet, got $type";
        }

        my $data = $msg->get_str;
        my $len = length($data);
        if ($len > COPY_SIZE) {
            croak "Received more data than asked for $len > " . COPY_SIZE;
        }
        $sftp->debug("In read loop, got $len offset $offset");

        if ($local) {
            print FH $data;
        }
        else {
            $ret .= $data;
        }

        $offset += $len;
    }
    $sftp->do_close($handle);

    if ($local) {
        close FH;
        my $flags = $a->flags;
        my $mode = $flags & SSH2_FILEXFER_ATTR_PERMISSIONS ?
            $a->perm & 0777 : 0666;
        chmod $mode, $local or croak "Can't chmod $local: $!";

        if ($flags & SSH2_FILEXFER_ATTR_ACMODTIME) {
            utime $a->atime, $a->mtime, $local or
                croak "Can't utime $local: $!";
        }
    }

    $ret;
}

sub put {
    my $sftp = shift;
    my($local, $remote) = @_;
    my $ssh = $sftp->{ssh};

    local *FH;
    open FH, $local or croak "Can't open local file $local: $!";
    my $a = Net::SFTP::Attributes->new(Stat => [ stat $local ]);

    my $handle = $sftp->do_open($remote, SSH2_FXF_WRITE | SSH2_FXF_CREAT |
        SSH2_FXF_TRUNC, $a);

    my $offset = 0;
    while (1) {
        my($len, $data, $msg, $id);
        $len = read FH, $data, COPY_SIZE;
        last unless $len;

        ($msg, $id) = $sftp->new_msg_w_id(SSH2_FXP_WRITE);
        $msg->put_str($handle);
        $msg->put_int64(int($offset));
        $msg->put_str($data);
        $sftp->send_msg($msg);
        $sftp->debug("Sent message SSH2_FXP_WRITE I:$id O:$offset S:$len");

        my $status = $sftp->get_status($id);
        if ($status != SSH2_FX_OK) {
            warn "Couldn't write to remote file $remote: ", fx2txt($status);
            $sftp->do_close($handle);
            close FH;
            return;
        }
        $sftp->debug("In write loop, got $len offset $offset");

        $offset += $len;
    }

    close FH or warn "Can't close local file $local: $!";

    $sftp->do_fsetstat($handle, $a);
    $sftp->do_close($handle);
}

sub ls {
    my $sftp = shift;
    my($remote, $code) = @_;
    my @dir;
    my $handle = $sftp->do_opendir($remote);
    while (1) {
        my $expected_id = $sftp->_send_str_request(SSH2_FXP_READDIR, $handle);
        my $msg = $sftp->get_msg;
        my $type = $msg->get_int8;
        my $id = $msg->get_int32;
        $sftp->debug("Received reply T:$type I:$id");

        croak "ID mismatch ($id != $expected_id)" unless $id == $expected_id;
        if ($type == SSH2_FXP_STATUS) {
            my $status = $msg->get_int32;
            $sftp->debug("Received SSH2_FXP_STATUS $status");
            if ($status == SSH2_FX_EOF) {
                last;
            }
            else {
                warn "Couldn't read directory: ", fx2txt($status);
                $sftp->do_close($handle);
                return;
            }
        }
        elsif ($type != SSH2_FXP_NAME) {
            croak "Expected SSH2_FXP_NAME packet, got $type";
        }

        my $count = $msg->get_int32;
        last unless $count;
        $sftp->debug("Received $count SSH2_FXP_NAME responses");
        for my $i (0..$count-1) {
            my $fname = $msg->get_str;
            my $lname = $msg->get_str;
            my $a = $msg->get_attributes;
            my $rec = {
                filename => $fname,
                longname => $lname,
                a        => $a,
            };
            if ($code && ref($code) eq "CODE") {
                $code->($rec);
            }
            else {
                push @dir, $rec;
            }
        }
    }
    $sftp->do_close($handle);
    @dir;
}

## Messaging methods--messages are essentially sub-packets.

sub msg_id { $_[0]->{_msg_id}++ }

sub new_msg {
    my $sftp = shift;
    my($code) = @_;
    my $msg = Net::SFTP::Buffer->new;
    $msg->put_int8($code);
    $msg;
}

sub new_msg_w_id {
    my $sftp = shift;
    my($code, $sid) = @_;
    my $msg = $sftp->new_msg($code);
    my $id = defined $sid ? $sid : $sftp->msg_id;
    $msg->put_int32($id);
    ($msg, $id);
}

sub send_msg {
    my $sftp = shift;
    my($buf) = @_;
    my $b = Net::SFTP::Buffer->new;
    $b->put_int32($buf->length);
    $b->append($buf->bytes);
    $sftp->{channel}->send_data($b->bytes);
}

sub get_msg {
    my $sftp = shift;
    my $buf = $sftp->{incoming};
    my $len;
    unless ($buf->length > 4) {
        $sftp->{ssh}->client_loop;
        croak "Connection closed" unless $buf->length > 4;
        $len = unpack "N", $buf->bytes(0, 4, '');
        croak "Received message too long $len" if $len > 256 * 1024;
        while ($buf->length < $len) {
            $sftp->{ssh}->client_loop;
        }
    }
    my $b = Net::SFTP::Buffer->new;
    $b->append( $buf->bytes(0, $len, '') );
    $b;
}

1;
__END__

=head1 NAME

Net::SFTP - Secure File Transfer Protocol client

=head1 SYNOPSIS

    use Net::SFTP;
    my $sftp = Net::SFTP->new($host);
    $sftp->get("foo", "bar");
    $sftp->put("bar", "baz");

=head1 DESCRIPTION

I<Net::SFTP> is a pure-Perl implementation of the Secure File
Transfer Protocol (SFTP)--file transfer built on top of the
SSH protocol. I<Net::SFTP> uses I<Net::SSH::Perl> to build a
secure, encrypted tunnel through which files can be transferred
and managed. It provides a subset of the commands listed in
the SSH File Transfer Protocol IETF draft, which can be found
at I<http://www.openssh.com/txt/draft-ietf-secsh-filexfer-00.txt>.

SFTP stands for Secure File Transfer Protocol and is a method of
transferring files between machines over a secure, encrypted
connection (as opposed to regular FTP, which functions over an
insecure connection). The security in SFTP comes through its
integration with SSH, which provides an encrypted transport
layer over which the SFTP commands are executed, and over which
files can be transferred. The SFTP protocol defines a client
and a server; only the client, not the server, is implemented
in I<Net::SFTP>.

Because it is built upon SSH, SFTP inherits all of the built-in
functionality provided by I<Net::SSH::Perl>: encrypted
communications between client and server, multiple supported
authentication methods (eg. password, public key, etc.).

=head1 USAGE

=head2 Net::SFTP->new($host, %args)

Opens a new SFTP connection with a remote host I<$host>, and
returns a I<Net::SFTP> object representing that open
connection.

I<%args> can contain:

=over 4

=item * user

The username to use to log in to the remote server. This should
be your SSH login, and can be empty, in which case the username
is drawn from the user executing the process.

See the I<login> method in I<Net::SSH::Perl> for more details.

=item * password

The password to use to log in to the remote server. This should
be your SSH password, if you use password authentication in
SSH; if you use public key authentication, this argument is
unused.

See the I<login> method in I<Net::SSH::Perl> for more details.

=item * debug

If set to a true value, debugging messages will be printed out
for both the SSH and SFTP protocols. This automatically turns
on the I<debug> parameter in I<Net::SSH::Perl>.

The default is false.

=item * ssh_args

Specifies a reference to a list of named arguments that should
be given to the constructor of the I<Net::SSH::Perl> object
underlying the I<Net::SFTP> connection.

For example, you could use this to set up your authentication
identity files, to set a specific cipher for encryption, etc.

See the I<new> method in I<Net::SSH::Perl> for more details.

=back

=head2 $sftp->get($remote [, $local ])

Downloads a file I<$remote> from the remote host. If I<$local>
is specified, it is opened/created, and the contents of the
remote file I<$remote> are written to I<$local>. In addition,
its filesystem attributes (atime, mtime, permissions, etc.)
will be set to those of the remote file.

If I<$local> is not given, returns the contents of I<$remote>.

=head2 $sftp->put($local, $remote)

Uploads a file I<$local> from the local host to the remote
host, and saves it as I<$remote>.

=head2 $sftp->ls($remote [, $subref ])

Fetches a directory listing of I<$remote>.

If I<$subref> is specified, for each entry in the directory,
I<$subref> will be called and given a reference to a hash
with three keys: I<filename>, the name of the entry in the
directory listing; I<longname>, an entry in a "long" listing
like C<ls -l>; and I<a>, a I<Net::SFTP::Attributes> object,
which contains the file attributes of the entry (atime, mtime,
permissions, etc.).

If I<$subref> is not specified, returns a list of directory
entries, each of which is a reference to a hash as described
in the previous paragraph.

=head1 AUTHOR & COPYRIGHTS

Benjamin Trott, ben@rhumba.pair.com

Except where otherwise noted, Net::SFTP is Copyright
2001 Benjamin Trott. All rights reserved. Net::SFTP is free
software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut
