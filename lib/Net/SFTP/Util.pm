# $Id: Util.pm,v 1.1 2001/05/14 07:24:12 btrott Exp $

package Net::SFTP::Util;
use strict;

use Net::SFTP::Constants qw( :status );

use vars qw( @ISA @EXPORT_OK );
@ISA = qw( Exporter );
@EXPORT_OK = qw( fx2txt );

use vars qw( %ERRORS );
%ERRORS = (
    SSH2_FX_OK() => "No error",
    SSH2_FX_EOF() => "End of file",
    SSH2_FX_NO_SUCH_FILE() => "No such file or directory",
    SSH2_FX_PERMISSION_DENIED() => "Permission denied",
    SSH2_FX_FAILURE() => "Failure",
    SSH2_FX_BAD_MESSAGE() => "Bad message",
    SSH2_FX_NO_CONNECTION() => "No connection",
    SSH2_FX_CONNECTION_LOST() => "Connection lost",
    SSH2_FX_OP_UNSUPPORTED() => "Operation unsupported",
);

sub fx2txt { exists $ERRORS{$_[0]} ? $ERRORS{$_[0]} : "Unknown status" }

1;
