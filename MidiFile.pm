#!/usr/bin/perl

package MidiFile;

use strict;
use warnings;

use MIDI;
#http://search.cpan.org/~conklin/MIDI-Perl-0.83/lib/MIDI.pm
#http://search.cpan.org/~conklin/MIDI-Perl-0.83/lib/MIDI/Event.pm#EVENTS
#great calculation infos from http://www.lastrayofhope.com/2009/12/23/midi-delta-time-ticks-to-seconds/

my $debug = 0;

sub get_timed_events {
  my $file = shift;
  die "file $file not found" unless -e $file;

  #import midi file
  my $song = MIDI::Opus->new( {
   "from_file" => $ARGV[0],
  } );

  #get song tracks references
  my @tracks = $song->tracks;

  #for each track, create an event list with absolute ticks reference
  my $nb = 0;
  my $absolut_ticks;
  my $linear_tracks;
  foreach my $track (@tracks) {
    $absolut_ticks = 0;
    my @events = $track->events;
    my @linear_events;
    foreach my $event (@events) {
      # $event[0] = event type
      # $event[1] = delta ticks
      # what is following depends on event type
      $absolut_ticks += $event->[1];
      #update event with absolute ticks
      $event->[1] = $absolut_ticks;
      #push to linear events array
      push @linear_events , $event;
    }
    $linear_tracks->{$nb} = \@linear_events;
    $nb++;
  }

  #now we have absolute ticks, we can merge and filter out necessary events
  my @absolute_tick_events;
  foreach my $track (keys $linear_tracks) {
    foreach my $event (@{$linear_tracks->{$track}}) {
      push (@absolute_tick_events , $event) 
        if ( ($event->[0] eq "set_tempo") or
             ($event->[0] eq "marker") or
             ($event->[0] eq "time_signature") );
    }
  }

  #we should have set_tempo and time_signature at tick position 0
  my $time_signature;
  my $set_tempo;
  my $position = 0;
  while (($position eq 0) and ((!defined $time_signature) or (!defined $set_tempo))) {
    my $event = shift @absolute_tick_events;
    $time_signature = $event if $event->[0] eq "time_signature";
    $set_tempo = $event if $event->[0] eq "set_tempo";
    die "We should not found a marker event so soon\n" if $event->[0] eq "marker";
    $position = $event->[1];
  }
  die "could not find time_signature and set_tempo at position 0\n" unless ((defined $time_signature) and (defined $set_tempo));

  #get song ticks
  my $TPQN = $song->ticks;
  die "could not get song ticks parameter\n" unless (defined $TPQN);
  #calculate time signature denominator
  my $time_numerator = $time_signature->[2];
  my $time_denominator = 2**($time_signature->[3]);
  #calculate tempo in BPM and tick duration
  my $MicrosecondsPerQuarterNote = $set_tempo->[2];
  my $BPM = ( 60000000 / $MicrosecondsPerQuarterNote ) * ( $time_denominator / 4 );
  my $tick_duration = &get_tick_duration($TPQN,$MicrosecondsPerQuarterNote);

  print "Song ticks is $TPQN\nStart tempo is $BPM\nStart Time signature is $time_numerator/$time_denominator\n" if $debug;

  #now we have only needed elements, we can calculate position in seconds
  my @absolute_seconds_events;
  my $current_seconds_position = 0;
  my $last_tick_change = 0;
  my $last_seconds_counter = 0;
  foreach my $event (@absolute_tick_events) {
    my @info;
    #get current position in seconds
    ($last_seconds_counter eq 0) ? $current_seconds_position = $event->[1] * $tick_duration : 
          $current_seconds_position = $last_seconds_counter + (($event->[1] - $last_tick_change) * $tick_duration);
    #update tick duration and last second counter if we have a new tempo
    if ($event->[0] eq "set_tempo") {
      $last_tick_change = $event->[1];
      $last_seconds_counter = $current_seconds_position;
      #get new tick duration
      $MicrosecondsPerQuarterNote = $event->[2];
      $tick_duration = &get_tick_duration($TPQN,$MicrosecondsPerQuarterNote);  
      $BPM = sprintf "%.1f", ( 60000000 / $MicrosecondsPerQuarterNote ) * ( $time_denominator / 4 );
      @info = ($current_seconds_position,$event->[0],$BPM);
    }
    #export marker
    elsif ($event->[0] eq "marker") {
      @info = ($current_seconds_position,$event->[0],$event->[2]);
    }
    #update time signature
    elsif ($event->[0] eq "time_signature") {
      $time_numerator = $event->[2];
      $time_denominator = 2**($event->[3]);
      @info = ($current_seconds_position,$event->[0],"$time_numerator/$time_denominator");
    }
    else {
      die "oups what is $event->[0] doing here ?";
    }
    push @absolute_seconds_events , \@info;
  }
  return @absolute_seconds_events;
}

sub dump_timed_events {
  my $timed_events = shift;

  foreach my $event (@{$timed_events}) {
    my $second = sprintf "%.3f", $event->[0];
    #update tick duration if we have a new tempo
    if ($event->[1] eq "set_tempo") {
     print "$second : new tempo $event->[2]\n";
    }
    #export marker
    elsif ($event->[1] eq "marker") {
      print "$second : Marker $event->[2]\n";
    }
    #update time signature
    elsif ($event->[1] eq "time_signature") {
      print "$second : New Time signature $event->[2]\n";
    }
  }
}

sub get_timed_markers {
  my $timed_events = shift;

  my @markers;
  foreach my $event (@{$timed_events}) {
    if ($event->[1] eq "marker") {
      $event->[2] =~ s/;/_/; #replace ; so cvs file will be ok
      push @markers , $event;
    }
  }
  return @markers;
}

sub get_tick_duration {
  my $tpqn = shift;
  my $MicrosecondsPerQuarterNote = shift;
  return ($MicrosecondsPerQuarterNote / 1000000) / $tpqn;
}

#------------use example---------------
# die "No source File\n" unless $ARGV[0];
# die "No destination File\n" unless $ARGV[1];
# my @songevents = &get_timed_events($ARGV[0]);
# &dump_timed_events(\@songevents);
# my @markers_list = &get_timed_markers(\@songevents);

# open FILE,">$ARGV[1]" or die "$!";
# print FILE "$_->[0];$_->[2]\n" for @markers_list;
# close FILE;
#------------use example---------------

1;