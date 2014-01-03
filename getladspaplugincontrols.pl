#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

#-------------------------------------------------------------------------
#
#  Get a hash containing all parameters and controls for a LADSPA plugin
#  (will work with part of the name as first found by grep, or can use unique ID)
#-------------------------------------------------------------------------
#
# sinon voir aussi http://search.cpan.org/~jdiepen/Audio-LADSPA-0.021/Plugin/Plugin.pod

#check for existing single argument
die "usage : getcontrols \“pluginname\" \n" until $#ARGV eq 0; 

#name of plugin passed as argument (may be incomplete)
my $plugin = $ARGV[0];

#-------------------------------------------------------------------------
#look for the plugin in installed dirs (first found is used)
my @stdout = `listplugins | grep $plugin -B1`;
chomp @stdout;
#check if a plugin was found
if (@stdout) {
	print "Warning : More than one plugin found, try to use the first in list\n" if (scalar @stdout > 2);
	#get the complete plugin name
	$stdout[1] =~ /^(.*) \(/;
	die "Error : unable to get plugin name\n" until $1;
	my $temp = $1;
	$temp =~ s/^\s+|\s+$//g; #remove whitspace
	print "Found plugin : $temp\n";
}
else {
	die "Error : plugin $plugin not found\n";
}

#get the plugin path to .so file
my $file = $stdout[0];
die "Error : can't get path to plugin\n" until $file;
chop($file) if $file;

#get the list of controls for this plugin
my @rawcontrols = `analyseplugin $file | grep "input, control"`;
die "Error : can't get list of controls for plugin\n" until @rawcontrols;
chomp @rawcontrols;

#-------------------------------------------------------------------------
# Controls hash creation
# %controls : position_order => (name,min,max,default)
my %controls;
my @defaults;

my $count = 1;
foreach (@rawcontrols) {
	# @control=(min,max,default,position)
	my @control;
	#sépare la ligne sur les virgules
	my @parts = split(/,/ , $_);
	#remove whitspace in each part
	for (@parts) {
		$_ =~ s/^\s+|\s+$//g;
	}
	#récupère le nom dans la première part, entre ""
	$parts[0] =~ /"(.*)"/;
	$control[0] = $1;
	#récupération ou création du min
	if ($parts[2] eq "toggled") {
		$control[1] = 0;
	}
	elsif ($parts[2] =~ /(.*) to / ) {
		$control[1] = $1;
		$control[1] =~ s/^\s+|\s+$//g; #remove whitspace
	}
	else {
		die "can't create min\n";
	}
	#récupération ou création du max
	if ($parts[2] eq "toggled") {
		$control[2] = 1;
	}
	elsif ($parts[2] =~ /to (.*)/ ) {
		$control[2] = $1;
		$control[2] =~ s/^\s+|\s+$//g; #remove whitspace
		$control[2] = 999 if ($control[2] eq "..."); #put number if not specified
	}
	else {
		die "can't create max\n";
	}
	#récupération ou création du défault
	$parts[3] =~ /default (.*)/;
	$control[3] = $1;
	#add value to defaults table
	push(@defaults,$control[2]);
	#increment count to keep trace of order or controls
	#add parts to @controls
	push( @{$controls{$count++}} ,@control);
#--LOOP END
#print Dumper @control;
}

#-------------------------------------------------------------------------
print Dumper \%controls;
print Dumper @defaults;

my $kmlist;
