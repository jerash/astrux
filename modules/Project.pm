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
	#TODO
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
		bless $mixer->{ecasound} , EcaFile::;
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
		bless $song->{ecasound} , EcaFile::;
		#create the file
		$song->{ecasound}->create;
		#copy header from player mixer
		if (defined $project->{mixers}{players}{ecasound}{header}) {
			$song->{ecasound}{header} = $project->{mixers}{players}{ecasound}{header};
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
	if (1) {
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
		#TODO check how to send parameter !? its too late....
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
	# #TODO verify this thing
	# eval <FILE>;
	# close FILE;
}

#-------------------------------------LIVE USE-----------------------------------------------------

sub Start {
	my $project = shift;

	#TODO verify Project is valid

	# copy jack plumbing
	if ($project->{connections}{"jack.plumbing"} eq 1) {
		my $homedir = $ENV{"HOME"};
		warn "jack.plumbing already exists, file will be overwritten\n" if (-e "$homedir/.jack.plumbing");
		use File::Copy;
		copy("$project->{connections}{file}","$homedir/.jack.plumbing") or die "Copy failed: $!";
	}

	#verify that backends are active
	#TODO make a hash of backends/PID, or add to project {process}
	my $pid_jackd = qx(pgrep jackd);
	die "JACK server is not running" unless $pid_jackd;
	print "JACK server running with PID $pid_jackd";
	#TODO verify jack parameters

	my $pid_jpmidi = qx(pgrep jpmidi);
	die "JPMIDI server is not running" unless $pid_jpmidi;
	print "JPMIDI server running with PID $pid_jpmidi";

	if ($project->{linuxsampler}{enable}) {
		my $pid_linuxsampler = qx(pgrep linuxsampler);
		die "LINUXSAMPLER is not running" unless $pid_linuxsampler;
		print "LINUXSAMPLER running with PID $pid_linuxsampler\n";
	}
	
	# get song list
	my @songkeys = sort keys %{$project->{songs}};
	my @songlist;
	push (@songlist,$project->{songs}{$_}{song_globals}{friendly_name}) foreach @songkeys;
	print "SONGS :\n";
	print " - $_\n" foreach @songlist;

	# start mixers
	print "Starting mixers\n";
	my @pid_mixers;
	my $pid_mixer;
	# $SIG{CHLD} = 'IGNORE'; #don't wait for child status

	# #TODO verify if mixer is not already running
	#my $ps = qx(ps ax);
	#print "Using existing Ecasound server", return
	#	if  $ps =~ /ecasound/
	#	and $ps =~ /--server/
	#	and ($ps =~ /tcp-port=$port/ or $port == $default_port);
	foreach my $mixername (keys %{$project->{mixers}}) {
		print " - mixer $mixername\n";
		my $mixerfile = $project->{mixers}{$mixername}{ecasound}{ecsfile};
		my $path = $project->{project}{base_path}."/".$project->{project}{eca_cfg_path};
		my $port = $project->{mixers}{$mixername}{ecasound}{port};
		#print "ecasound -s $mixerfile -R $path/ecasoundrc --server --server-tcp-port=$port\n";
		my $command = "ecasound -q -s $mixerfile -R $path/ecasoundrc --server --server-tcp-port=$port > /dev/null 2>&1 &\n";
		#fork and exec
			$SIG{CHLD} = sub { wait };
			$pid_mixer = fork();
			if ($pid_mixer) {
				#we are parent
				print "new pid_mixer = $pid_mixer\n";
			   	push (@pid_mixers,$pid_mixer);
			}
			elsif (defined $pid_mixer) {
				#we are child
				print "$command\n";
			    exec( $command );
		        die "unable to exec: $!";
			}
			else {
				die "unable to fork: $!";
			}
			sleep(1);
			print ".../\n"
	}

	print "finished with table of pid =\n";
	print Dumper @pid_mixers;
	# load song chainsetups + dummy
	# start plumbing

	# now should have sound

}

1;