#!/usr/bin/perl

package Live;

use strict;
use warnings;

#use Net::OpenSoundControl::Server;
use Protocol::OSC;
use IO::Socket::INET;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::ReadLine::Gnu;

use lib '/home/seijitsu/astrux/modules';
use Project;
use Mixer;
use Song;
use Bridge;

use Data::Dumper;

#-------------------------------------INIT LIVE -----------------------------------
#autoflush
$| = 1;
use vars qw($project);
#----------------------------------------------------------------
# This is the main entry point for Astrux Live
#----------------------------------------------------------------

if ($#ARGV+1 eq 0) {
	die "usage : start_project project_name.cfg\n";
}

#------------LOAD project structure----------------------------

my $infile = $ARGV[0];
print "Opening : $infile\n";

use Storable;
our $project = retrieve($infile);
die "Could not load file $infile\n" unless $project;

&Start;

#------------Now PLay !------------------------
&PlayIt;

#------------------------------------------------------------------------

sub Start {

	#TODO verify if Project is valid
	print "--------- Init Project $project->{project}{name} ---------\n";

	# copy jack plumbing file
	#-------------------------
	if ($project->{connections}{"jack.plumbing"} eq 1) {
		my $homedir = $ENV{"HOME"};
		warn "jack.plumbing already exists, file will be overwritten\n" if (-e "$homedir/.jack.plumbing");
		use File::Copy;
		copy("$project->{connections}{file}","$homedir/.jack.plumbing") or die "Copy failed: $!";
	}

	#verify that backends are active
	#---------------------------------
	
	#JACK
	my $pid_jackd = qx(pgrep jackd);
	if (!$pid_jackd) {
		print "Strange ...JACK server is not running ?? Starting it\n";
		my $command = $project->{JACK}{start};
		system ($command) if $command;
		sleep 1;
		$pid_jackd = qx(pgrep jackd);
	}
	else {
		print "JACK server running with PID $pid_jackd";
	}
	#TODO verify jack parameters
	$project->{backends}{JACK}{PID} = $pid_jackd;

	#JPMIDI << problem in server mode can't load new midi file....
	# my $pid_jpmidi = qx(pgrep jpmidi);
	# if ($project->{midi_player}{enable}) {
	# 	die "JPMIDI server is not running" unless $pid_jpmidi;
	# 	print "JPMIDI server running with PID $pid_jpmidi";
	# }
	# $project->{backends}{JPMIDI} = $pid_jpmidi;

	#SAMPLER
	my $pid_linuxsampler = qx(pgrep linuxsampler);
	if ($project->{linuxsampler}{enable}) {
		die "LINUXSAMPLER is not running" unless $pid_linuxsampler;
		print "LINUXSAMPLER running with PID $pid_linuxsampler";
	}
	$project->{backends}{LINUXSAMPLER}{PID} = $pid_linuxsampler;

	#jack.plumbing
	my $pid_jackplumbing = qx(pgrep jack.plumbing);
	if ($project->{connections}{"jack.plumbing"} eq 1) {
		die "jack.plumbing is not running" unless $pid_jackplumbing;
		print "jack.plumbing running with PID $pid_jackplumbing";
	}
	$project->{backends}{JACKPLUMBING}{PID} = $pid_jackplumbing;

	#OSC/MIDI BRIDGE
	# my $pid_osc2midibridge = qx(pgrep -f osc2midi);
	# if ($project->{osc2midi}{enable} eq 1) {
	# 	die "osc2midi bridge is not running" unless $pid_osc2midibridge;
	# 	print "osc2midi bridge running with PID $pid_osc2midibridge";
	# }
	# $project->{backends}{OSC2MIDI} = $pid_osc2midibridge;

	#a2jmidid
	my $pid_a2jmidid = qx(pgrep -f a2jmidid);
	die "alsa to jack midi bridge is not running" unless $pid_a2jmidid;
	print "a2jmidid running with PID $pid_a2jmidid";
	$project->{backends}{A2JMIDID}{PID} = $pid_a2jmidid;
	
	# get song list
	#---------------
	my @songkeys = sort keys %{$project->{songs}};
	my @songlist;
	push (@songlist,$project->{songs}{$_}{song_globals}{friendly_name}) foreach @songkeys;
	print "SONGS :\n";
	print " - $_\n" foreach @songlist;

	# start mixers
	#---------------
	print "Starting mixers\n"; 
	$project->StartEngines;

	# load song chainsetups + dummy
	#--------------------------------
	my $playersport = $project->{mixers}{players}{ecasound}{port};
	foreach my $song (@songkeys) {
		#load song chainsetup
		print "Loading song $song\n"; 
		print $project->{mixers}{players}{ecasound}->LoadFromFile($project->{songs}{$song}{ecasound}{ecsfile});
	}
	#load dummy song chainsetup
	$project->{mixers}{players}{ecasound}->SelectAndConnectChainsetup("players");

	#send previous state to ecasound engines
	#--------------------------------------
	&OSC_send("/refresh i 1");

	# now we should be back to saved state
	#--------------------------------------
}

#-------------------------MAIN LOOP---------------------------------------------

sub PlayIt {

	print "\n--------- Project $project->{project}{name} Running---------\n";
	#Start the global parser accepting many things like:
	#	tcp commands
	&init_tcp_server if $project->{TCP}{enable};
	#	OSC messages
	&init_osc_server if $project->{OSC}{enable};
	#	command line interface
	&init_cli_server if $project->{CLI}{enable};	
	#	gui actions (from tcp commands is best)
	#	front panel actions (from tcp commands)

	#main loop waiting
	my $cv = AE::cv;
	$cv->recv;
	# old static CLI
	# while (1) {
	# 	print "$project->{project}{name}> ";
	# 	my $command = <STDIN>;
	# 	chomp $command;
	# 	return if ($command =~ /exit|x|quit/);
	# 	$project->execute_command($command);
	# }
}
#-------------------------CLI---------------------------------------------
sub init_cli_server {
	my $rl; $rl = new AnyEvent::ReadLine::Gnu prompt => "$project->{project}{name}>  ", on_line => sub {
		# called for each line entered by the user
		# AnyEvent::ReadLine::Gnu->print ("you entered: $_[0]\n");
		undef $rl unless process_cli($_[0]);
 }
}
sub process_cli {
	my $command = shift;
	return if ($command =~ /exit|x|quit/);
	print $project->execute_command($command);
	return 1;
}

#-------------------------TCP---------------------------------------------
sub init_tcp_server {
	my $tcpport = $project->{TCP}{port};
	# creating a listening socket
	my $tcpsocket = new IO::Socket::INET (
	    LocalHost => '0.0.0.0',
	    LocalPort => $tcpport,
	    Proto => 'tcp',
	    Listen => 5,
	    Reuse => 1
	);
	warn "cannot create socket $!\n" unless $tcpsocket;
	print "Starting TCP listener on port $tcpport\n";
	$project->{TCP}{socket} = $tcpsocket;
 	$project->{TCP}{events} = AE::io( $tcpsocket, 0, \&process_tcp_command );
}
sub process_tcp_command {

	#TODO for persistent connection we should fork the connection and put it in a loop until clients asks to exit

    my $socket = $project->{TCP}{socket};
    # waiting for a new client connection
    my $client_socket = $socket->accept();
 
    # get information about a newly connected client
    my $client_address = $client_socket->peerhost();
    my $client_port = $client_socket->peerport();
    #print "connection from $client_address:$client_port\n";
 
    # read up to 256 characters from the connected client
    my $data = "";
    $client_socket->recv($data, 256);
    print "received data: $data\n";

    chomp($data);
	my $reply = $project->execute_command($data);

    # write response data to the connected client
    $data = "ok\n";
    $data .= " : $reply\n" if $reply;
    $client_socket->send($data);
   
    # notify client that response has been sent
    shutdown($client_socket, 1);
}
#$socket->close();

#-------------------------OSC---------------------------------------------
	#version using Protocol::OSC
sub init_osc_server {
	
	my $oscip = $project->{OSC}{ip} || 'localhost';
	my $oscport = $project->{OSC}{inport} || '8000';
	print ("Starting OSC listener on port $oscport\n");
	#init socket on osc port
	my $osc_in = $project->{OSC}{socket} = IO::Socket::INET->new(
		LocalAddr => $oscip, #default is localhost
		LocalPort => $oscport,
		Proto	  => 'udp',
		Type	  =>  SOCK_DGRAM) || die $!;
	warn "cannot create socket $!\n" unless $osc_in;
	#create the anyevent watcher on this socket
	$project->{OSC}{events} = AE::io( $osc_in, 0, \&process_osc_command );
	#init an osc object
	$project->{OSC}{object} = Protocol::OSC->new;
}
sub process_osc_command {
use Socket qw(getnameinfo NI_NUMERICHOST);

	my $in = $project->{OSC}{socket};
	my $osc = $project->{OSC}{object};
	
	#grab the message, and get the sender
	my $sender = $in->recv(my $packet, $in->sockopt(SO_RCVBUF));
	#parse the osc packet
	my $p = $osc->parse($packet);
	#TODO deal with osc bundles
	#grab osc packet arguments
	my ($path, $types, @args) = @$p;

	# print "grabbed path=$path types=$types and args";
	# print Dumper @args;
	# print "\n";

	#verify how many arguments we have
	if ( length($types) == 0 ) {
		warn "ignored osc message without arguments\n";
		return;
	}
	elsif ( length($types) > 1 ) {
		warn "ignored osc message with multiple arguments\n";
	}

	#go on with a single argument osc message
	#cleanup path
	$path =~ s(^/)();
	$path =~ s(/$)();
	#split path elements
	my @pathelements = split '/',$path;
	#TODO verify number of elements
	#element 1 = mixername OR TODO system command
	my $mixername = shift @pathelements;
		#print " mixer $mixername\n";
	return unless exists $project->{mixers}{$mixername};
	#element 2 = trackname OR TODO system command arguments
	my $trackname = shift @pathelements;
		#print " track $trackname\n";
	return unless exists $project->{mixers}{$mixername}{channels}{$trackname};
	#element 3 = fx name OR 'aux_to' OR special command
	my $el3 = shift @pathelements;
	print " el3 $el3\n";
	if ($el3 eq 'aux_to') {
		print "track $trackname aux_to\n";
	}
	elsif (exists $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$el3} ) {
		my $insertname = $el3;
		my $insertparam = shift @pathelements;
		return unless $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$el3}->is_param_ok($insertparam);
		my $value = shift @args;
		warn "empty value on param $insertparam!\n" unless defined $value;
		print "effect $el3 change param $insertparam with value $value on track $trackname\n";
		#TODO send ecasound command
	}
	elsif ($el3 eq 'mute') {
		print "mute track $trackname\n";
	}
	else {
		warn "unknown osc parameter $el3\n";
	}

	#TODO check if we send back information
	if ($project->{OSC}{sendback}) {
		#resolve the sender adress
		my($err, $hostname, $servicename) = getnameinfo($sender, NI_NUMERICHOST);
	}
}

	#version with Net::OpenSoundControl
# sub init_osc_server {
# 	my $oscport = $project->{OSC}{inport};
# 	print ("Starting OSC listener on port $oscport\n");
# 	$project->{OSC}{object} = Net::OpenSoundControl::Server->new(
# 	      Port => $oscport, Handler => \&process_osc_command) or
# 	      die "Could not start server: $@\n";
# 	$project->{OSC}{event} = AE::io( $project->{OSC}{object}{SOCKET}, 0, \&process_osc_event );
# 	print Dumper $project->{OSC};
# }
# sub process_osc_event{
# 	my $MAXLEN = 1024;
# 	my ($msg, $host);
#     $project->{OSC}{object}{SOCKET}->recv($msg, $MAXLEN);
#     my ($port, $ipaddr) = sockaddr_in($project->{OSC}{object}{SOCKET}->peername);
#     $host = gethostbyaddr($ipaddr, AF_INET) || '';

#     $project->{OSC}{object}{HANDLER}->($host, Net::OpenSoundControl::decode($msg))
#       if defined $project->{OSC}{object}{HANDLER};

#     return if ($msg =~ /exit/);
# }
# sub process_osc_command {
# 	my ($sender, $machin) = @_;
# 	#print Dumper @_;
# 	my @message = @{$machin};
# 	# print "path=$message[0]\n";
# 	# print "type=$message[1]\n";
# 	# print "value=$message[2]\n";
# 	print Dumper @message;
# 	my $path = $message[0];
# }

	#osc send tool
sub OSC_send {
	use Protocol::OSC;
	use IO::Socket::INET;

	my $osc = Protocol::OSC->new;
	#make packet
	my $data = $osc->message(my @specs = qw(/refresh i 1));
    # or
    #use Time::HiRes 'time';
    #my $data $osc->bundle(time, [@specs], [@specs2], ...);
		
	#send
	my $udp = IO::Socket::INET->new( PeerAddr => 'localhost', PeerPort => '8000', Proto => 'udp', Type => SOCK_DGRAM) || die $!;
	$udp->send($data);	
}

1;