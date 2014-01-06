#!/usr/bin/perl
use strict;
use warnings;

use MIDI;
#http://search.cpan.org/~conklin/MIDI-Perl-0.83/lib/MIDI.pm
#http://search.cpan.org/~conklin/MIDI-Perl-0.83/lib/MIDI/Event.pm#EVENTS

# Dump a MIDI file's text events
  die "No filename" unless @ARGV;
  use MIDI;  # which "use"s MIDI::Event;
  MIDI::Opus->new( {
     "from_file" => $ARGV[0],
     "exclusive_event_callback" => sub{print "$_[0] $_[2]\n"},
     #"include" => \@MIDI::Event::Text_events
     "include" => \@MIDI::Event::All_events
   } ); # These options percolate down to MIDI::Event::decode
  exit;