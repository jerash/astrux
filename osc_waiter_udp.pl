#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

#http://search.cpan.org/~egor/Protocol-OSC-0.03/lib/Protocol/OSC.pod#Dispatching
use Protocol::OSC;
use IO::Socket::INET;

use AnyEvent;

# sub start_osc_listener {
# 	my $port = shift;
# 	pager_newline("Starting OSC listener on port $port");
# 	my $in = $project->{osc_socket} = IO::Socket::INET->new( qw(LocalAddr localhost LocalPort), $port, qw(Proto tcp Type), SOCK_STREAM, qw(Listen 1 Reuse 1) ) || die $!;
# 	$this_engine->{events}->{osc} = AE::io( $in, 0, \&process_osc_command );
# 	$project->{osc} = Protocol::OSC->new;
# }

# sub process_osc_command {
# 	my $in = $project->{osc_socket};
# 	my $osc = $project->{osc};
#  	$in->accept->recv(my $packet, $in->sockopt(SO_RCVBUF));
#     my $p = $osc->parse(($osc->from_stream($packet))[0]);
# 	#say "got OSC: ", Dumper $p;
# 	my $input = $p->[0];
# 	$input =~ s(/)( )g;
# 	process_command(sanitize_remote_input($input));
# }
my $project;

#autoflush
$| = 1;


my $port = 8989;

print ("Starting OSC listener on port $port");
my $in = $project->{osc_socket} = IO::Socket::INET->new( qw(LocalAddr localhost LocalPort), $port, qw(Proto udp Type), SOCK_DGRAM ) || die $!;
$project->{events}->{osc} = AE::io( $in, 0, \&process_osc_command );
$project->{osc} = Protocol::OSC->new;


sub process_osc_command {
	print "in process\n";
	my $in = $project->{osc_socket};
	my $osc = $project->{osc};
	
	$in->recv(my $packet, $in->sockopt(SO_RCVBUF));
    my $p = $osc->parse($packet);

	#say "got OSC: ", Dumper $p;
	my $input = $p->[0];
	my $type = $p->[1];
	my $value = $p->[2];
	print "OSC==$p p0=$input p1=$type p2=$value\n";
}

my $cv = AE::cv;
$cv->recv;