#!/usr/bin/perl

package EcaEngine;

use strict;
use warnings;

use Data::Dumper;

#--------------------OBJECT---------------------------------------
sub create {
	#create the file (overwrite)
	my $ecaengine = shift;

	#get path to file
	my $path = $ecaengine->{ecsfile};
	#print "---EcaEngine:create\n path = $path\n";
	die "no path to create ecs file\n" unless (defined $path);
	#create an empty file (overwrite existing)
	#TODO : check for existence and ask for action
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
	#TODO open it with ecasound and check return code

	$ecaengine->{status} = "verified";
}

#--------------------STATUS---------------------------------------
sub is_ready {
	#check if chainsetup is connected and engine launched
	my $ecaengine = shift;
	#send the question
	my $reply = $ecaengine->tcp_send("cs-status");
	my @lines =();
	return unless @lines = reply_is_ok($reply);
	my $line = shift @lines; #drop next line (### Chainsetup status ###)
	#verify the line
	$line = shift @lines; #here it is (Chainsetup (1) "main" [selected] [connected])
	my $enginename = $ecaengine->{name};
	return 1 if ($line =~ m/\"$enginename\" \[selected\] \[connected\]/);
	return 0;
}

#--------------------COMMUNICATION---------------------------------------
sub tcp_send {
	#send a tcp message to the engine
	my $ecaengine = shift;
	my $command = shift;
	#get answer
	return qx(echo $command | nc localhost $ecaengine->{port} -C);
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
	return @lines;
}

sub LoadFromFile {
	my $ecaengine = shift;
	my $file = shift;
	
	$ecaengine->tcp_send("cs-load $file");
	#TODO check return for errors
}
sub LoadAndStart {
	my $ecaengine = shift;
	my $file = shift;

	$ecaengine->tcp_send("cs-load $ecaengine->{ecsfile}");
	#TODO check return for errors
	$ecaengine->tcp_send("cs-connect");
	#TODO check return for errors
	$ecaengine->tcp_send("engine-launch"); #maybe not necessary with start after?
	#TODO,  check return for errors
	$ecaengine->tcp_send("start");
	#TODO check return for errors
}
sub LoadAndStartFromFile {
	my $ecaengine = shift;
	my $file = shift;

	$ecaengine->tcp_send("cs-load $file");
	#TODO check return for errors
	$ecaengine->tcp_send("cs-connect");
	#TODO check return for errors
	$ecaengine->tcp_send("engine-launch"); #maybe not necessary with start after?
	#TODO,  check return for errors
	$ecaengine->tcp_send("start");
	#TODO check return for errors
}
sub SelectAndConnectChainsetup {
	my $ecaengine = shift;
	my $chainsetup = shift;

	$ecaengine->tcp_send("cs-select $chainsetup");
	#TODO check return for errors
	$ecaengine->tcp_send("cs-connect");
	#TODO check return for errors
	$ecaengine->tcp_send("engine-launch"); #maybe not necessary with start after?
	#TODO,  check return for errors
}

1;