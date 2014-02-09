#!/usr/bin/perl

package Fx;

use strict;
use warnings;
use feature 'state';

use Data::Dumper;
#http://search.cpan.org/~jdiepen/Audio-LADSPA-0.018/UserGuide/UserGuide.pod
# use Audio::LADSPA;

my $debug = 0;

###########################################################
#
#		 FX globals
#
###########################################################

state $LADSPA_PluginsList;

#build the plugin list if it doesn't exist
if (!defined $LADSPA_PluginsList) {
	print "FX: Loading LADSPA plugins list\n";
	$LADSPA_PluginsList = &get_LADSPA_PluginsList;
	# print Dumper $LADSPA_PluginsList;
}

###########################################################
#
#		 FX OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $effect = shift;
	my $midi_km = shift;
	
	#create fx object
	my $fx = {};
	
	#add fx name/ID
	$fx->{fxname} = $effect;

	#create CC array if midi control is enabled
	$fx->{generate_midi_CC} = $midi_km;
	$fx->{CCs} = () if $midi_km;
	
	bless $fx,$class;

	#init effect
	$fx->init if $effect ne "";

	return $fx;
}

sub init {
	my $fx = shift;
	
	my $effect = $fx->{fxname};

	# check if ecasound or LADSPA effect
	if ( $fx->LADSPAfxGetControls ) {
		print "   | |_adding LADSPA plugin $effect\n";
	}
	else {
		if ($fx->EcafxGetControls($effect)) {
			#construit la ligne d'effet ecs
			my $defaults = join ',', @{$fx->{defaultvalues}};
			$fx->{ecsline} = " -pn:$effect," . $defaults;
		
		}
	}
	# add midi controllers ? #TODO adapt to nonmixer
	$fx->Generate_eca_midi_CC if $fx->{generate_midi_CC};
}

###########################################################
#
#		 FX functions
#
###########################################################

sub update_current_value {
	my $ecafx = shift;
	my $index = shift;
	my $value = shift;

	#TODO verify if value is within range, return adequately for next actions
	#update value
	print "EcaFx : updating at index $index with value $value\n" if $debug;
	$ecafx->{currentvalues}[$index-1] = $value;
}

###########################################################
#
#		 FX TEST functions
#
###########################################################

sub is_param_ok {
	#grab parameter name in parameter
	my $fx = shift;
	my $paramtotest = shift;

	#iterate through each parameters
	my $nb = 0;
	foreach my $param (@{$fx->{paramnames}}) {
		$nb++;
		#return index (starting at 1)
		return $nb if $paramtotest eq $param;
	}
	return 0;
}

###########################################################
#
#		 LADSPA effect functions
#
###########################################################
sub is_LADSPA {
	my $fxhash = shift;
	my $fx = $fxhash->{fxname};

	#build the plugin list if it doesn't exist
	if (!defined $LADSPA_PluginsList) {
		$LADSPA_PluginsList = &get_LADSPA_PluginsList;
	}
	#look for the plugin ID
	if (defined $LADSPA_PluginsList) {
		if (exists $LADSPA_PluginsList->{$fx}) {
			return 1;
		}
	}
	return 0;
}

sub SanitizeLADSPAFx {
	my $fxhash = shift;
	my $samplerate = shift;

	#get number of parameter
	my @paramnames = @{$fxhash->{paramnames}};
	my $nb = $#paramnames;

	my @totest = ("lowvalues","highvalues","defaultvalues","currentvalues");
	foreach my $ref (@totest) {
		my @values = @{$fxhash->{$ref}};
		for my $i (0..$nb) {
			if ( $values[$i] =~ /\*/ ) {
				my $string = $values[$i];
				print " |_transforming $string into ";
				$string =~ s/srate/$samplerate/;
				$string =~ s/samplerate/$samplerate/;
				my $result = eval $string; #calculate the value

				#round to int
				if ( (exists $fxhash->{type}) and ($fxhash->{type} eq "integer") ) {
					use POSIX qw(ceil floor);
					print "(rounded) ";
					$result = floor($result);
				}
				print "$result\n";
				$values[$i] = $result; #update value
			}
		}
	}

}

sub LADSPAfxGetControls {
	my $fxhash = shift;
	my $fx = $fxhash->{fxname};

	#build the plugin list if it doesn't exist
	if (!defined $LADSPA_PluginsList) {
		$LADSPA_PluginsList = &get_LADSPA_PluginsList;
	}
	#look for the plugin ID
	if (defined $LADSPA_PluginsList) {
		if (exists $LADSPA_PluginsList->{$fx}) {
			#fill arrays
			my (@names, @defaults,@lowvals,@highvals);
			foreach my $control (sort keys $LADSPA_PluginsList->{$fx}{controls}) {
				push @names, $control if $control;
				push @lowvals, $LADSPA_PluginsList->{$fx}{controls}{$control}{min} if exists $LADSPA_PluginsList->{$fx}{controls}{$control}{min};
				push @highvals, $LADSPA_PluginsList->{$fx}{controls}{$control}{max} if exists $LADSPA_PluginsList->{$fx}{controls}{$control}{max};
				push @defaults, $LADSPA_PluginsList->{$fx}{controls}{$control}{default} if exists $LADSPA_PluginsList->{$fx}{controls}{$control}{default};
				#TODO do something with the control {type}
				#TODO deal with specific info like '...' '2*samplerate' ...Etc
			}
		
			#verify equal quantites of parameters
			if ( grep {$_ != $#defaults} ($#lowvals, $#highvals, $#names) ) {
					warn "Fx Error : incoherent number of parameters for plugin $fxhash->{fxname}";
					return 0;
			}
			if ( grep {$_ == -1} ($#defaults, $#lowvals, $#highvals, $#names) ) {
					warn "Fx Error : empty parameters for plugin $fxhash->{fxname}";
					return 0;
			}

			#insert values
			push( @{$fxhash->{paramnames}} ,@names);
			push( @{$fxhash->{defaultvalues}} ,@defaults);
			push( @{$fxhash->{currentvalues}} ,@defaults);
			push( @{$fxhash->{lowvalues}} ,@lowvals);
			push( @{$fxhash->{highvalues}} ,@highvals);
			$fxhash->{audio_io} = $LADSPA_PluginsList->{$fx}{audio_io};
			return 1;
		}
	}
	return 0;
}

sub get_LADSPA_PluginsList {
	#look for the plugins in installed dirs
	my @stdout = `listplugins`;
	my %PluginsFileList;

	#check if a plugin was found
	if (@stdout) {
		foreach my $line (@stdout) {
			chomp $line; #remove \n
			next unless ($line =~ /^\//g);
			#new plugin file
			chop($line); #remove trailing :
			print "---PluginFile: $line\n" if $debug;

			#query the plugin file for its plugins
			my $stdout = `analyseplugin $line`;

			my @pl = split(/\n{2,}/, $stdout); # note the new pattern

			# print "pluginfile $file has $#pl plugins\n";
			foreach my $plugininfo (@pl) {
				chomp($plugininfo);

				# print "-----------\n";
				# print $plugininfo,"\n";

				next unless $plugininfo; #return on empty line

			# Plugin Name: "C* Eq2x2 - Stereo 10-band equalizer"
			# Plugin Label: "Eq2x2"
			# Plugin Unique ID: 2594
			# Maker: "Tim Goetze <tim@quitte.de>"
			# Copyright: "2004-7"
			# Must Run Real-Time: No
			# Has activate() Function: Yes
			# Has deactivate() Function: No
			# Has run_adding() Function: Yes
			# Environment: Normal or Hard Real-Time
			# Ports:	"in.l" input, audio, -1 to 1
			# 	"in.r" input, audio, -1 to 1
			# 	"31 Hz" input, control, -48 to 24, default 0
			# 	"63 Hz" input, control, -48 to 24, default 0
			# 	"125 Hz" input, control, -48 to 24, default 0
			# 	"250 Hz" input, control, -48 to 24, default 0
			# 	"500 Hz" input, control, -48 to 24, default 0
			# 	"1 kHz" input, control, -48 to 24, default 0
			# 	"2 kHz" input, control, -48 to 24, default 0
			# 	"4 kHz" input, control, -48 to 24, default 0
			# 	"8 kHz" input, control, -48 to 24, default 0
			# 	"16 kHz" input, control, -48 to 24, default 0
			# 	"out.l" output, audio
			# 	"out.r" output, audio

				#get plugin info
				my ($Name) = $plugininfo =~ /Plugin Name: "(.*)"/;
				my ($Label) = $plugininfo =~ /Plugin Label: "(.*)"/;
				my ($ID) = $plugininfo =~ /Plugin Unique ID: (\d+)/;
				my ($Ports) = $plugininfo =~ /Ports: (.+)/sx;

				#get plugin controls
				my @controls = split /\n/ , $Ports;
				my $controls_hash = parse_controls(\@controls);
				my $audio_hash = parse_audio_io(\@controls);

				#update structure
				$PluginsFileList{$ID}{name} = $Name;
				$PluginsFileList{$ID}{label} = $Label;
				$PluginsFileList{$ID}{controls} = $controls_hash;
				$PluginsFileList{$ID}{audio_io} = $audio_hash;
				$PluginsFileList{$ID}{file} = $line;
			}
		}
	}
	else { die "Error : no plugin found, or comamnd error \n"; }
	
	print Dumper \%PluginsFileList if $debug;

	return \%PluginsFileList;
}

sub parse_controls {
	my $rawcontrols = shift;
	my %controls;

	my $nb = 1;
	foreach my $line (@{$rawcontrols}) {

		#ignore audio control definition
		next if (( $line =~ /input, audio/ ) or ( $line =~ /output, audio/ ));

		$line =~ s/\t//; #remove tab

		my ($name , $min, $max , $default ) = $line =~ /"(.*)" input, control, (.*) to (.*), default (.*)/;

		#some plugins may have bad formatting or missing info, return empty if we don't have every info
		next unless defined $name;

		#update hash
		$controls{$nb}{name} = $name;
		$controls{$nb}{min} = $min;
		$controls{$nb}{max} = $max;

		#default may contain more info (format like integer, or logaritmic)
		if ($default =~ /,/) {
			my ($def,$plus) = $default =~ /(.*), (.*)/;
			$controls{$nb}{default} = $def;
			$controls{$nb}{type} = $plus;
		}
		else {
			$controls{$nb}{default} = $default;
		}
		#increment number
		$nb++;
	}
	return \%controls;
}
sub parse_audio_io {
	my $rawcontrols = shift;
	my %controls;

	my $inputs = 0;
	my $outputs = 0;

	foreach my $line (@{$rawcontrols}) {
		#only audio control definition
		$inputs++ if ( $line =~ /input, audio/ ); 
		$outputs++ if ( $line =~ /output, audio/ );
	}
	$controls{inputs} = $inputs;
	$controls{outputs} = $outputs;
	return \%controls;
}

###########################################################
#
#		 ECASOUND effect functions
#
###########################################################

sub EcafxGetControls() {
	my $fx = shift;
	my $plugin = shift;

	return 0 if !$plugin; 
	
	#open effect file
	my $file;
	#TODO : path is not generic !!!!!!!!!!!!
	my $string = '';
	if (open($file, "<", "/home/seijitsu/2.TestProject/ecacfg/effect_presets")) {
		#get the effect parameters string
		my $found =0;
		my $tic = 0;
		while (<$file>) {
			if ( $tic == 1 ) {
				$string = $string . $_; #print $string,"\n";
				last if $_ !~ /\\$/; #print "notlast\n";
			}
			if (( /^$plugin\b/ ) && ( $tic eq 0) ) {
				$found = 1; #print "found : ",$_,"\n";
				$tic = 1 if $_ =~ /\\$/; #print "tic=",$tic,"\n";
				$string = $_;
			}
		}
		#close file
		close($file) || warn "close failed: $!";
		if ($found eq 0) {
			warn "Plugin $plugin not found\n";
			return 0;
		}
	}
	# TODO : fallback from project file to global file
	# "$ENV{HOME}/.ecasound/effect_presets";
	# warn "cannot open effect_presets file : $!";
	# return 0;

	my $paramnames = '';
	my $defaultvalues = '';
	my $lowvalues = '';
	my $highvalues = '';

	my @params = split("\n",$string);

	foreach (@params) {
		my $temp = $_;
		$paramnames = $temp if ($temp =~ /^-ppn/);
		$paramnames =~ s/-ppn:|\\$// if $paramnames;
		$paramnames =~ s/\s$// if $paramnames;
		$defaultvalues = $temp if ($temp =~ /^-ppd/);
		$defaultvalues =~ s/-ppd:|\\$// if $defaultvalues;
		$defaultvalues =~ s/\s$// if $defaultvalues;
		$lowvalues = $temp if ($temp =~ /^-ppl/);
		$lowvalues =~ s/-ppl:|\\$// if $lowvalues;
		$lowvalues =~ s/\s$// if $lowvalues;
		$highvalues = $temp if ($temp =~ /^-ppu/);
		$highvalues =~ s/-ppu:|\\$// if $highvalues;
		$highvalues =~ s/\s$// if $highvalues;
	}

	if ($debug) {
		print "params : $paramnames\n";
		print "default: $defaultvalues\n";
		print "lowval : $lowvalues\n";
		print "highval: $highvalues\n";
	}

	my @names = split(",",$paramnames);
	my @defaults = split(",",$defaultvalues);
	my @lowvals = split(",",$lowvalues);
	my @highvals = split(",",$highvalues);

	#verify equal quantites of parameters
	if ( grep {$_ != $#defaults} ($#lowvals, $#highvals, $#names) ) {
			warn "Error : incoherent number of parameters";
			return 0;
	}
	if ( grep {$_ == -1} ($#defaults, $#lowvals, $#highvals, $#names) ) {
			warn "Error : empty parameters";
			return 0;
	}

	#insert values
	push( @{$fx->{paramnames}} ,@names);
	push( @{$fx->{defaultvalues}} ,@defaults);
	push( @{$fx->{currentvalues}} ,@defaults);
	push( @{$fx->{lowvalues}} ,@lowvals);
	push( @{$fx->{highvalues}} ,@highvals);

	print Dumper $fx if $debug;
	return 1;
}

sub Generate_eca_midi_CC {
	#grab plugin name in parameter
	my $fx = shift;
	my $plugin = shift;
	
	my @lows = @{$fx->{lowvalues}};
	my @highs = @{$fx->{highvalues}};

	#iterate through each parameters
	my $nb =1;
	foreach my $param (@{$fx->{paramnames}}) {
		#get mim/max parameter range, and new unique CC/channel
		my ($CC,$channel) = &getnextCC();
		my $low = (shift @lows);
		my $high = (shift @highs);
		$fx->{ecsline} .= " -km:" . $nb++ . ",$low,$high,$CC,$channel";
		#push channel and CC values
		push (@{$fx->{CCs}},join(',',($CC,$channel)));
	}
	#remove trailing whitespace
	$fx->{ecsline} =~ s/\s+$//;
	return 1;
}
###########################################################
#
#		 MIDI functions
#
###########################################################

sub getnextCC {
	state $channel = 1;
	state $CC = 0;
	#verify end of midi CC range
	die "CC max range error!!\n" if (($CC eq 127) and ($channel eq 16));
	#CC range from 1 to 127, update channel if needed
	if ($CC == 127) {
		$CC = 0;
		$channel++;
	}
	#increment CC number
	$CC++;
	#return values
	return($CC,$channel);
}

1;