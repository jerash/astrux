#!/usr/bin/perl

package EcaEngine;

use strict;
use warnings;

use Data::Dumper;

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

sub tcp_send {
	#send a tcp message to the engine
	my $ecaengine = shift;
	my $command = shift;
	#get answer
	return qx(echo $command | nc localhost $ecaengine->{port} -C);
}

sub is_ready {
	#check if chainsetup is connected and engine launched
	my $ecaengine = shift;
	#send the question
	my $reply = $ecaengine->tcp_send("cs-status");
	#do we have a reply ?
	return "unknown" unless defined $reply;
	#transform line into array
	my @lines = split "\n" , $reply;
	#read first line
	my $line = shift @lines;
	return unless defined $line;
	my ($dummy,$bytes,$type) = split " ",$line;
	#check for error message
	return if $type eq "e"; #error
	$line = shift @lines; #drop next line (### Chainsetup status ###)
	#verify the line
	$line = shift @lines; #here it is (Chainsetup (1) "main" [selected] [connected])
	my $enginename = $ecaengine->{name};
	return 1 if ($line =~ m/\"$enginename\" \[selected\] \[connected\]/);
	return 0;
}

1;