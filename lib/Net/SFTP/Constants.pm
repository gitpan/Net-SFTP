# $Id: Constants.pm,v 1.4 2001/05/14 07:27:00 btrott Exp $

package Net::SFTP::Constants;
use strict;

use vars qw( %CONSTANTS );
%CONSTANTS = (
    'SSH2_FXP_INIT' => 1,
    'SSH2_FXP_VERSION' => 2,
    'SSH2_FXP_OPEN' => 3,
    'SSH2_FXP_CLOSE' => 4,
    'SSH2_FXP_READ' => 5,
    'SSH2_FXP_WRITE' => 6,
    'SSH2_FXP_LSTAT' => 7,
    'SSH2_FXP_FSTAT' => 8,
    'SSH2_FXP_SETSTAT' => 9,
    'SSH2_FXP_FSETSTAT' => 10,
    'SSH2_FXP_OPENDIR' => 11,
    'SSH2_FXP_READDIR' => 12,
    'SSH2_FXP_REMOVE' => 13,
    'SSH2_FXP_MKDIR' => 14,
    'SSH2_FXP_RMDIR' => 15,
    'SSH2_FXP_REALPATH' => 16,
    'SSH2_FXP_STAT' => 17,
    'SSH2_FXP_RENAME' => 18,
    'SSH2_FXP_STATUS' => 101,
    'SSH2_FXP_HANDLE' => 102,
    'SSH2_FXP_DATA' => 103,
    'SSH2_FXP_NAME' => 104,
    'SSH2_FXP_ATTRS' => 105,

    'SSH2_FXF_READ' => 0x01,
    'SSH2_FXF_WRITE' => 0x02,
    'SSH2_FXF_APPEND' => 0x04,
    'SSH2_FXF_CREAT' => 0x08,
    'SSH2_FXF_TRUNC' => 0x10,
    'SSH2_FXF_EXCL' => 0x20,

    'SSH2_FX_OK' => 0,
    'SSH2_FX_EOF' => 1,
    'SSH2_FX_NO_SUCH_FILE' => 2,
    'SSH2_FX_PERMISSION_DENIED' => 3,
    'SSH2_FX_FAILURE' => 4,
    'SSH2_FX_BAD_MESSAGE' => 5,
    'SSH2_FX_NO_CONNECTION' => 6,
    'SSH2_FX_CONNECTION_LOST' => 7,
    'SSH2_FX_OP_UNSUPPORTED' => 8,

    'SSH2_FILEXFER_ATTR_SIZE' => 0x01,
    'SSH2_FILEXFER_ATTR_UIDGID' => 0x02,
    'SSH2_FILEXFER_ATTR_PERMISSIONS' => 0x04,
    'SSH2_FILEXFER_ATTR_ACMODTIME' => 0x08,
    'SSH2_FILEXFER_ATTR_EXTENDED' => 0x80000000,

    'SSH2_FILEXFER_VERSION' => 3,
);

use vars qw( %TAGS );
my %RULES = (
    '^SSH2_FXP'    => 'fxp',
    '^SSH2_FXF'    => 'flags',
    '^SSH2_FILEXFER_ATTR' => 'att',
    '^SSH2_FX_' => 'status',
);

for my $re (keys %RULES) {
    @{ $TAGS{ $RULES{$re} } } = grep /$re/, keys %CONSTANTS;
}

sub import {
    my $class = shift;

    my @to_export;
    my @args = @_;
    for my $item (@args) {
        push @to_export,
            $item =~ s/^:// ? @{ $TAGS{$item} } : $item;
    }

    no strict 'refs';
    my $pkg = caller;
    for my $con (@to_export) {
        warn __PACKAGE__, " does not export the constant '$con'"
            unless exists $CONSTANTS{$con};
        *{"${pkg}::$con"} = sub () { $CONSTANTS{$con} }
    }
}

1;
