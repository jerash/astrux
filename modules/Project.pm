#!/usr/bin/perl

package Project;

use strict;
use warnings;
use Data::Dumper;

use Mixer;
use Song;
use Plumbing;
use Bridge;

#-------------------------------------GENERATION-----------------------------------------------------

sub new {
	my $class = shift;
	my $ini_file = shift;

	#init structure
	my $project = {
		'mixers' => {},
		'songs' => {},
	};
	bless $project,$class;

	#if parameter exist, fill from ini file
	$project->init($ini_file) if defined $ini_file;

	return $project; 
}

sub init {
	#grap Project object from argument
	my $project = shift;
	my $ini_project = shift;

	#merge project ini info
	%$project = ( %{$ini_project} , %$project );

	#------------------Add mixers-----------------------------
	$project->AddMixers;	

	#------------------Add songs------------------------------
	$project->AddSongs;	

	#----------------Add plumbing-----------------------------
	$project->AddPlumbing;

	#----------------Add bridge-----------------------------
	$project->AddOscMidiBridge;
}

sub AddMixers {
	my $project = shift;

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

	#build path to songs folder
	my $songs_path = $project->{project}{base_path} . "/" . $project->{project}{songs_path};
	
	#get song list
	my @songs_folders = <$songs_path/*>;

	#iterate through each song fodlder
	foreach my $folder (@songs_folders){

		#ignore files, use directories only
		next if (! -d $folder);
		print "Project: Entering song folder : $folder\n";

		#crete a song object
		my $song = Song->new($folder);

		#update the project with song info
		$project->{songs}{$song->{song_globals}{name}} = $song;
	}
}

sub AddOscMidiBridge {	
	my $project = shift;
	
	$project->{bridge}{status} = "notcreated";
	bless $project->{bridge}, Bridge::;

	my @bridgelines = Bridge->create_lines($project);
	#print Dumper @bridgelines;
	$project->{bridge}{lines} = \@bridgelines;
}

sub AddPlumbing {
	my $project = shift;

	my $plumbingfilepath = $project->{project}{base_path}."/".$project->{project}{output_path}."/jack.plumbing";
	$project->{connections}{file} = $plumbingfilepath;
	bless $project->{connections} , Plumbing::;

	my @plumbing_rules = Plumbing->create_rules($project);
	#print Dumper @plumbing_rules;
	$project->{connections}{rules} = \@plumbing_rules;
}

sub GenerateFiles {
	my $project = shift;

	#----------------ECASOUND FILES------------------------
	#for each mixer, create the ecasound mixer file
	foreach my $mixername (keys %{$project->{mixers}}) {
		#shorcut name
		my $mixer = $project->{mixers}{$mixername};
		#create path to ecs file
		my $ecsfilepath = $project->{project}{base_path}."/".$project->{project}{output_path}."/".$mixer->{ecasound}{name} . ".ecs";
		#add path to ecasound info
		$mixer->{ecasound}{ecsfile} = $ecsfilepath;
		#bless structure to access data with module functions
		bless $mixer->{ecasound} , EcaEngine::;
		#create the file
		$mixer->{ecasound}->create;
		#add ecasound header to file
		$mixer->{ecasound}->build_header;
		#get chains from structure
		$mixer->get_ecasoundchains;
		#add chains to file
		$mixer->{ecasound}->add_chains;
		#TODO verify is the generated file can be opened by ecasound
		#$mixer->{ecasound}->verify;
	}

	#for each song, create the ecasound player file		
	foreach my $songname (keys %{$project->{songs}}) {
		#shorcut name
		my $song = $project->{songs}{$songname};
		#create path to ecs file
		my $ecsfilepath = $project->{project}{base_path}."/songs/$songname/chainsetup.ecs";
		#add path to song info
		$song->{ecasound}{ecsfile} = $ecsfilepath;
		#bless structure to access data with module functions
		bless $song->{ecasound} , EcaEngine::;
		#create the file
		$song->{ecasound}->create;
		#copy header from player mixer
		if (defined $project->{mixers}{players}{ecasound}{header}) {
			$song->{ecasound}{header} = $project->{mixers}{players}{ecasound}{header};
			#replace -n:"players" with song name to have unique chainsetup name
			$song->{ecasound}{header} =~ s/-n:\"players\"/-n:\"$songname\"/;
		}
		else {
			die "Error : can't find a player mixer header\n";
		}
		#add ecasound header to file
		$song->build_song_header;
		#add chains to file
		$song->add_songfile_chain;
		#TODO verify is the generated file can be opened by ecasound
		#$song->{ecasound}->verify;
	}

	#----------------PLUMBING FILE------------------------
	if ($project->{connections}{"jack.plumbing"} == 1) {
		#we're asked to generate the plumbing file
		my $plumbingfilepath = $project->{project}{base_path}."/".$project->{project}{output_path}."/jack.plumbing";
		$project->{connections}{file} = $plumbingfilepath;
		# bless $project->{connections} , Plumbing::;
		print "Project: creating plumbing file $plumbingfilepath\n";
		$project->{connections}->create;
		$project->{connections}->save;
	}
	else {
		print "Project: jack.plumbing isn't defined as active. Not creating file.";
	}

	#----------------BRIDGE FILE------------------------
	#TODO define bridge option
	if ($project->{controls}{bridge} == 1) {
		#we're asked to generate the bridge file
		my $filepath = $project->{project}{base_path} . "/" . $project->{project}{output_path} . "/oscmidistate.csv";
		$project->{bridge}{file} = $filepath;
		print "Project: creating bridge file $filepath\n";
		$project->{bridge}->create;
		$project->{bridge}->save;
	}
	else {
		print "Project: midi/osc bridge isn't defined as active. Not creating file.";
	}

}

sub SaveTofile {
	my $project = shift;
	my $outfile = shift;
#Data::Dumper
	# $Data::Dumper::Purity = 1;
		#open FILE, ">$outfile" or die "Can't open file to write:$!";
	# open FILE, ">project.cfg" or die "Can't open file to write:$!";
	# print FILE Dumper $project;
	# close FILE;
#Storable
	 use Storable;
	#>>>works but output is not human readable
	store $project, $outfile;
	# $hashref = retrieve('file');
#use JSON::XS
	# $utf8_encoded_json_text = encode_json $perl_hash_or_arrayref;
 	# $perl_hash_or_arrayref  = decode_json $utf8_encoded_json_text;
}

sub LoadFromFile {
	my $project = shift;
	my $infile = shift;

	use Storable;
	$project = retrieve($infile);

#Data::Dumper
	# #restore
	# open FILE, $infile;
	# undef $/;
	# eval <FILE>;
	# close FILE;
}

1;