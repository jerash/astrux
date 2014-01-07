#!/usr/bin/perl

package EcaEcs;

use strict;
use warnings;

sub new {
	my $class = shift;
	my $project = shift;
	my $ini_name = shift;
	
	my $config = $project->{$ini_name};
	#un object EcaEcs contient
	# 1. le chemin d'accès au fichier ecs
	# 2. une référence vers un fichier ecs
	# 3. une copie de la section ini correspondante
	my $path = $project->{'project'}{'filesfolder'} . "/" . $config->{'name'} . ".ecs";
	open my $ecsfile, ">$path" or die $!;

	my $ecaecs = {};
	$ecaecs->{'path'} = $path;
	$ecaecs->{'file'} = $ecsfile;
	$ecaecs->{'config'} = $config;

	bless $ecaecs, $class;
	return $ecaecs;
}

sub build_header {
	my $ecaecs = shift;
	my $synchro = shift;
	
	my $name = $ecaecs->{'config'}{'name'};
	my $header = "#GENERAL\n";
	$header .= "-b:".$ecaecs->{'config'}{'buffersize'} if $ecaecs->{'config'}{'buffersize'};
	$header .= " -r:".$ecaecs->{'config'}{'realtime'} if $ecaecs->{'config'}{'realtime'};
	my @zoptions = split(",",$ecaecs->{'config'}{'z'});
	foreach (@zoptions) {
		$header .= " -z:".$_;
	}
	$header .= " -n:\"$name\"";
	$header .= " -z:mixmode,".$ecaecs->{'config'}{'mixmode'} if $ecaecs->{'config'}{'mixmode'};
	$header .= " -G:jack,$name,notransport" if ($ecaecs->{'config'}{'sync'} == 0);
	$header .= " -G:jack,$name,sendrecv" if ($ecaecs->{'config'}{'sync'});
	$header .= " -Md:".$ecaecs->{'config'}{'midi'} if $ecaecs->{'config'}{'midi'};
	#add header to file
	my $file = $ecaecs->{'file'};
	print $file $header;
}

1;