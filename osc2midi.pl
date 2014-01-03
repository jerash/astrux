#!/usr/bin/perl
use strict;
use warnings;

#http://search.cpan.org/~egor/Protocol-OSC-0.03/lib/Protocol/OSC.pod#Dispatching
use Protocol::OSC;
use IO::Socket::INET;

my $osc = Protocol::OSC->new;
my $port = 4000;

#create input socket
 my $in = IO::Socket::INET->new( qw(LocalAddr localhost LocalPort), $port, qw(Proto udp Type), SOCK_DGRAM ) || die $!;
 
 while (1) {
    $in->recv(my $packet, $in->sockopt(SO_RCVBUF));
    my $p = $osc->parse($packet);
	print $p->path;
	print "\n";
	print $p->type;
	print "\n";
	my $args = $p->args;
	my $arg = ($p->args)[0];
	print "$args,$arg\n";
	}
	
#	see also
# http://search.cpan.org/~crenz/Net-OpenSoundControl-0.05/lib/Net/OpenSoundControl/Server.pm