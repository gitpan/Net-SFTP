# $Id: test.pl,v 1.1 2001/05/13 23:14:07 btrott Exp $

my $loaded;
BEGIN { print "1..1\n" }
use Net::SFTP;
$loaded++;
print "ok 1\n";
END { print "not ok 1\n" unless $loaded }
