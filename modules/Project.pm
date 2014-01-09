#!/usr/bin/perl

package Project;

use strict;
use warnings;
use Data::Dumper;

use Mixer;
use Player;

use Exporter;
our @ISA = 'Exporter';
our @EXPORT = qw($baseurl);

#TODO test global variable export
our $baseurl = "/home/seijitsu/";

sub new {
	my $class = shift;
	my $ini_file = shift;

	#init structure
	my $project = {
		'mixers' => {},
		'songs' => {},
		'rules' => {},
	};
	bless $project,$class;

	#if parameter exist, fill from ini file
	$project->init($ini_file) if defined $ini_file;

	return $project; 
}

sub init {
	#grap Project object from argument
	our $project = shift;
	my $ini_project = shift;


	#merge project ini info
	#%$project = ( %{$ini_project->{project}} , %$project );
	%$project = ( %{$ini_project} , %$project );

	#------------------Add mixers-----------------------------
	$project->AddMixers;	

	#------------------Add songs------------------------------
	#----------------Add plumbing-----------------------------
	
}

sub AddMixers {
	my $project = shift;
	#print Dumper $project;

	#build path to mixers files
	my $mixers_path = $project->{project}{base_path} . "/" . $project->{project}{mixers_path};
	
	#iterate through each mixer file
	my @files = <$mixers_path/*.ini>;
	foreach my $mixerfile (@files) {

		#create mixer
	 	print "Project: Creating mixer from $mixerfile\n";
	 	my $mixer = Mixer->new($mixerfile);
		$project->{mixers}{$mixer->{ecasound}{name}} = $mixer;
	}

	#verify if there is one "main" mixer
	if (!exists $project->{mixers}{"main"} ) {
		die "!!!! main mixer must exist !!!!!\n";
	}
}

sub AddSongs {
	my $project = shift;
# 	#my $player = Player->new();
	#TODO : deal with players ecs chains
	return;
}

sub CreateEcsFiles {
	my $project = shift;

	#for each mixer, create the ecasound mixer file
	foreach my $mixername (keys %{$project->{mixers}}) {
		#shorcut name
		my $mixer = $project->{mixers}{$mixername};
		#create path to ecs file
		my $ecsfilepath = $project->{project}{base_path}."/".$project->{project}{output_path}."/".$mixer->{ecasound}{name} . ".ecs";
		#add path to ecasound info
		$mixer->{ecasound}{ecsfile} = $ecsfilepath;
		#bless structure to access data with module functions
		bless $mixer->{ecasound} , EcaFile::;
		#create the file
		$mixer->{ecasound}->create;
		#add ecasound header to file
		$mixer->{ecasound}->build_header;
		#get chains from structure
		$mixer->get_ecasoundchains;
		#add chains to file
		$mixer->{ecasound}->add_chains;
		#verify is the generated file can be opened by ecasound
		#$mixer->{ecasound}->verify;
	}

	#for each song, create the players files if necessary

}

sub CreateOscMidiBridge {	
	# 	#------------------------BRIDGE-----------------------------------
	# 	#create/reset the oscmidipath file
	# 	Bridge::Init_file();	
	#
	# 	Bridge::Close_file();
	return;
}
sub CreatePlumbing {
	# 	#------------------------PLUMBING-----------------------------------
	# 	#create/reset the plumbing file
	# 	my $plumbing = Plumbing->new($ini_project);	
	#
	# 	$plumbing->Close;
	return;
}


1;