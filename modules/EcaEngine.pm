#!/usr/bin/perl

package EcaEngine;

use strict;
use warnings;

my $debug = 0;

#--------------------OBJECT---------------------------------------
sub create {
	#create the file (overwrite)
	my $ecaengine = shift;

	#get path to file
	my $path = $ecaengine->{ecsfile};
	#print "---EcaEngine:create\n path = $path\n";
	die "no path to create ecs file\n" unless (defined $path);
	#create an empty file (overwrite existing)
	open my $handle, ">$path" or die $!;
	#update mixer status
	$ecaengine->{status} = "new";
	#close file
	close $handle;
}
sub add_header {
	my $ecaengine = shift;

	my $name = $ecaengine->{name};
	my $header = "#GENERAL\n";
	$header .= "-b:".$ecaengine->{buffersize} if $ecaengine->{buffersize};
	$header .= " -r:".$ecaengine->{realtime} if $ecaengine->{realtime};
	my @zoptions = split(",",$ecaengine->{z});
	foreach (@zoptions) {
		$header .= " -z:".$_;
	}
	$header .= " -n:\"$name\"";
	$header .= " -z:mixmode,".$ecaengine->{mixmode} if $ecaengine->{mixmode};
	$header .= " -G:jack,$name,notransport" if ($ecaengine->{jack_sync} == 0);
	$header .= " -G:jack,$name,sendrecv" if ($ecaengine->{jack_sync});
	$header .= " -Md:".$ecaengine->{midi_port} if $ecaengine->{midi_port};
	#add to tructure
	$ecaengine->{header} = $header;
	#update status
	$ecaengine->{status} = "header";
}

#--------------------ENGINE FILE---------------------------------------
sub CreateEcsFile {
	my $ecaengine = shift;
	my $ecsfilepath = shift;

	#add path to ecasound info
	$ecaengine->{ecsfile} = $ecsfilepath;
	#create the file
	$ecaengine->create;
	#add ecasound header to file
	$ecaengine->build_header;
	#get chains from structure
	$ecaengine->get_ecasoundchains;
	#add chains to file
	$ecaengine->add_chains;
	#TODO verify is the generated file can be opened by ecasound
	#$ecaengine->verify;
}
sub build_header {
	my $ecaengine = shift;

	#print "--EcaEngine:build_header\n header = $header\n";
	die "ecs file has not been created" if ($ecaengine->{status} eq "notcreated");
	#open file handle
	open my $handle, ">>$ecaengine->{ecsfile}" or die $!;
	#append to file
	print $handle $ecaengine->{header} or die $!;
	#close file
	close $handle or die $!;
	#update status
	$ecaengine->{status} = "header";
}
sub get_ecasoundchains {
	my $ecaengine = shift;

	my @table;

	if (defined $ecaengine->{i_chains}) {
		push @table , "\n#INPUTS\n";
		push @table , @{$ecaengine->{i_chains}};
		delete $ecaengine->{i_chains};
	}
	if (defined $ecaengine->{o_chains}) {
		push @table , "\n#OUTPUTS\n";
		push @table , @{$ecaengine->{o_chains}};
		delete $ecaengine->{o_chains};
	}
	if (defined $ecaengine->{x_chains}) {
		push @table , "\n#CHANNELS ROUTING\n";
		push @table , @{$ecaengine->{x_chains}};
		delete $ecaengine->{x_chains};
	}
	if (defined $ecaengine->{io_chains}) {
		push @table , "\n#PLAYERS\n";
		push @table , @{$ecaengine->{io_chains}};
		delete $ecaengine->{io_chains};
	}

	#update structure
	@{$ecaengine->{all_chains}} = @table;
}
sub add_chains {
	my $ecaengine = shift;

	#open file in add mode
	open my $handle, ">>$ecaengine->{ecsfile}" or die $!;
	#append to file
	print $handle "$_\n" for @{$ecaengine->{all_chains}};
	#close file
	close $handle or die $!;
	#update status
	$ecaengine->{status} = "created";
}

sub verify {
	#check if chainsetup file is valid
	my $ecaengine = shift;
	unless ($ecaengine->{status} eq "created") {
		warn "cannot verify an ecs file not containing chains\n";
		return;
	}
	#TODO if possible open it with ecasound and check return code

	$ecaengine->{status} = "verified";
}

#--------------------STATUS---------------------------------------
sub is_ready {
	#check if chainsetup is connected and engine launched
	my $ecaengine = shift;
	#send the question
	return unless my @lines = $ecaengine->tcp_send("cs-status");
	my $line = shift @lines; #drop next line (### Chainsetup status ###)
	#verify the line
	$line = shift @lines; #here it is (Chainsetup (1) "main" [selected] [connected])
	my $enginename = $ecaengine->{name};
	return 1 if ($line =~ m/\"$enginename\" \[selected\] \[connected\]/);
	return 0;
}
sub is_running {
	#check if an ecasound engine is running on the engine's defined port
	my $ecaengine = shift;
	my $port = $ecaengine->{tcp_port};
	my $ps = qx(ps ax);
	# print "***\n $ps \n***\n";
	($ps =~ /ecasound/ and $ps =~ /--server/ and $ps =~ /tcp-port=$port/) ? return 1 : return 0;
}

sub tcp_send {
	#send a tcp message to the engine
	my $ecaengine = shift;
	my $command = shift;
	#get answer
	my $reply = qx(echo $command | nc localhost $ecaengine->{tcp_port} -C);
	return reply_is_ok($reply);
}
sub reply_is_ok { #verify if there is an error mentioned, drop the first line, returns an array of lines
	my $reply = shift;
	#do we have a reply ?
	return unless defined $reply;
	#transform reply into array (256 nbytes errorcode)
	my @lines = split "\n" , $reply;
	#read first line
	my $line = shift @lines;
	return unless defined $line;
	my ($dummy,$bytes,$errorcode) = split " ",$line;
	#check for error message
	return if $errorcode eq "e"; #error
	#send back ecasound reply line if they are
	return @lines if @lines;
	#else return 1
	return 1;
}

#--------------------COMMUNICATION---------------------------------------
sub init_socket {
	my $ecaengine = shift;	
	my $port = shift;
	print ("   Creating engine socket on port $port.\n");
	$ecaengine->{socket} = new IO::Socket::INET (
		PeerAddr => 'localhost', 
		PeerPort => $port, 
		Proto => 'tcp', 
	); 
	die "Could not create socket: $!\n" unless $ecaengine->{socket}; 
}

sub SendCmdGetReply {
	my $ecaengine = shift;	
	my $cmd = shift;
	
	$cmd =~ s/\s*$//s; # remove trailing white space

	#verify if socket is active (after a reload for example)
	return unless $ecaengine->{socket};

	print "sending message \"$cmd\" to mixer $ecaengine->{name} using socket $ecaengine->{socket}\n" if $debug;

	#send command
	$ecaengine->{socket}->send("$cmd\r\n");
	my $buf;
	# get socket reply
	my $result = $ecaengine->{socket}->recv($buf, 65536);
	defined $result or return "no answer from ecasound";
	#parse reply
	my ($return_value, $setup_length, $type, $reply) =
		$buf =~ /(\d+)# digits
				 \    # space
				 (\d+)# digits
				 \    # space
 				 ([^\r\n]+) # a line of text, probably one character 
				\r\n    # newline
				(.+)  # rest of string
				/sx;  # s-flag: . matches newline
	#check for errors
	if (!defined $return_value) {
		return "no answer from ecasound engine";
		#TODO try to restart ecasound ?
	}
	if(	$return_value != 256 ){
		$reply = "Net-ECI bad return value: $return_value (expected 256)";
		return;
	}
	if( $type eq 'e')
	{
		$reply = "ECI error! Command: $cmd Reply: $reply";
		return $reply;
	}
	else
	#return reply text
	{ 	#print "Net-ECI command ok\n";
		return $reply;
		#print $reply;
	}
	
}

#--------------------FUNCTIONS---------------------------------------

sub LoadFromFile {
	my $ecaengine = shift;
	my $file = shift;
	
	return $ecaengine->SendCmdGetReply("cs-load $file");
}
sub LoadAndStart {
	my $ecaengine = shift;
	my $file = shift;

	my $reply = $ecaengine->SendCmdGetReply("cs-load $ecaengine->{ecsfile}");
	$reply .= $ecaengine->SendCmdGetReply("cs-connect");
	$reply .= $ecaengine->SendCmdGetReply("engine-launch"); #maybe not necessary with start after?
	$reply .= $ecaengine->SendCmdGetReply("start");
	return $reply;
}
sub LoadAndStartFromFile {
	my $ecaengine = shift;
	my $file = shift;

	my $reply = $ecaengine->SendCmdGetReply("cs-load $file");
	$reply .= $ecaengine->SendCmdGetReply("cs-connect");
	$reply .= $ecaengine->SendCmdGetReply("engine-launch"); #maybe not necessary with start after?
	$reply .= $ecaengine->SendCmdGetReply("start");
	return $reply;
}
sub SelectAndConnectChainsetup {
	my $ecaengine = shift;
	my $chainsetup = shift;

	my $reply = $ecaengine->SendCmdGetReply("cs-select $chainsetup");
	$reply .= $ecaengine->SendCmdGetReply("cs-connect");
	$reply .= $ecaengine->SendCmdGetReply("engine-launch"); #maybe not necessary with start after?
	return $reply;
}
sub Status {
	my $ecaengine = shift;	
	return $ecaengine->SendCmdGetReply("cs-status");
}
sub get_selected_chainsetup {
	my $ecaengine = shift;
	return $ecaengine->SendCmdGetReply("cs-selected");
}
sub get_selected_channel {
	my $ecaengine = shift;
	return $ecaengine->SendCmdGetReply("c-selected");
}
sub get_selected_effect {
	my $ecaengine = shift;
	return $ecaengine->SendCmdGetReply("cop-selected");
}

#--------------Live functions-------------------------
sub mute_channel {
	my $ecaengine = shift;
	my $trackname = shift;
	print "----muting $trackname on $ecaengine received\n" if $debug;
	
	#TODO when we're moved to OSC remember to update the bus trackname ...
	#$trackname = "bus_$trackname" if $mixer->{channels}{$trackname}->is_hardware_out;
	
	#c-muting no reply, toggle
	$ecaengine->SendCmdGetReply("c-select $trackname");
	$ecaengine->SendCmdGetReply("c-muting");
}

sub udpate_trackfx_value {
	my $ecaengine = shift;
	my $trackname = shift;
	my $position = shift;
	my $index = shift;
	my $value = shift;

	#TODO when we're moved to OSC remember to update the bus trackname ...
	#$trackname = "bus_$trackname" if $mixer->{channels}{$trackname}->is_hardware_out;

	#TODO do something with message returns ?
	$ecaengine->SendCmdGetReply("c-select $trackname");
	$ecaengine->SendCmdGetReply("cop-select $position");
	$ecaengine->SendCmdGetReply("copp-select $index");
	$ecaengine->SendCmdGetReply("copp-set $value");
}

sub udpate_auxroutefx_value {
	my $ecaengine = shift;
	my $trackname = shift;
	my $destination = shift;
	my $position = shift;
	my $index = shift;
	my $value = shift;

	my $chain = "$trackname"."_to_"."$destination";

	#TODO do something with message returns ?
	$ecaengine->SendCmdGetReply("c-select $chain");
	$ecaengine->SendCmdGetReply("cop-set $position,$index,$value");
}

1;