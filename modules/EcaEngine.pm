#!/usr/bin/perl

package EcaEngine;

use strict;
use warnings;

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

#--------------------ENGINE FILE---------------------------------------
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
	my $port = $ecaengine->{port};
	my $ps = qx(ps ax);
	# print "***\n $ps \n***\n";
	($ps =~ /ecasound/ and $ps =~ /--server/ and $ps =~ /tcp-port=$port/) ? return 1 : return 0;
}

sub tcp_send {
	#send a tcp message to the engine
	my $ecaengine = shift;
	my $command = shift;
	#get answer
	my $reply = qx(echo $command | nc localhost $ecaengine->{port} -C);
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

sub LoadFromFile {
	my $ecaengine = shift;
	my $file = shift;
	
	return $ecaengine->SendCmdGetReply("cs-load $file");
}
sub LoadAndStart {
	my $ecaengine = shift;
	my $file = shift;

	return $ecaengine->SendCmdGetReply("cs-load $ecaengine->{ecsfile}");
	return $ecaengine->SendCmdGetReply("cs-connect");
	return $ecaengine->SendCmdGetReply("engine-launch"); #maybe not necessary with start after?
	return $ecaengine->SendCmdGetReply("start");
}
sub LoadAndStartFromFile {
	my $ecaengine = shift;
	my $file = shift;

	return $ecaengine->SendCmdGetReply("cs-load $file");
	return $ecaengine->SendCmdGetReply("cs-connect");
	return $ecaengine->SendCmdGetReply("engine-launch"); #maybe not necessary with start after?
	return $ecaengine->SendCmdGetReply("start");
}
sub SelectAndConnectChainsetup {
	my $ecaengine = shift;
	my $chainsetup = shift;

	return $ecaengine->SendCmdGetReply("cs-select $chainsetup");
	return $ecaengine->SendCmdGetReply("cs-connect");
	return $ecaengine->SendCmdGetReply("engine-launch"); #maybe not necessary with start after?
}
sub Status {
	my $ecaengine = shift;	
	return $ecaengine->SendCmdGetReply("cs-status");
}

#--------------------COMMUNICATION 2---------------------------------------
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
	#send command
	$ecaengine->{socket}->send("$cmd\r\n");
	my $buf;
	# get socket reply
	my $result = $ecaengine->{socket}->recv($buf, 65536);
	defined $result or warn "no answer from ecasound\n", return;
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
	if(	! $return_value == 256 ){
		warn "Net-ECI bad return value: $return_value (expected 256)";
		return;
	}
	$reply =~ s/\s+$//; 
	if( $type eq 'e')
	{
		warn "ECI error! Command: $cmd Reply: $reply";
		return;
	}
	else
	#return reply text
	{ 	#print "Net-ECI command ok\n";
		return $reply;
		#print $reply;
	}
	
}

1;