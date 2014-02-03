astrux
======

A live-oriented setup creation tool based on ecasound and non-mixer.
Written as Perl modules.

This is an ongoing project by Raphaël Mouneyres, usable though.

To correctly build a project, you have to follow some rules :
- the build wants correctly formatted INI files
- the build want a correct folder structure
- you have a project.ini file on the project root folder
- you define mixers, with at least a 'main' mixer
- in each mixer, you define channels
- for each song folder you have a song.ini file
some error checks are done so the script will die.

here's a project.ini example
  [project]
  name = MyProject
  version = 1.0
  base_path = /home/user/myproject
  config_path = config
  mixers_path = mixer
  output_path = files
  eca_cfg_path = ecacfg
  songs_path = songs
  [JACK]
  start = jackd -R -P89 -d alsa -d hw:DSP -p128 -n2 &
  [midi_player]
  backend = jpmidi
  enable = 0
  port = 2013
  [MIDI]
  enable = 1
  [OSC]
  enable = 1
  ip = 192.168.0.15
  inport = 8000
  outport = 9000
  sendback = 1
  [TCP]
  enable = 1
  port = 8989
  [CLI]
  enable = 0
  [osc2midi]
  enable = 1
  [connections]
  jack.plumbing = 1
  #jack.connect = 0
  [linuxsampler]
  enable = 0
  presetfolder=sampler
  port = 8888

here's a one channel mixer ini file example
  [mixer_globals]
  type = main
  engine = ecasound
  port = 2868
  name = main
  sync = 0
  generatekm = 1
  buffersize = 128
  realtime = 50
  z = nodb,nointbuf,noxruns
  mixmode = avg
  midi = alsaseq,astrux:0
  [mic1]
  type = hardware_in
  status = active
  friendly_name = Leader
  group = 1
  channels = 1
  connect_1 = system:capture_1
  insert = 
  can_be_backed = no
  generatekm = 1
  
here's a song.ini example 
  [song_globals]
  name = mysong
  #this name here is the same as containing folder name
  friendly_name = A name with spaces
  tempo = 86
  autostart = 0
  autoload = 
  [players_slot_1]
  type = player
  filename = myfile.wav
  
