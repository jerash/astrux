#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

#http://search.cpan.org/~egor/Protocol-OSC-0.03/lib/Protocol/OSC.pod#Dispatching
use Protocol::OSC;
use IO::Socket::INET;

use AnyEvent;
use AnyEvent::Socket;

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

#------------TCP socket--from nama-----------
# { my $is_connected;
# my $port = 8989;
# sub start_remote_listener {
#     #my $port = shift;
#     print ("Starting remote control listener on port $port\n");
#     $project->{remote_control_socket} = IO::Socket::INET->new( 
#         LocalAddr   => 'localhost',
#         LocalPort   => $port, 
#         Proto       => 'tcp',
#         Type        => SOCK_STREAM,
#         Listen      => 1,
#         Reuse       => 1) || die $!;
#     start_remote_watcher();
# }
# sub start_remote_watcher {
#     print ("Creating remote watcher\n");
#     $project->{events}->{remote_control} = AE::io(
#         $project->{remote_control_socket}, 0, \&process_remote_command )
# }
# sub remove_remote_watcher {
#     undef $project->{events}->{remote_control};
# }
# sub process_remote_command {
# 	print "...commandreceived\n";
#     if ( ! $is_connected++ ){
#         print ("making connection");
#         $project->{remote_control_socket} =
#             $project->{remote_control_socket}->accept();
# 		remove_remote_watcher();
#         $project->{events}->{remote_control} = AE::io(
#             $project->{remote_control_socket}, 0, \&process_remote_command );
#     }
#     my $input;
#     eval {     
#         $project->{remote_control_socket}->recv($input, $project->{remote_control_socket}->sockopt(SO_RCVBUF));
#     };
#     $@ and throw("caught error: $@, resetting..."), reset_remote_control_socket(), return;
# 	#process_command($input);
# 	#TODO
# 	print "Will process command : $input";
# 	my $out;
# 	{ no warnings 'uninitialized';
# 		# $out = $text->{eval_result} . "\n";
# 	}
#     eval {
#         #$project->{remote_control_socket}->send($out);
#         $project->{remote_control_socket}->send("ok");
#     };
#     $@ and throw("caught error: $@, resetting..."), reset_remote_control_socket(), return;
# }
# sub reset_remote_control_socket { 
#     undef $is_connected;
#     undef $@;
#     $project->{remote_control_socket}->shutdown(2);
#     undef $project->{remote_control_socket};
#     remove_remote_watcher();
# 	start_remote_listener($port);
# }
# }
#-------------------

#OSC
my $oscport = 9000;
print ("Starting OSC listener on port $oscport\n");
my $osc_in = $project->{osc_socket} = IO::Socket::INET->new( qw(LocalAddr localhost LocalPort), $oscport, qw(Proto udp Type), SOCK_DGRAM ) || die $!;
$project->{events}->{osc} = AE::io( $osc_in, 0, \&process_osc_command );
$project->{osc} = Protocol::OSC->new;

sub process_osc_command {
	print "in process osc\n";
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

#tcp socket
my $tcpport = 8989;
print ("Starting TCP server on port $tcpport\n");
# a simple tcp server
   tcp_server undef, $tcpport, sub {
      my ($fh, $host, $port) = @_;

      #syswrite $fh, "The internet is full, $host:$port. Go away!\015\012";
      syswrite $fh, "Nono no!";
      print $fh "XXXXXX";
   };

print Dumper $project;
#main loop
my $cv = AE::cv;
$cv->recv;


