#!/usr/bin/perl

package EcaFile;

use strict;
use warnings;

use Data::Dumper;

sub create {
	#create the file (overwrite)
	my $ecafile = shift;

	#get path to file
	my $path = $ecafile->{ecsfile};
	#print "---Ecafile:create\n path = $path\n";
	die "no path to create ecs file\n" unless (defined $path);
	#create an empty file (overwrite existing)
	#TODO : check for existence and ask for action
	open my $handle, ">$path" or die $!;
	#update mixer status
	$ecafile->{status} = "new";
	#close file
	close $handle;
}

sub build_header {
	my $ecafile = shift;

	#print "--Ecafile:build_header\n header = $header\n";
	die "ecs file has not been created" if ($ecafile->{status} eq "notcreated");
	#open file handle
	open my $handle, ">>$ecafile->{ecsfile}" or die $!;
	#append to file
	print $handle $ecafile->{header} or die $!;
	#close file
	close $handle or die $!;
	#update status
	$ecafile->{status} = "header";
}

sub add_chains {
	my $ecafile = shift;

	#open file in add mode
	open my $handle, ">>$ecafile->{ecsfile}" or die $!;
	#append to file
	print $handle "$_\n" for @{$ecafile->{all_chains}};
	#close file
	close $handle or die $!;
	#update status
	$ecafile->{status} = "created";
}

sub verify {
	#check if chainsetup file is valid
	my $ecaecs = shift;
	unless ($ecaecs->{status} eq "created") {
		warn "cannot verify an ecs file not containing chains\n";
		return;
	}
	#open it with ecasound and check return code
	
	$ecaecs->{status} = "verified";
}

1;