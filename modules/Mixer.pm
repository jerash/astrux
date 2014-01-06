#!/usr/bin/perl

package Mixer;

use strict;
use warnings;

#use Config::IniFiles;
use EcaEcs;

sub NewMixer {
	my $class = shift;
	my $project = shift;
	my $name = shift;
	my $ini_name = "mixer_$name";
	#un objet mixer a:
	# 1. un fichier de sortie 
	my $ecasound = EcaEcs->new($project,$ini_name);
	$ecasound->build_header($project,$ini_name,'nosync');
	# 2. des paramètres
	my %mixer = ( 
		"ecasound" , $ecasound,
		"name" , $project->val($ini_name,'name'),
		"port" , $project->val($ini_name,'port'),
		"config_folder" , $project->val($ini_name,'configfolder'),
		"midi" , $project->val($ini_name,'generatekm') );
	bless \%mixer, $class;
	return \%mixer;
}


sub add_track {
	#my $create_midi_CC = $ini_project->val('ecasound','generatekm'); #enable/disable midiCC control with -km switch
	
}

sub get_name {
	my $self = shift;
	return $self->{"name"};
}
sub get_port {
	my $self = shift;
	return $self->{"port"};
}
sub is_midi_controllable {
	my $self = shift;
	return $self->{"midi"};
}

1;