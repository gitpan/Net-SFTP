# $Id: Makefile.PL,v 1.2 2001/05/15 06:51:37 btrott Exp $

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => 'Net::SFTP',
    DISTNAME => 'Net-SFTP',
    VERSION_FROM => 'lib/Net/SFTP.pm',
    AUTHOR => 'Benjamin Trott <ben@rhumba.pair.com>',
    ABSTRACT => 'Secure File Transfer Protocol client',
    PREREQ_PM => {
        'Net::SSH::Perl' => '1.13',
    },
);
