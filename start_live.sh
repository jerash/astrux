echo -e "\n\n\n####################################################"
echo -e "#     WELCOME TO SEIJITSU LIVE SETUP CONSOLE!      #"
echo -e "#################################################### \n\n"

while [ 1 ]; do

    echo -e "\n\nPress q to quit, p to see current processes"
    echo -e "r to restart jack.plumbing, m to restart mididings, 2 to run project2 ";
    # lets read the key press to $key variable:
    # -e means that after input comes a line feed and
    # -n 1 reads just one key without waiting enter.
    read -e -n 1 key
    echo -e "\n\n"

    if [ $key == "q" ] || [ $key == "Q" ]; then
        echo "Are you sure you want to quit? [y/n]"
        read -e -n 1 key
        if [ $key == "y" ]; then
            break;
        fi
    elif [ $key == "p" ] || [ $key == "P" ]; then
        jobs
    elif [ $key == "r" ] || [ $key == "R" ]; then
        if pgrep jack.plumbing
         then
          echo killing jack.plumbing
          killall jack.plumbing
        fi
        jack.plumbing &
        JACKPLUMBING_PID=$!
        echo jack.plumbing restarted with PID $JACKPLUMBING_PID
        sleep 1
    elif [ $key == "m" ] || [ $key == "M" ]; then
        echo TODO
    elif [ $key == "2" ]; then
        echo "--------------PROJECT2----------------"

        #cd 2.TestProject
        echo "--- Starting ecasound channels---"
        #start channels
        ECASOUNDCHANNELS_PID=$(pgrep -f 'ecasound -s mixer4.ecs')
        if [[ -n $ECASOUNDCHANNELS_PID ]]
         then
          echo ecasound channels tourne avec PID $ECASOUNDCHANNELS_PID
         else
          ecasound -s mixer4.ecs -R ecacfg/ecasoundrc --server --server-tcp-port=2000 --osc-udp-port=7000 &
          ECASOUNDCHANNELS_PID=$!
          sleep 2
        fi

        echo "--- Starting ecasound player---"
        #start channels
        ECASOUNDPLAYERS_PID=$(pgrep -f 'ecasound -s 0.nosong/dummy.ecs')
        if [[ -n $ECASOUNDPLAYERS_PID ]]
         then
          echo ecasound players tourne avec PID $ECASOUNDPLAYERS_PID
         else
          ecasound -s 0.nosong/dummy.ecs -R ecacfg/ecasoundrc --server --server-tcp-port=2001 --osc-udp-port=7001 &
          ECASOUNDPLAYERS_PID=$!
          sleep 1
        fi
        echo "cs-load 1.TestSong1/jamesbond.ecs" | nc -C localhost 2001
        echo "cs-load 2.TestSong2/hedgehog.ecs" | nc -C localhost 2001

        echo "--- NOW IN SONG MODE ---"
        
        while [ 1 ]; do

          JACKPLUMBING_PID=$(pgrep jack.plumbing)
          if [[ -n $JACKPLUMBING_PID ]]
           then
            #echo SYSTEM: jack.plumbing est deja en tache de fond
            #echo JACKPLUMBING_PID $JACKPLUMBING_PID
            echo -
           else
            echo "--- Starting jack.plumbing ---"
            jack.plumbing &
            sleep 1
          fi

          #echo "Available songs :\n"
          #ls -d [1-9]*/
          echo -e "\n\n"
          echo "Type number of the song, s to start, S to stop, b goto beginning"
          # -t3 pour tourner toutes les 3 secondes et relancer plumbin si ca plante
          read -t 3 -e -n 1 key
          echo -e "\n\n"
          if [ $key == "b" ]; then
            echo "setpos 0" | nc -C localhost 2001
          elif [ $key == "s" ]; then
            echo "start" | nc -C localhost 2001
          elif [ $key == "S" ]; then
            echo "stop" | nc -C localhost 2001
          elif [ $key == "1" ]; then
            echo "stop" | nc -C localhost 2001
            echo "cs-disconnect" | nc -C localhost 2001
            echo "cs-select jamesbond" | nc -C localhost 2001
            echo "cs-connect" | nc -C localhost 2001
            echo "setpos 0" | nc -C localhost 2001
            echo "start" | nc -C localhost 2001
          elif [ $key == "2" ]; then
            echo "stop" | nc -C localhost 2001
            echo "cs-disconnect" | nc -C localhost 2001
            echo "cs-select hedgehog" | nc -C localhost 2001
            echo "cs-connect" | nc -C localhost 2001
            echo "setpos 0" | nc -C localhost 2001
            echo "start" | nc -C localhost 2001
          elif [ $key == "q" ] || [ $key == "Q" ]; then
            break
          fi

          sleep 1
          jack_lsp -c > /dev/null 2>&1
        done

    fi

done

#cleaning
killall ecasound

